//
//  BaseTimelineItem.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import ArcKitCore
import CoreLocation

/// The abstract base class for timeline items.
open class TimelineItem: TimelineObject, Hashable, Comparable, Codable {

    // MARK: TimelineObject

    public var objectId: UUID { return itemId }
    public weak var store: TimelineStore?
    internal(set) public var inTheStore = false
    open var currentInstance: TimelineItem? { return inTheStore ? self : store?.item(for: itemId) }

    public var classifier: TimelineClassifier? { return store?.manager?.classifier }

    public var mutex = PThreadMutex(type: .recursive)

    public let itemId: UUID

    private(set) public var lastModified: Date

    open var isMergeLocked: Bool { return false }

    internal(set) public var deleted = false {
        willSet(willDelete) {
            if willDelete {
                guard self.samples.isEmpty else {
                    fatalError("Can't delete item that has samples")
                }
                self.previousItem = nil
                self.nextItem = nil
            }
        }
    }

    private var updatingPedometerData = false
    private var pedometerDataIsStale = false

    private var _stepCount: Int?
    open var stepCount: Int? {
        if _stepCount == nil || pedometerDataIsStale { updatePedometerData() }
        return _stepCount
    }

    private var _floorsAscended: Int?
    public var floorsAscended: Int? {
        if _floorsAscended == nil || pedometerDataIsStale { updatePedometerData() }
        return _floorsAscended
    }

    private var _floorsDescended: Int?
    public var floorsDescended: Int? {
        if _floorsDescended == nil || pedometerDataIsStale { updatePedometerData() }
        return _floorsDescended
    }

    private var _samples: [LocomotionSample] = []
    open var samples: [LocomotionSample] { return mutex.sync { _samples } }

    private(set) public var _dateRange: DateInterval?
    public var dateRange: DateInterval? {
        if let cached = _dateRange { return cached }
        if let start = samples.first?.date, let end = samples.last?.date {
            _dateRange = DateInterval(start: start, end: end)
        }
        return _dateRange
    }

    public var startDate: Date? { return dateRange?.start }
    public var endDate: Date? { return dateRange?.end }
    public var duration: TimeInterval { return dateRange?.duration ?? 0 }

    public var previousItemId: UUID?
    public var nextItemId: UUID?

    private weak var _previousItem: TimelineItem?
    public var previousItem: TimelineItem? {
        get {
            if let cached = self._previousItem?.currentInstance, cached.itemId == self.previousItemId { return cached }
            if let itemId = self.previousItemId, let item = store?.item(for: itemId) { self._previousItem = item }
            return self._previousItem
        }
        set(newValue) {
            if newValue == self { fatalError("CAN'T LINK TO SELF") }
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
            if let cached = self._nextItem?.currentInstance, cached.itemId == self.nextItemId { return cached }
            if let itemId = self.nextItemId, let item = store?.item(for: itemId) { self._nextItem = item }
            return self._nextItem
        }
        set(newValue) {
            if newValue == self { fatalError("CAN'T LINK TO SELF") }
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

    public var isCurrentItem: Bool { return store?.manager?.currentItem == self }

    // MARK: Timeline item validity

    public var isInvalid: Bool { return !isValid }

    open var isValid: Bool { fatalError("Shouldn't be here.") }

    open var isWorthKeeping: Bool { fatalError("Shouldn't be here.") }
    
    public var keepnessScore: Int {
        if isWorthKeeping { return 2 }
        if isValid { return 1 }
        return 0
    }

    public var isDataGap: Bool {
        if let first = samples.first, first.recordingState == .off { return true }
        return false
    }

    private var _isNolo: Bool?
    public var isNolo: Bool {
        if isDataGap { return false }
        if let nolo = _isNolo { return nolo }
        _isNolo = samples.haveAnyUsableLocations
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

    // MARK: Activity Types

    private var _classifierResults: ClassifierResults? = nil

    /// The `ActivityTypeClassifier` results for the timeline item.
    public var classifierResults: ClassifierResults? {
        if let cached = _classifierResults { return cached }

        guard let results = classifier?.classify(self, filtered: true) else { return nil }

        // don't cache if it's incomplete
        if results.moreComing { return results }

        _classifierResults = results
        return results
    }

    private var _unfilteredClassifierResults: ClassifierResults? = nil

    /// The unfiltered `ActivityTypeClassifier` results for the timeline item.
    public var unfilteredClassifierResults: ClassifierResults? {
        if let cached = _unfilteredClassifierResults { return cached }

        guard let results = classifier?.classify(self, filtered: false) else { return nil }

        // don't cache if it's incomplete
        if results.moreComing { return results }

        _unfilteredClassifierResults = results
        return results
    }

    private(set) public var _activityType: ActivityTypeName?
    
    /// The highest scoring activity type for the timeline's samples.
    public var activityType: ActivityTypeName? {
        if let cached = _activityType { return cached }
        _activityType = classifierResults?.first?.name
        return _activityType
    }

    public var movingActivityType: ActivityTypeName? {
        return classifierResults?.first(where: { $0.name != .stationary })?.name
    }

    private var _modeActivityType: ActivityTypeName? = nil

    /// The most common activity type for the timeline item's samples.
    public var modeActivityType: ActivityTypeName? {
        if let cached = _modeActivityType { return cached }

        let sampleTypes = samples.flatMap { $0.activityType }
        if sampleTypes.isEmpty { return nil }

        let counted = NSCountedSet(array: sampleTypes)
        let modeType = counted.max { counted.count(for: $0) < counted.count(for: $1) }

        _modeActivityType = modeType as? ActivityTypeName
        return _modeActivityType
    }

    private var _modeMovingActivityType: ActivityTypeName? = nil

    /// The most common moving activity type for the timeline item's samples.
    public var modeMovingActivityType: ActivityTypeName? {
        if let modeType = _modeMovingActivityType {
            return modeType
        }
        let sampleTypes = samples.flatMap { $0.activityType != .stationary ? $0.activityType : nil }

        if sampleTypes.isEmpty {
            return nil
        }

        let counted = NSCountedSet(array: sampleTypes)
        let modeType = counted.max { counted.count(for: $0) < counted.count(for: $1) }

        _modeMovingActivityType = modeType as? ActivityTypeName
        return _modeMovingActivityType
    }

    // MARK: Comparisons and Helpers

    /**
     The time interval between this item and the given item.

     - Note: A negative value indicates overlapping items, and thus the duration of their overlap.
     */
    public func timeInterval(from otherItem: TimelineItem) -> TimeInterval? {
        guard let myRange = self.dateRange, let theirRange = otherItem.dateRange else {
            return nil
        }

        if let intersection = myRange.intersection(with: theirRange) {
            return -intersection.duration
        }
        if myRange.end <= theirRange.start {
            return theirRange.start.timeIntervalSince(myRange.end)
        }
        if myRange.start >= theirRange.end {
            return myRange.start.timeIntervalSince(theirRange.end)
        }

        return nil
    }

    internal func edgeSample(with otherItem: TimelineItem) -> LocomotionSample? {
        if otherItem == previousItem {
            return samples.first
        }
        if otherItem == nextItem {
            return samples.last
        }
        return nil
    }

    internal func secondToEdgeSample(with otherItem: TimelineItem) -> LocomotionSample? {
        if otherItem == previousItem { return samples.second }
        if otherItem == nextItem { return samples.secondToLast }
        return nil
    }

    open func withinMergeableDistance(from otherItem: TimelineItem) -> Bool {
        if self.isNolo || otherItem.isNolo {
            return true
        }
        if let gap = distance(from: otherItem), gap <= maximumMergeableDistance(from: otherItem) {
            return true
        }
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

    public func sanitiseEdges() {
        edit { item in
            var lastPreviousChanged: LocomotionSample?
            var lastNextChanged: LocomotionSample?

            while true {
                var previousChanged: LocomotionSample?
                var nextChanged: LocomotionSample?

                if let previousPath = item.previousItem as? Path { previousChanged = item.cleanseEdge(with: previousPath) }
                if let nextPath = item.nextItem as? Path { nextChanged = item.cleanseEdge(with: nextPath) }

                // no changes, so we're done
                if previousChanged == nil && nextChanged == nil { break }

                // break from an infinite loop
                if previousChanged == lastPreviousChanged && nextChanged == lastNextChanged { break }

                lastPreviousChanged = previousChanged
                lastNextChanged = nextChanged
            }
        }
    }

    public func cleanseEdge(with path: Path) -> LocomotionSample? {
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

    // MARK: Modifying the timeline item

    open func edit(changes: (TimelineItem) -> Void) {
        guard let instance = self.currentInstance else { return }
        store?.retain(instance)
        mutex.sync { changes(instance) }
        store?.release(instance)
    }

    public func add(_ sample: LocomotionSample) { add([sample]) }

    public func remove(_ sample: LocomotionSample) { remove([sample]) }
    
    open func add(_ samples: [LocomotionSample]) {
        mutex.sync {
            if deleted { fatalError("Can't add samples to a deleted item") }
            for sample in samples where sample.timelineItem != self {
                sample.timelineItem?.remove(sample)
                sample.timelineItem = self
            }
            _samples = Set(_samples + samples).sorted { $0.date < $1.date }
        }
        samplesChanged()
    }

    open func remove(_ samples: [LocomotionSample]) {
        mutex.sync {
            for sample in samples where sample.timelineItem == self { sample.timelineItem = nil }
            _samples.removeObjects(samples)
        }
        samplesChanged()
    }

    open func samplesChanged() {
        _isNolo = nil
        _center = nil
        _radius = nil
        _altitude = nil
        _segments = nil
        _classifierResults = nil
        _unfilteredClassifierResults = nil
        _modeMovingActivityType = nil
        _modeActivityType = nil
        _activityType = nil

        let oldDateRange = dateRange
        _dateRange = nil

        if oldDateRange != dateRange { pedometerDataIsStale = true }

        lastModified = Date()
        onMain {
            NotificationCenter.default.post(Notification(name: .updatedTimelineItem, object: self, userInfo: nil))
        }
    }

    private(set) public var _center: CLLocation?
    public var center: CLLocation? {
        if let cached = _center { return cached }
        _center = samples.weightedCenter
        return _center
    }

    private(set) public var _radius: Radius?
    public var radius: Radius {
        if let cached = _radius { return cached }
        if let center = center { _radius = samples.radius(from: center) }
        else { _radius = Radius.zero }
        return _radius!
    }

    private(set) public var _altitude: CLLocationDistance?
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

            self._stepCount = data.numberOfSteps.intValue
            self._floorsAscended = data.floorsAscended?.intValue
            self._floorsDescended = data.floorsDescended?.intValue

            onMain {
                NotificationCenter.default.post(Notification(name: .updatedTimelineItem, object: self, userInfo: nil))
            }
        }
    }

    // MARK: Hashable, Comparable

    public var hashValue: Int { return itemId.hashValue }

    public static func ==(lhs: TimelineItem, rhs: TimelineItem) -> Bool { return lhs.itemId == rhs.itemId }

    public static func <(lhs: TimelineItem, rhs: TimelineItem) -> Bool {
        if let leftEnd = lhs.endDate, let rightEnd = rhs.endDate, leftEnd < rightEnd { return true }
        return false
    }

    // MARK: Required initialisers

    public required init(in store: TimelineStore) {
        self.itemId = UUID()
        self.lastModified = Date()
        store.add(self)
    }

    public required init(from dict: [String: Any?], in store: TimelineStore) {
        if let uuidString = dict["itemId"] as? String {
            self.itemId = UUID(uuidString: uuidString)!
        } else {
            self.itemId = UUID()
        }
        self.deleted = dict["deleted"] as? Bool ?? false
        if let uuidString = dict["previousItemId"] as? String { self.previousItemId = UUID(uuidString: uuidString)! }
        if let uuidString = dict["nextItemId"] as? String { self.nextItemId = UUID(uuidString: uuidString)! }
        self.lastModified = dict["lastModified"] as? Date ?? Date()
        if let mean = dict["radiusMean"] as? Double, let sd = dict["radiusSD"] as? Double {
            self._radius = Radius(mean: mean, sd: sd)
        }
        if let start = dict["startDate"] as? Date, let end = dict["endDate"] as? Date {
            _dateRange = DateInterval(start: start, end: end)
        }
        self._altitude = dict["altitude"] as? Double
        self._stepCount = dict["stepCount"] as? Int
        self._floorsAscended = dict["floorsAscended"] as? Int
        self._floorsDescended = dict["floorsDescended"] as? Int
        if let typeName = dict["activityType"] as? String { self._activityType = ActivityTypeName(rawValue: typeName) }
        if let center = dict["center"] as? CLLocation {
            self._center = center
        } else if let latitude = dict["latitude"] as? Double, let longitude = dict["longitude"] as? Double {
            self._center = CLLocation(latitude: latitude, longitude: longitude)
        }
        store.add(self)
    }

    // MARK: Codable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.itemId = (try? container.decode(UUID.self, forKey: .itemId)) ?? UUID()
        self.deleted = (try? container.decode(Bool.self, forKey: .deleted)) ?? false
        self.previousItemId = try? container.decode(UUID.self, forKey: .previousItemId)
        self.nextItemId = try? container.decode(UUID.self, forKey: .nextItemId)

        let start = try? container.decode(Date.self, forKey: .startDate)
        let end = try? container.decode(Date.self, forKey: .endDate)
        if let start = start, let end = end, start <= end { self._dateRange = DateInterval(start: start, end: end) }

        self.lastModified = (try? container.decode(Date.self, forKey: .lastModified)) ?? Date()
        self._radius = try? container.decode(Radius.self, forKey: .radius)
        self._altitude = try? container.decode(CLLocationDistance.self, forKey: .altitude)
        self._stepCount = try? container.decode(Int.self, forKey: .stepCount)
        self._floorsAscended = try? container.decode(Int.self, forKey: .floorsAscended)
        self._floorsDescended = try? container.decode(Int.self, forKey: .floorsDescended)
        self._activityType = try? container.decode(ActivityTypeName.self, forKey: .activityType)

        if let codableLocation = try? container.decode(CodableLocation.self, forKey: .center) {
            self._center = CLLocation(from: codableLocation)
        }
    }

    open func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(deleted, forKey: .deleted)
        try container.encode(previousItemId, forKey: .previousItemId)
        try container.encode(nextItemId, forKey: .nextItemId)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(center?.codable, forKey: .center)
        try container.encode(radius, forKey: .radius)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(stepCount, forKey: .stepCount)
        try container.encode(activityType, forKey: .activityType)
        try container.encode(floorsAscended, forKey: .floorsAscended)
        try container.encode(floorsDescended, forKey: .floorsDescended)
    }

    private enum CodingKeys: String, CodingKey {
        case itemId
        case deleted
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
    }
}
