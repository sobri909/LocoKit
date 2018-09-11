//
//  PersistentPath.swift
//  LocoKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB

open class PersistentPath: Path, PersistentObject {

    open override func delete() {
        super.delete()
        hasChanges = true
        save()
    }

    // MARK: Relationships

    open override var previousItemId: UUID? {
        didSet {
            if oldValue != previousItemId {
                hasChanges = true
                save()
            }
        }
    }
    
    open override var nextItemId: UUID? {
        didSet {
            if oldValue != nextItemId {
                hasChanges = true
                save()
            }
        }
    }

    private var _samples: [LocomotionSample]?
    open override var samples: [LocomotionSample] {
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

    // MARK: Data modification

    open override func edit(changes: () -> Void) {
        mutex.sync { changes() }
        hasChanges = true
        save(immediate: true)
    }

    open override func add(_ samples: [LocomotionSample]) {
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

    open override func remove(_ samples: [LocomotionSample]) {
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

    open override func samplesChanged() {
        super.samplesChanged()
        hasChanges = true
        save()
    }

    // MARK: PersistableRecord

    public static let databaseTableName = "TimelineItem"

    open func encode(to container: inout PersistenceContainer) {
        container["itemId"] = itemId.uuidString
        container["lastSaved"] = transactionDate ?? lastSaved ?? Date()
        container["deleted"] = deleted
        container["isVisit"] = false
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
        container["distance"] = _distance
        container["stepCount"] = stepCount
        container["floorsAscended"] = floorsAscended
        container["floorsDescended"] = floorsDescended
        container["activityType"] = _modeMovingActivityType?.rawValue
        container["latitude"] = _center?.coordinate.latitude
        container["longitude"] = _center?.coordinate.longitude
    }

    // MARK: PersistentObject

    public var transactionDate: Date?
    public var lastSaved: Date?
    public var hasChanges: Bool = false

    // MARK: Initialisers

    public required init(in store: TimelineStore) { super.init(in: store) }

    public required init(from dict: [String: Any?], in store: TimelineStore) {
        self.lastSaved = dict["lastSaved"] as? Date
        super.init(from: dict, in: store)
    }

    // MARK: Decodable

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

}

