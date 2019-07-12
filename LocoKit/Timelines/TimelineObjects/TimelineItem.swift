//
//  TimelineItem.swift
//  LocoKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import GRDB
import LocoKitCore
import CoreLocation
import CoreMotion

/// The abstract base class for timeline items.
open class TimelineItem: TimelineObject, Hashable, Comparable, Codable {

    // MARK: TimelineObject

    public var objectId: UUID { return itemId }
    public weak var store: TimelineStore? { didSet { if store != nil { store?.add(self) } } }
    public var transactionDate: Date?
    public var lastSaved: Date?
    public var hasChanges: Bool = false

    public var classifier: MLCompositeClassifier? { return store?.recorder?.classifier }

    public var mutex = PThreadMutex(type: .recursive)

    public let itemId: UUID

    public var source: String = "LocoKit"

    open var isMergeLocked: Bool {
        if isCurrentItem && !isWorthKeeping { return true }
        return false
    }

    public var hasBrokenEdges: Bool {
        return hasBrokenPreviousItemEdge || hasBrokenNextItemEdge
    }

    public var hasBrokenPreviousItemEdge: Bool {
        if deleted { return false }
        if previousItem == nil { return true }
        return false
    }

    public var hasBrokenNextItemEdge: Bool {
        if deleted { return false }
        if nextItem == nil && !isCurrentItem { return true }
        return false
    }

    public private(set) var deleted = false
    open func delete() {
        deleted = true
        previousItem = nil
        nextItem = nil
        hasChanges = true
        save()
    }

    private var updatingPedometerData = false
    private var pedometerDataIsStale = false

    public private(set) var _stepCount: Int?
    open var stepCount: Int? {
        get {
            if CMPedometer.isStepCountingAvailable() && (_stepCount == nil || pedometerDataIsStale) {
                updatePedometerData()
            }
            return _stepCount
        }
        set(newValue) { _stepCount = newValue }
    }

    public private(set) var _floorsAscended: Int?
    public var floorsAscended: Int? {
        if CMPedometer.isFloorCountingAvailable() && (_floorsAscended == nil || pedometerDataIsStale) {
            updatePedometerData()
        }
        return _floorsAscended
    }

    public private(set) var _floorsDescended: Int?
    public var floorsDescended: Int? {
        if CMPedometer.isFloorCountingAvailable() && (_floorsDescended == nil || pedometerDataIsStale) {
            updatePedometerData()
        }
        return _floorsDescended
    }

    private var _samples: [PersistentSample]?
    open var samples: [PersistentSample] {
        return mutex.sync {
            if let existing = _samples { return existing }
            if lastSaved == nil {
                _samples = []
            } else if let store = store {
                _samples = store.samples(where: "timelineItemId = ? AND deleted = 0 ORDER BY date",
                                         arguments: [itemId.uuidString])
            } else {
                _samples = []
            }
            return _samples!
        }
    }

    // MARK: - Relationships

    public var previousItemId: UUID? {
        didSet {
            if previousItemId == itemId { fatalError("Can't link to self") }
            if oldValue != previousItemId { hasChanges = true; save() }
        }
    }
    public var nextItemId: UUID? {
        didSet {
            if nextItemId == itemId { fatalError("Can't link to self") }
            if oldValue != nextItemId { hasChanges = true; save() }
        }
    }

    private weak var _previousItem: TimelineItem?
    public var previousItem: TimelineItem? {
        get {
            if let cached = _previousItem, cached.itemId == previousItemId, !cached.deleted, cached != self { return cached }
            if let itemId = previousItemId, let item = store?.item(for: itemId), !item.deleted, item != self {
                _previousItem = item
                return item
            }
            return nil
        }
        set(newValue) {
            if newValue == self { os_log("Can't link to self", type: .error); return }
            if newValue?.deleted == true { os_log("Can't link to a deleted item", type: .error); return }
            mutex.sync {
                let oldValue = self.previousItem

                // no change? do nothing
                if newValue == oldValue { return }

                // store the new value
                self._previousItem = newValue
                self.previousItemId = newValue?.itemId

                // disconnect the old relationship
                if oldValue?.nextItemId == self.itemId {
                    oldValue?.nextItemId = nil
                }

                // complete the other side of the new relationship
                if newValue?.nextItemId != self.itemId {
                    newValue?.nextItemId = self.itemId
                }
            }
        }
    }

    private weak var _nextItem: TimelineItem?
    public var nextItem: TimelineItem? {
        get {
            if let cached = _nextItem, cached.itemId == nextItemId, !cached.deleted, cached != self { return cached }
            if let itemId = nextItemId, let item = store?.item(for: itemId), !item.deleted, item != self {
                _nextItem = item
                return item
            }
            return nil
        }
        set(newValue) {
            if newValue == self { os_log("Can't link to self", type: .error); return }
            if newValue?.deleted == true { os_log("Can't link to a deleted item", type: .error); return }
            mutex.sync {
                let oldValue = self.nextItem

                // no change? do nothing
                if newValue == oldValue { return }

                // store the new value
                self._nextItem = newValue
                self.nextItemId = newValue?.itemId

                // disconnect the old relationship
                if oldValue?.previousItemId == self.itemId {
                    oldValue?.previousItemId = nil
                }

                // complete the other side of the new relationship
                if newValue?.previousItemId != self.itemId {
                    newValue?.previousItemId = self.itemId
                }
            }
        }
    }

    public var isCurrentItem: Bool { return store?.recorder?.currentItem == self }

    // MARK: - Dates, times, durations

    private(set) public var _dateRange: DateInterval?
    public var dateRange: DateInterval? {
        if let cached = _dateRange { return cached }
        guard let start = samples.first?.date else { return nil }
        if let nextItemStart = nextItem?.startDate, nextItemStart > start {
            _dateRange = DateInterval(start: start, end: nextItemStart)
        } else if let end = samples.last?.date {
            _dateRange = DateInterval(start: start, end: end)
        }
        return _dateRange
    }

    public var startDate: Date? { return dateRange?.start }
    public var endDate: Date? { return dateRange?.end }
    public var duration: TimeInterval { return dateRange?.duration ?? 0 }

    public var startTimeZone: TimeZone? {
        return samples.first?.localTimeZone
    }

    public var endTimeZone: TimeZone? {
        return samples.last?.localTimeZone
    }

    // MARK: - Item validity

    public var isInvalid: Bool { return !isValid }

    open var isValid: Bool { fatalError("Shouldn't be here.") }

    open var isWorthKeeping: Bool { fatalError("Shouldn't be here.") }
    
    public var keepnessScore: Int {
        if isWorthKeeping { return 2 }
        if isValid { return 1 }
        return 0
    }

    public var keepnessString: String {
        if isWorthKeeping { return "keeper" }
        if isValid { return "valid" }
        return "invalid"
    }

    public var isDataGap: Bool {
        if self is Visit { return false }
        if samples.isEmpty { return false }
        for sample in samples {
            if sample.recordingState != .off { return false }
        }
        return true
    }

    private var _isNolo: Bool?
    public var isNolo: Bool {
        if isDataGap { return false }
        if let nolo = _isNolo { return nolo }
        _isNolo = !samples.haveAnyUsableLocations
        return _isNolo!
    }

    // ~50% of samples
    public var radius0sd: Double {
        return radius.with0sd.clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
    }

    // ~84% of samples
    public var radius1sd: Double {
        return radius.with1sd.clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
    }

    // ~98% of samples
    public var radius2sd: Double {
        return radius.with2sd.clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
    }

    // ~100% of samples
    public var radius3sd: Double {
        return radius.with3sd.clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
    }

    /// The timeline item's samples grouped up into ItemSegments by sequentially matching activityType and recordingState.
    private var _segments: [ItemSegment]? = nil
    public var segments: [ItemSegment] {
        if let segments = _segments { return segments }

        var segments: [ItemSegment] = []
        var current: ItemSegment?
        for sample in samples {

            // first segment?
            if current == nil {
                current = ItemSegment(samples: [sample], timelineItem: self)
                segments.append(current!)
                continue
            }

            // can add it to the current segment?
            if current?.canAdd(sample) == true {
                current?.add(sample)
                continue
            }

            /** NEED A NEW SEGMENT **/

            // use the sample to finalise the current segment before starting the next
            current?.endSample = sample

            // create the next segment
            current = ItemSegment(samples: [sample], timelineItem: self)
            segments.append(current!)
        }

        _segments = segments
        return segments
    }

    /// The timeline item's samples grouped up into ItemSegments by sequentially matching activityType.
    private var _segmentsByActivityType: [ItemSegment]? = nil
    public var segmentsByActivityType: [ItemSegment] {
        if let segments = _segmentsByActivityType { return segments }

        var segments: [ItemSegment] = []
        var current: ItemSegment?
        for sample in samples {

            // first segment?
            if current == nil {
                current = ItemSegment(samples: [sample], timelineItem: self)
                segments.append(current!)
                continue
            }

            // can add it to the current segment?
            if current?.canAdd(sample, ignoreRecordingState: true) == true {
                current?.add(sample)
                continue
            }

            /** NEED A NEW SEGMENT **/

            // use the sample to finalise the current segment before starting the next
            current?.endSample = sample

            // create the next segment
            current = ItemSegment(samples: [sample], timelineItem: self)
            segments.append(current!)
        }

        _segmentsByActivityType = segments
        return segments
    }

    // MARK: - Activity Types

    open var activityType: ActivityTypeName? {
        if self is Visit { return .stationary }

        // if cached classifier results available, use classified moving type
        if _classifierResults != nil, let activityType = movingActivityType { return activityType }

        // if cached classifier result not available, use mode moving type
        if let activityType = modeMovingActivityType { return activityType }

        // if there's no mode moving type, fall back to mode type (most likely stationary)
        if let activityType = modeActivityType { return activityType }

        return nil
    }

    public private(set) var _classifierResults: ClassifierResults? = nil

    /// The `ActivityTypeClassifier` results for the timeline item.
    public var classifierResults: ClassifierResults? {
        if let cached = _classifierResults { return cached }

        guard let results = classifier?.classify(self, timeout: 30) else { return nil }

        // don't cache if it's incomplete
        if results.moreComing { return results }

        _classifierResults = results
        return results
    }

    public private(set) var _movingActivityType: ActivityTypeName? = nil

    public var movingActivityType: ActivityTypeName? {
        if let cached = _movingActivityType { return cached }
        guard let results = classifierResults else { return nil }
        guard let first = results.first(where: { $0.name != .stationary }) else { return nil }
        guard first.score > 0 else { return nil }
        if !results.moreComing {
            _movingActivityType = first.name
        }
        return first.name
    }

    public private(set) var _modeActivityType: ActivityTypeName? = nil

    /// The most common activity type for the timeline item's samples.
    public var modeActivityType: ActivityTypeName? {
        if let cached = _modeActivityType { return cached }

        let sampleTypes = samples.compactMap { $0.activityType }
        if sampleTypes.isEmpty { return nil }

        let counted = NSCountedSet(array: sampleTypes)
        let modeType = counted.max { counted.count(for: $0) < counted.count(for: $1) }

        _modeActivityType = modeType as? ActivityTypeName
        return _modeActivityType
    }

    public private(set) var _modeMovingActivityType: ActivityTypeName? = nil

    /// The most common moving activity type for the timeline item's samples.
    public var modeMovingActivityType: ActivityTypeName? {
        if let modeType = _modeMovingActivityType { return modeType }

        let sampleTypes = samples.compactMap { $0.activityType != .stationary ? $0.activityType : nil }
        if sampleTypes.isEmpty { return nil }

        let counted = NSCountedSet(array: sampleTypes)
        let modeType = counted.max { counted.count(for: $0) < counted.count(for: $1) }

        _modeMovingActivityType = modeType as? ActivityTypeName
        return _modeMovingActivityType
    }

    // MARK: - Comparisons and Helpers

    /**
     The time interval between this item and the given item.

     - Note: A negative value indicates overlapping items, and thus the duration of their overlap.
     */
    public func timeInterval(from otherItem: TimelineItem) -> TimeInterval? {
        guard let myRange = self.dateRange else { return nil }
        guard let theirRange = otherItem.dateRange else { return nil }

        // items overlap?
        if let intersection = myRange.intersection(with: theirRange) { return -intersection.duration }

        if myRange.end <= theirRange.start { return theirRange.start.timeIntervalSince(myRange.end) }
        if myRange.start >= theirRange.end { return myRange.start.timeIntervalSince(theirRange.end) }

        return nil
    }

    internal func edgeSample(with otherItem: TimelineItem) -> PersistentSample? {
        if otherItem == previousItem {
            return samples.first
        }
        if otherItem == nextItem {
            return samples.last
        }
        return nil
    }

    internal func secondToEdgeSample(with otherItem: TimelineItem) -> PersistentSample? {
        if otherItem == previousItem { return samples.second }
        if otherItem == nextItem { return samples.secondToLast }
        return nil
    }

    open func withinMergeableDistance(from otherItem: TimelineItem) -> Bool {
        if self.isNolo || otherItem.isNolo { return true }
        if let gap = distance(from: otherItem), gap <= maximumMergeableDistance(from: otherItem) { return true }

        // if the items overlap in time, any physical distance is acceptable
        guard let timeGap = self.timeInterval(from: otherItem), timeGap < 0 else { return true }

        return false
    }

    public func contains(_ location: CLLocation, sd: Double) -> Bool {
        fatalError("Shouldn't be here.")
    }

    public func distance(from: TimelineItem) -> CLLocationDistance? {
        fatalError("Shouldn't be here.")
    }

    public func maximumMergeableDistance(from: TimelineItem) -> CLLocationDistance {
        fatalError("Shouldn't be here.")
    }

    @discardableResult
    internal func sanitiseEdges(excluding: Set<LocomotionSample> = []) -> Set<LocomotionSample> {
        var allMoved: Set<LocomotionSample> = []
        let maximumEdgeSteals = 30

        while allMoved.count < maximumEdgeSteals {
            var movedThisLoop: Set<LocomotionSample> = []

            if let previousPath = self.previousItem as? Path {
                if let moved = self.cleanseEdge(with: previousPath, excluding: excluding.union(allMoved)) {
                    movedThisLoop.insert(moved)
                }
            }
            if let nextPath = self.nextItem as? Path {
                if let moved = self.cleanseEdge(with: nextPath, excluding: excluding.union(allMoved)) {
                    movedThisLoop.insert(moved)
                }
            }

            // no changes, so we're done
            if movedThisLoop.isEmpty { break }

            // break from an infinite loop
            guard movedThisLoop.intersection(allMoved).isEmpty else { break }

            // keep track of changes
            allMoved.formUnion(movedThisLoop)
        }

        return allMoved
    }

    internal func cleanseEdge(with path: Path, excluding: Set<LocomotionSample>) -> LocomotionSample? {
        fatalError("Shouldn't be here.")
    }

    open func scoreForConsuming(item: TimelineItem) -> ConsumptionScore {
        return MergeScores.consumptionScoreFor(self, toConsume: item)
    }

    /**
     For subclasses to perform additional actions when merging items, for example copying and preserving
     subclass properties.
     */
    open func willConsume(item: TimelineItem) {}

    // MARK: - Modifying the timeline item

    public func add(_ sample: PersistentSample) { add([sample]) }

    public func remove(_ sample: PersistentSample) { remove([sample]) }
    
    open func add(_ samples: [PersistentSample]) {
        var madeChanges = false
        mutex.sync {
            _samples = Set(self.samples + samples).sorted { $0.date < $1.date }
            for sample in samples where sample.timelineItem != self {
                sample.timelineItem = self
                madeChanges = true
            }
        }
        if madeChanges { samplesChanged() }
    }

    open func remove(_ samples: [PersistentSample]) {
        var madeChanges = false
        mutex.sync {
            _samples?.removeObjects(samples)
            for sample in samples where sample.timelineItemId == self.itemId {
                sample.timelineItemId = nil
                madeChanges = true
            }
        }
        if madeChanges { samplesChanged() }
    }

    open func sampleTypesChanged() {
        _segments = nil
        _segmentsByActivityType = nil
        _classifierResults = nil
        _movingActivityType = nil
        _modeMovingActivityType = nil
        _modeActivityType = nil
    }

    open func samplesChanged() {
        sampleTypesChanged()
        
        _isNolo = nil
        _center = nil
        _radius = nil
        _altitude = nil

        let oldDateRange = dateRange
        _dateRange = nil

        if oldDateRange != dateRange { pedometerDataIsStale = true }

        hasChanges = true
        save()

        onMain {
            NotificationCenter.default.post(Notification(name: .updatedTimelineItem, object: self, userInfo: nil))
        }
    }

    public private(set) var _center: CLLocation?
    public var center: CLLocation? {
        if let cached = _center { return cached }
        _center = samples.weightedCenter
        return _center
    }

    public private(set) var _radius: Radius?
    public var radius: Radius {
        if let cached = _radius { return cached }
        if let center = center { _radius = samples.radius(from: center) }
        else { _radius = Radius.zero }
        return _radius!
    }

    public private(set) var _altitude: CLLocationDistance?
    public var altitude: CLLocationDistance? {
        if let cached = _altitude { return cached }
        _altitude = samples.weightedMeanAltitude
        return _altitude
    }

    public func updatePedometerData() {
        let loco = LocomotionManager.highlander

        if updatingPedometerData { return }
        guard loco.recordPedometerEvents && loco.haveCoreMotionPermission else { return }
        guard let dateRange = dateRange, dateRange.duration > 0 else { return }

        // iOS doesn't keep pedometer data older than one week
        guard dateRange.start.age < 60 * 60 * 24 * 7 else { return }

        pedometerDataIsStale = false
        updatingPedometerData = true

        loco.pedometer.queryPedometerData(from: dateRange.start, to: dateRange.end) { data, error in
            self.updatingPedometerData = false

            guard let data = data else { return }

            var madeChanges = false
            if self._stepCount != data.numberOfSteps.intValue {
                self._stepCount = data.numberOfSteps.intValue
                madeChanges = true
            }
            if let floorsAscended = data.floorsAscended?.intValue, self._floorsAscended != floorsAscended {
                self._floorsAscended = floorsAscended
                madeChanges = true
            }
            if let floorsDescended = data.floorsDescended?.intValue, self._floorsDescended != floorsDescended {
                self._floorsDescended = floorsDescended
                madeChanges = true
            }

            if madeChanges {
                onMain {
                    NotificationCenter.default.post(Notification(name: .updatedTimelineItem, object: self, userInfo: nil))
                }
            }
        }
    }

    // MARK: - Item metadata copying

    open func copyMetadata(from otherItem: TimelineItem) {}

    // MARK: - PersistableRecord

    public static let databaseTableName = "TimelineItem"

    open func encode(to container: inout PersistenceContainer) {
        container["itemId"] = itemId.uuidString
        container["lastSaved"] = transactionDate ?? lastSaved ?? Date()
        container["deleted"] = deleted
        container["source"] = source
        let range = _dateRange ?? dateRange
        container["startDate"] = range?.start
        container["endDate"] = range?.end
        if deleted {
            container["previousItemId"] = nil
            container["nextItemId"] = nil
        } else {
            container["previousItemId"] = previousItemId?.uuidString
            container["nextItemId"] = nextItemId?.uuidString
        }
        container["radiusMean"] = _radius?.mean
        container["radiusSD"] = _radius?.sd
        container["altitude"] = _altitude
        container["stepCount"] = stepCount
        container["floorsAscended"] = floorsAscended
        container["floorsDescended"] = floorsDescended
        container["latitude"] = _center?.coordinate.latitude
        container["longitude"] = _center?.coordinate.longitude
    }

    // MARK: - Hashable, Comparable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(itemId)
    }

    public static func ==(lhs: TimelineItem, rhs: TimelineItem) -> Bool { return lhs.itemId == rhs.itemId }

    public static func <(lhs: TimelineItem, rhs: TimelineItem) -> Bool {
        if let leftEnd = lhs.endDate, let rightEnd = rhs.endDate, leftEnd < rightEnd { return true }
        return false
    }

    // MARK: - Required initialisers

    public required init(in store: TimelineStore) {
        self.itemId = UUID()
        self.store = store
        store.add(self)
    }

    public required init(from dict: [String: Any?], in store: TimelineStore) {
        self.store = store
        if let uuidString = dict["itemId"] as? String {
            self.itemId = UUID(uuidString: uuidString)!
        } else {
            self.itemId = UUID()
        }
        self.lastSaved = dict["lastSaved"] as? Date
        self.deleted = dict["deleted"] as? Bool ?? false
        if let uuidString = dict["previousItemId"] as? String { self.previousItemId = UUID(uuidString: uuidString)! }
        if let uuidString = dict["nextItemId"] as? String { self.nextItemId = UUID(uuidString: uuidString)! }
        if let mean = dict["radiusMean"] as? Double, let sd = dict["radiusSD"] as? Double {
            self._radius = Radius(mean: mean, sd: sd)
        }
        if let start = dict["startDate"] as? Date, let end = dict["endDate"] as? Date, start <= end {
            _dateRange = DateInterval(start: start, end: end)
        }
        self._altitude = dict["altitude"] as? Double
        if let steps = dict["stepCount"] as? Int64 {
            self._stepCount = Int(steps)
        }
        if let floors = dict["floorsAscended"] as? Int64 {
            self._floorsAscended = Int(floors)
        }
        if let floors = dict["floorsDescended"] as? Int64 {
            self._floorsDescended = Int(floors)
        }
        if let center = dict["center"] as? CLLocation {
            self._center = center
        } else if let latitude = dict["latitude"] as? Double, let longitude = dict["longitude"] as? Double {
            self._center = CLLocation(latitude: latitude, longitude: longitude)
        }
        if let rawValue = dict["activityType"] as? String, let activityType = ActivityTypeName(rawValue: rawValue) {
            if self is Path {
                _modeMovingActivityType = activityType
            } else {
                _modeActivityType = activityType
            }
        }
        if let source = dict["source"] as? String, !source.isEmpty {
            self.source = source
        }
        store.add(self)
    }

    // MARK: - Codable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.itemId = (try? container.decode(UUID.self, forKey: .itemId)) ?? UUID()
        self.deleted = (try? container.decode(Bool.self, forKey: .deleted)) ?? false
        self.previousItemId = try? container.decode(UUID.self, forKey: .previousItemId)
        self.nextItemId = try? container.decode(UUID.self, forKey: .nextItemId)

        let start = try? container.decode(Date.self, forKey: .startDate)
        let end = try? container.decode(Date.self, forKey: .endDate)
        if let start = start, let end = end, start <= end { self._dateRange = DateInterval(start: start, end: end) }

        self._radius = try? container.decode(Radius.self, forKey: .radius)
        self._altitude = try? container.decode(CLLocationDistance.self, forKey: .altitude)
        self._stepCount = try? container.decode(Int.self, forKey: .stepCount)
        self._floorsAscended = try? container.decode(Int.self, forKey: .floorsAscended)
        self._floorsDescended = try? container.decode(Int.self, forKey: .floorsDescended)

        if let coordinate = try? container.decode(CLLocationCoordinate2D.self, forKey: .center) {
            self._center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } else if let codableLocation = try? container.decode(CodableLocation.self, forKey: .center) {
            self._center = CLLocation(from: codableLocation)
        }
    }

    open func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(self is Visit, forKey: .isVisit)
        if deleted { try container.encode(deleted, forKey: .deleted) }
        if previousItemId != nil { try container.encode(previousItemId, forKey: .previousItemId) }
        if nextItemId != nil { try container.encode(nextItemId, forKey: .nextItemId) }
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(center?.coordinate, forKey: .center)
        try container.encode(radius, forKey: .radius)
        if altitude != nil { try container.encode(altitude, forKey: .altitude) }
        if stepCount != nil { try container.encode(stepCount, forKey: .stepCount) }
        if self is Path {
            if modeMovingActivityType != nil { try container.encode(modeMovingActivityType, forKey: .activityType) }
        }
        if floorsAscended != nil { try container.encode(floorsAscended, forKey: .floorsAscended) }
        if floorsDescended != nil { try container.encode(floorsDescended, forKey: .floorsDescended) }
        try container.encode(samples, forKey: .samples)
    }

    internal enum CodingKeys: String, CodingKey {
        case itemId
        case deleted
        case isVisit
        case previousItemId
        case nextItemId
        case startDate
        case endDate
        case lastModified
        case center
        case radius
        case altitude
        case stepCount
        case activityType
        case floorsAscended
        case floorsDescended
        case samples
    }
}

internal enum DecodeError: Error {
    case runtimeError(String)
}
