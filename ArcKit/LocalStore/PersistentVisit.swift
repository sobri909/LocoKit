//
//  PersistentVisit.swift
//  ArcKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB

open class PersistentVisit: Visit, PersistentObject {

    open override var currentInstance: PersistentVisit? { return super.currentInstance as? PersistentVisit }

    public override var deleted: Bool { didSet { if oldValue != deleted { save() } } }

    // MARK: Relationships

    open override var previousItemId: UUID? { didSet { save() } }
    open override var nextItemId: UUID? { didSet { save() } }

    private var _samples: [LocomotionSample]?
    open override var samples: [LocomotionSample] {
        return mutex.sync {
            if let existing = _samples { return existing }
            if lastSaved == nil { _samples = [] } else {
                _samples = persistentStore.samples(where: "timelineItemId = ? ORDER BY date", arguments: [itemId.uuidString])
            }
            return _samples!
        }
    }

    // MARK: Data modification

    open override func edit(changes: (PersistentVisit) -> Void) {
        guard let instance = self.currentInstance else { return }
        store?.retain(instance)
        mutex.sync { changes(instance) }
        instance.save()
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
        save()
    }

    // MARK: Persistable

    public static let databaseTableName = "TimelineItem"
    
    open func encode(to container: inout PersistenceContainer) {
        container["itemId"] = itemId.uuidString
        container["lastSaved"] = transactionDate ?? lastSaved
        container["deleted"] = deleted
        container["isVisit"] = true
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
        container["activityType"] = activityType?.rawValue
        container["latitude"] = _center?.coordinate.latitude
        container["longitude"] = _center?.coordinate.longitude
    }

    // MARK: PersistentObject

    public var transactionDate: Date?
    public var lastSaved: Date?

    // MARK: Initialisers

    public required init(in store: TimelineStore) { super.init(in: store) }

    public required init(from dict: [String: Any?], in store: TimelineStore) {
        self.lastSaved = dict["lastSaved"] as? Date
        super.init(from: dict, in: store)
    }
    
    // MARK: Codable

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

