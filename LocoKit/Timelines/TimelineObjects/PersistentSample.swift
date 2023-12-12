//
//  PersistentSample.swift
//  LocoKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB
import CoreLocation

open class PersistentSample: LocomotionSample, TimelineObject {

    // MARK: - TimelineObject

    public var objectId: UUID { return sampleId }
    public weak var store: TimelineStore? { didSet { if store != nil { store?.add(self) } } }
    public var source: String = "LocoKit"

    public var rtreeId: Int64?

    private var _invalidated = false
    public var invalidated: Bool { return _invalidated }
    public func invalidate() {
        _invalidated = true
        timelineItem?.invalidate()
    }

    internal override var _classifiedType: ActivityTypeName? {
        didSet { if oldValue != _classifiedType { hasChanges = true; save() } }
    }

    public override var confirmedType: ActivityTypeName? {
        didSet {
            if oldValue != confirmedType {
                hasChanges = true
                save()
            }
        }
    }

    public override var hasUsableCoordinate: Bool {
        if confirmedType == .bogus { return false }
        return super.hasUsableCoordinate
    }

    public override var sinceVisitStart: TimeInterval {
        guard let visit = timelineItem as? Visit else { return 0 }
        guard let startDate = visit.startDate else { return 0 }
        return date.timeIntervalSince(startDate)
    }

    // MARK: - Convenience initialisers

    public convenience init(from dict: [String: Any?], in store: TimelineStore) {
        self.init(from: dict)
        self.store = store
        store.add(self)

        // backfill rtree indexes
        if lastSaved != nil, rtreeId == nil {
            Task(priority: .background) {
                if self.rtreeId == nil {
                    self.updateRTree()
                }
            }
        }
    }

    public convenience init(from sample: ActivityBrainSample, in store: TimelineStore) {
        self.init(from: sample)
        self.store = store
        store.add(self)
    }

    public convenience init(date: Date, location: CLLocation? = nil, movingState: MovingState = .uncertain,
                            recordingState: RecordingState, in store: TimelineStore) {
        self.init(date: date, location: location, movingState: movingState, recordingState: recordingState)
        self.store = store
        store.add(self)
    }

    // MARK: - Required initialisers

    public required init(from dict: [String: Any?]) {
        self.lastSaved = dict["lastSaved"] as? Date
        if let uuidString = dict["timelineItemId"] as? String { self.timelineItemId = UUID(uuidString: uuidString)! }
        if let source = dict["source"] as? String, !source.isEmpty { self.source = source }
        self.disabled = dict["disabled"] as? Bool ?? false
        self.deleted = dict["deleted"] as? Bool ?? false
        self.rtreeId = dict["rtreeId"] as? Int64

        super.init(from: dict)
    }

    public required init(from sample: ActivityBrainSample) { super.init(from: sample) }

    public required init(date: Date, location: CLLocation? = nil, movingState: MovingState = .uncertain,
                         recordingState: RecordingState) {
        super.init(date: date, location: location, movingState: movingState, recordingState: recordingState)
    }

    // MARK: - Decodable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PersistentCodingKeys.self)
        self.timelineItemId = try? container.decode(UUID.self, forKey: .timelineItemId)
        self.lastSaved = try? container.decode(Date.self, forKey: .lastSaved)
        if let deleted = try? container.decode(Bool.self, forKey: .deleted) { self.deleted = deleted }
        if let disabled = try? container.decode(Bool.self, forKey: .disabled) { self.disabled = disabled }
        try super.init(from: decoder)
    }

    open override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PersistentCodingKeys.self)
        if timelineItemId != nil { try container.encode(timelineItemId, forKey: .timelineItemId) }
        try container.encode(lastSaved, forKey: .lastSaved)
        if deleted { try container.encode(deleted, forKey: .deleted) }
        if disabled { try container.encode(disabled, forKey: .disabled) }
        try super.encode(to: encoder)
    }

    private enum PersistentCodingKeys: String, CodingKey {
        case timelineItemId
        case lastSaved
        case deleted
        case disabled
        case rtreeId
    }

    // MARK: - Relationships

    private weak var _timelineItem: TimelineItem?

    public var timelineItemId: UUID? {
        didSet {
            if oldValue != timelineItemId {
                hasChanges = true
                save()
            }
        }
    }

    /// The sample's parent `TimelineItem`.
    public var timelineItem: TimelineItem? {
        get {
            if let cached = self._timelineItem, cached.itemId == self.timelineItemId { return cached }
            if let itemId = self.timelineItemId, let item = store?.item(for: itemId) { self._timelineItem = item; return item }
            return self._timelineItem
        }
        set(newValue) {
            let oldValue = self.timelineItem

            // no change? do nothing
            if newValue == oldValue { return }

            // disconnect the old relationship
            oldValue?.remove(self)

            // store the new value
            self._timelineItem = newValue
            self.timelineItemId = newValue?.itemId

            // complete the other side of the new relationship
            newValue?.add(self)
        }
    }

    private weak var _nextSample: PersistentSample?
    public var nextSample: PersistentSample? {
        if let cached = _nextSample { return cached }
        _nextSample = store?.sample(where: "date > ? ORDER BY date", arguments: [self.date])
        return _nextSample
    }

    public private(set) var deleted = false 
    open func delete() {
        deleted = true
        hasChanges = true
        timelineItem?.remove(self)
        save()
    }

    public var disabled: Bool = false {
        didSet {
            hasChanges = true
            timelineItem?.samplesChanged()
        }
    }

    // MARK: - RTree index

    internal func updateRTree() {
        guard let coordinate = location?.coordinate, coordinate.isUsable else { return }
        guard let pool = store?.pool else { return }
        do {
            if let rtreeId = rtreeId {
                let rtree = SampleRTree(
                    id: rtreeId,
                    latMin: coordinate.latitude, latMax: coordinate.latitude,
                    lonMin: coordinate.longitude, lonMax: coordinate.longitude
                )
                try pool.write { try rtree.update($0) }
                
            } else {
                var rtree = SampleRTree(
                    latMin: coordinate.latitude, latMax: coordinate.latitude,
                    lonMin: coordinate.longitude, lonMax: coordinate.longitude
                )
                try pool.write { try rtree.insert($0) }
                rtreeId = rtree.id
                save()
            }

        } catch {
            logger.error("ERROR: \(error)")
        }
    }

    // MARK: - PersistableRecord
    
    public static let databaseTableName = "LocomotionSample"

    open func encode(to container: inout PersistenceContainer) {
        container["sampleId"] = sampleId.uuidString
        container["source"] = source
        container["date"] = date
        container["secondsFromGMT"] = secondsFromGMT
        container["deleted"] = deleted
        container["disabled"] = disabled
        container["lastSaved"] = transactionDate ?? lastSaved ?? Date()
        container["movingState"] = movingState.rawValue
        container["recordingState"] = recordingState.rawValue
        container["timelineItemId"] = timelineItemId?.uuidString
        container["stepHz"] = stepHz
        container["courseVariance"] = courseVariance
        container["xyAcceleration"] = xyAcceleration
        container["zAcceleration"] = zAcceleration
        container["confirmedType"] = confirmedType?.rawValue
        container["classifiedType"] = _classifiedType?.rawValue

        // location
        container["latitude"] = location?.coordinate.latitude
        container["longitude"] = location?.coordinate.longitude
        container["altitude"] = location?.altitude
        container["horizontalAccuracy"] = location?.horizontalAccuracy
        container["verticalAccuracy"] = location?.verticalAccuracy
        container["speed"] = location?.speed
        container["course"] = location?.course

        container["rtreeId"] = rtreeId
    }
    
    // MARK: - PersistentObject

    public var transactionDate: Date?
    public var lastSaved: Date?
    public var hasChanges: Bool = false

}

