//
//  PersistentPath.swift
//  LocoKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB

open class PersistentPath: Path, PersistentObject {

    public override var deleted: Bool {
        didSet {
            if oldValue != deleted {
                hasChanges = true
                save()
            }
        }
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
            } else if let store = persistentStore {
                _samples = store.samples(where: "timelineItemId = ? ORDER BY date", arguments: [itemId.uuidString])
            } else {
                _samples = []
            }
            return _samples!
        }
    }

    // MARK: Data modification

    open override func edit(changes: (PersistentPath) -> Void) {
        mutex.sync { changes(self) }
        hasChanges = true
        save(immediate: true)
    }

    open override func add(_ samples: [LocomotionSample]) {
        mutex.sync {
            _samples = Set(self.samples + samples).sorted { $0.date < $1.date }
            for sample in samples where sample.timelineItem != self {
                sample.timelineItem = nil
                sample.timelineItemId = self.itemId
            }
        }
        samplesChanged()
    }

    open override func remove(_ samples: [LocomotionSample]) {
        mutex.sync {
            _samples?.removeObjects(samples)
            for sample in samples where sample.timelineItemId == self.itemId { sample.timelineItemId = nil }
        }
        samplesChanged()
    }

    open override func samplesChanged() {
        super.samplesChanged()
        hasChanges = true
        save()
    }

    // MARK: Persistable

    public static let databaseTableName = "TimelineItem"

    open func encode(to container: inout PersistenceContainer) {
        container["itemId"] = itemId.uuidString
        container["lastSaved"] = transactionDate ?? lastSaved
        container["deleted"] = deleted
        container["isVisit"] = false
        container["startDate"] = _dateRange?.start
        container["endDate"] = _dateRange?.end
        container["previousItemId"] = previousItemId?.uuidString
        container["nextItemId"] = nextItemId?.uuidString
        container["radiusMean"] = _radius?.mean
        container["radiusSD"] = _radius?.sd
        container["altitude"] = _altitude
        container["stepCount"] = stepCount
        container["floorsAscended"] = floorsAscended
        container["floorsDescended"] = floorsDescended
        container["activityType"] = modeMovingActivityType?.rawValue
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lastSaved = try? container.decode(Date.self, forKey: .lastSaved)
        try super.init(from: decoder)
    }

    open override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lastSaved, forKey: .lastSaved)
        try super.encode(to: encoder)
    }

    enum CodingKeys: String, CodingKey {
        case lastSaved
    }
}

