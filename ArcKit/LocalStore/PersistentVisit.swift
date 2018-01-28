//
//  PersistentVisit.swift
//  ArcKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB

open class PersistentVisit: Visit, PersistentObject {

    public override var deleted: Bool { didSet { if oldValue != deleted { save() } } }

    // MARK: Relationships

    open override var previousItemId: UUID? { didSet { save() } }
    open override var nextItemId: UUID? { didSet { save() } }

    private var _samples: [LocomotionSample]?
    open override var samples: [LocomotionSample] {
        return mutex.sync {
            if let samples = _samples { return samples }
            if lastSaved == nil { _samples = [] } else {
                let found = persistentStore.samples(where: "timelineItemId = ?", arguments: [itemId.uuidString])
                _samples = found.sorted { $0.date < $1.date }
            }
            return _samples!
        }
    }

    // MARK: Data modification

    open override func add(_ samples: [LocomotionSample]) {
        for sample in samples where sample.timelineItem != self {
            sample.timelineItem?.remove(sample)
            sample.timelineItem = self
        }
        let deduplicated = Set(self.samples + samples)
        mutex.sync { _samples = deduplicated.sorted { $0.date < $1.date } }
        samplesChanged()
    }

    open override func remove(_ samples: [LocomotionSample]) {
        for sample in samples where sample.timelineItem == self { sample.timelineItem = nil }
        mutex.sync { _samples?.removeObjects(samples) }
        samplesChanged()
    }
    
    open override func samplesChanged() {
        super.samplesChanged()
        save()
    }

    // MARK: PersistentObject

    public var transactionDate: Date?
    public var lastSaved: Date?

    open func insert(in db: Database) throws {
        guard unsaved else { return }
        try db.execute("""
            REPLACE INTO TimelineItem (
                itemId, lastSaved, isVisit, deleted, previousItemId, nextItemId, startDate, endDate, radiusMean,
                radiusSD, altitude, stepCount, floorsAscended, floorsDescended, latitude, longitude, activityType
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                itemId.uuidString, transactionDate, true, deleted, previousItemId?.uuidString, nextItemId?.uuidString,
                _dateRange?.start, _dateRange?.end, _radius?.mean, _radius?.sd, _altitude, stepCount, floorsAscended,
                floorsDescended, _center?.coordinate.latitude, _center?.coordinate.longitude, _activityType?.rawValue
            ])
    }

    open func update(in db: Database) throws {
        if unsaved { return }
        try db.execute("""
            UPDATE TimelineItem SET
                lastSaved = ?, isVisit = ?, deleted = ?, previousItemId = ?, nextItemId = ?, startDate = ?,
                endDate = ?, radiusMean = ?, radiusSD = ?, altitude = ?, stepCount = ?, floorsAscended = ?,
                floorsDescended = ?, latitude = ?, longitude = ?, activityType = ?
            WHERE itemId = ?
            """, arguments: [
                transactionDate, true, deleted, previousItemId?.uuidString, nextItemId?.uuidString, _dateRange?.start,
                _dateRange?.end, _radius?.mean, _radius?.sd, _altitude, stepCount, floorsAscended, floorsDescended,
                _center?.coordinate.latitude, _center?.coordinate.longitude, _activityType?.rawValue, itemId.uuidString
            ])
    }
    
    // MARK: Initialisers

    public required init(in store: TimelineStore) { super.init(in: store) }

    public required init(from dict: [String: Any?], in store: TimelineStore) {
        self.lastSaved = dict["lastSaved"] as? Date
        super.init(from: dict, in: store)
    }
    
    // MARK: Decodable

    public required init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.lastSaved = try? container.decode(Date.self, forKey: .lastSaved)
            try super.init(from: decoder)
        } catch {
            fatalError("DECODE FAIL: \(error)")
        }
    }

    enum CodingKeys: String, CodingKey {
        case lastSaved
    }
}

