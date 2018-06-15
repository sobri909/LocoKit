//
//  PersistentTimelineStore.swift
//  LocoKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import os.log
import GRDB
import LocoKitCore

open class PersistentTimelineStore: TimelineStore {

    open var keepDeletedObjectsFor: TimeInterval = 60 * 60
    public var sqlDebugLogging = false

    public var itemsToSave: Set<TimelineItem> = []
    public var samplesToSave: Set<PersistentSample> = []

    private lazy var itemsObserver = {
        return ItemsObserver(store: self)
    }()

    open lazy var dbUrl: URL = {
        return try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("LocoKit.sqlite")
    }()

    public lazy var poolConfig: Configuration = {
        var config = Configuration()
        if sqlDebugLogging {
            config.trace = {
                if self.sqlDebugLogging { os_log("SQL: %@", type: .default, $0) }
            }
        }
        return config
    }()

    public lazy var pool: DatabasePool = {
        return try! DatabasePool(path: self.dbUrl.path, configuration: self.poolConfig)
    }()

    public override init() {
        super.init()
        migrateDatabase()
        pool.add(transactionObserver: itemsObserver)
        pool.setupMemoryManagement(in: UIApplication.shared)
    }

    // MARK: - Item / Sample creation

    open override func createVisit(from sample: LocomotionSample) -> PersistentVisit {
        let visit = PersistentVisit(in: self)
        visit.add(sample)
        return visit
    }

    open override func createPath(from sample: LocomotionSample) -> PersistentPath {
        let path = PersistentPath(in: self)
        path.add(sample)
        return path
    }

    open func createVisit(from samples: [LocomotionSample]) -> PersistentVisit {
        let visit = PersistentVisit(in: self)
        visit.add(samples)
        return visit
    }

    open func createPath(from samples: [LocomotionSample]) -> PersistentPath {
        let path = PersistentPath(in: self)
        path.add(samples)
        return path
    }

    open override func createSample(from sample: ActivityBrainSample) -> PersistentSample {
        return PersistentSample(from: sample, in: self)
    }

    public func object(for row: Row) -> TimelineObject {
        if row["itemId"] as String? != nil { return item(for: row) }
        if row["sampleId"] as String? != nil { return sample(for: row) }
        fatalError("Couldn't create an object for the row.")
    }

    open func item(for row: Row) -> TimelineItem {
        guard let itemId = row["itemId"] as String? else { fatalError("MISSING ITEMID") }
        if let item = object(for: UUID(uuidString: itemId)!) as? TimelineItem { return item }
        guard let isVisit = row["isVisit"] as Bool? else { fatalError("MISSING ISVISIT BOOL") }
        return isVisit
            ? PersistentVisit(from: row.asDict(in: self), in: self)
            : PersistentPath(from: row.asDict(in: self), in: self)
    }

    open func sample(for row: Row) -> PersistentSample {
        guard let sampleId = row["sampleId"] as String? else { fatalError("MISSING SAMPLEID") }
        if let sample = object(for: UUID(uuidString: sampleId)!) as? PersistentSample { return sample }
        return PersistentSample(from: row.asDict(in: self), in: self)
    }

    // MARK: - Item fetching

    open override var mostRecentItem: TimelineItem? {
        return item(where: "deleted = 0 ORDER BY endDate DESC")
    }

    open override func item(for itemId: UUID) -> TimelineItem? {
        if let item = object(for: itemId) as? TimelineItem { return item }
        return item(where: "itemId = ?", arguments: [itemId.uuidString])
    }

    public func item(where query: String, arguments: StatementArguments? = nil) -> TimelineItem? {
        return item(for: "SELECT * FROM TimelineItem WHERE " + query + " LIMIT 1", arguments: arguments)
    }

    public func items(where query: String, arguments: StatementArguments? = nil) -> [TimelineItem] {
        return items(for: "SELECT * FROM TimelineItem WHERE " + query, arguments: arguments)
    }

    public func item(for query: String, arguments: StatementArguments? = nil) -> TimelineItem? {
        return try! pool.read { db in
            guard let row = try Row.fetchOne(db, query, arguments: arguments) else { return nil }
            return item(for: row)
        }
    }

    public func items(for query: String, arguments: StatementArguments? = nil) -> [TimelineItem] {
        return try! pool.read { db in
            var items: [TimelineItem] = []
            let itemRows = try Row.fetchCursor(db, query, arguments: arguments)
            while let row = try itemRows.next() { items.append(item(for: row)) }
            return items
        }
    }

    // MARK: Sample fetching

    open override func sample(for sampleId: UUID) -> PersistentSample? {
        if let sample = object(for: sampleId) as? PersistentSample { return sample }
        return sample(for: "SELECT * FROM LocomotionSample WHERE sampleId = ?", arguments: [sampleId.uuidString])
    }

    public func samples(where query: String, arguments: StatementArguments? = nil) -> [PersistentSample] {
        return samples(for: "SELECT * FROM LocomotionSample WHERE " + query, arguments: arguments)
    }

    public func sample(for query: String, arguments: StatementArguments? = nil) -> PersistentSample? {
        return try! pool.read { db in
            guard let row = try Row.fetchOne(db, query, arguments: arguments) else { return nil }
            return sample(for: row)
        }
    }

    public func samples(for query: String, arguments: StatementArguments? = nil) -> [PersistentSample] {
        let rows = try! pool.read { db in
            return try Row.fetchAll(db, query, arguments: arguments)
        }
        return rows.map { sample(for: $0) }
    }

    // MARK: - Counting

    public func countItems(where query: String = "1", arguments: StatementArguments? = nil) -> Int {
        return try! pool.read { db in
            return try Int.fetchOne(db, "SELECT COUNT(*) FROM TimelineItem WHERE " + query, arguments: arguments)!
        }
    }

    public func countSamples(where query: String = "1", arguments: StatementArguments? = nil) -> Int {
        return try! pool.read { db in
            return try Int.fetchOne(db, "SELECT COUNT(*) FROM LocomotionSample WHERE " + query, arguments: arguments)!
        }
    }

    // MARK: - Saving

    public func save(_ object: PersistentObject, immediate: Bool) {
        mutex.sync {
            if let item = object as? TimelineItem {
                itemsToSave.insert(item)
            } else if let sample = object as? PersistentSample {
                samplesToSave.insert(sample)
            }
        }
        if immediate { save() }
    }

    open override func save() {
        var savingItems: Set<TimelineItem> = []
        var savingSamples: Set<PersistentSample> = []

        mutex.sync {
            savingItems = itemsToSave.filter { ($0 as? PersistentItem)?.needsSave == true }
            itemsToSave.removeAll(keepingCapacity: true)

            savingSamples = samplesToSave.filter { $0.needsSave }
            samplesToSave.removeAll(keepingCapacity: true)
        }

        if !savingItems.isEmpty {
            try! pool.write { db in
                let now = Date()
                for case let item as PersistentObject in savingItems {
                    item.transactionDate = now
                    do { try item.save(in: db) }
                    catch PersistenceError.recordNotFound { os_log("PersistenceError.recordNotFound", type: .error) }
                }
                db.afterNextTransactionCommit { db in
                    for case let item as PersistentObject in savingItems { item.lastSaved = item.transactionDate }
                }
            }
        }
        if !savingSamples.isEmpty {
            try! pool.write { db in
                let now = Date()
                for case let sample as PersistentObject in savingSamples {
                    sample.transactionDate = now
                    do { try sample.save(in: db) }
                    catch PersistenceError.recordNotFound { os_log("PersistenceError.recordNotFound", type: .error) }
                }
                db.afterNextTransactionCommit { db in
                    for case let sample as PersistentObject in savingSamples { sample.lastSaved = sample.transactionDate }
                }
            }
        }
    }

    // MARK: - Database housekeeping

    open func hardDeleteSoftDeletedObjects() {
        let deadline = Date(timeIntervalSinceNow: -keepDeletedObjectsFor)
        do {
            try pool.write { db in
                try db.execute("DELETE FROM LocomotionSample WHERE deleted = 1 AND date < ?", arguments: [deadline])
                try db.execute("DELETE FROM TimelineItem WHERE deleted = 1 AND (endDate < ? OR endDate IS NULL)", arguments: [deadline])
            }
        } catch {
            os_log("%@", error.localizedDescription)
        }
    }

    // MARK: - Database creation and migrations

    public var migrator = DatabaseMigrator()

    open func migrateDatabase() {
        registerMigrations()
        try! migrator.migrate(pool)
    }

    open var dateFields: [String] { return ["lastSaved", "lastModified", "startDate", "endDate", "date"] }
    open var boolFields: [String] { return ["isVisit", "deleted"] }
}

class ItemsObserver: TransactionObserver {

    var store: PersistentTimelineStore
    var changedRowIds: Set<Int64> = []

    init(store: PersistentTimelineStore) {
        self.store = store
    }

    // observe updates to next/prev item links
    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        switch eventKind {
        case .update(let tableName, let columnNames):
            guard tableName == "TimelineItem" else { return false }
            let itemEdges: Set<String> = ["previousItemId", "nextItemId"]
            return itemEdges.intersection(columnNames).count > 0
        default: return false
        }
    }

    func databaseDidChange(with event: DatabaseEvent) {
        changedRowIds.insert(event.rowID)
    }

    func databaseDidCommit(_ db: Database) {
        let rowIds: Set<Int64> = store.mutex.sync {
            let rowIds = changedRowIds
            changedRowIds = []
            return rowIds
        }

        if rowIds.isEmpty { return }

        /** maintain the timeline items linked list locally, for changes made outside the managed environment **/

        do {
            let marks = repeatElement("?", count: rowIds.count).joined(separator: ",")
            let query = "SELECT itemId, previousItemId, nextItemId FROM TimelineItem WHERE rowId IN (\(marks))"
            let rows = try Row.fetchCursor(db, query, arguments: StatementArguments(rowIds))

            while let row = try rows.next() {
                let previousItemIdString = row["previousItemId"] as String?
                let nextItemIdString = row["nextItemId"] as String?
                
                guard let uuidString = row["itemId"] as String?, let itemId = UUID(uuidString: uuidString) else { continue }
                guard let item = store.object(for: itemId) as? TimelineItem else { continue }

                if let uuidString = previousItemIdString, item.previousItemId?.uuidString != uuidString {
                    item.previousItemId = UUID(uuidString: uuidString)

                } else if previousItemIdString == nil && item.previousItemId != nil {
                    item.previousItemId = nil
                }

                if let uuidString = nextItemIdString, item.nextItemId?.uuidString != uuidString {
                    item.nextItemId = UUID(uuidString: uuidString)

                } else if nextItemIdString == nil && item.nextItemId != nil {
                    item.nextItemId = nil
                }
            }

        } catch {
            os_log("SQL Exception: %@", error.localizedDescription)
        }
    }

    func databaseDidRollback(_ db: Database) {}
}

public extension Row {
    func asDict(in store: PersistentTimelineStore) -> [String: Any?] {
        let dateFields = store.dateFields
        let boolFields = store.boolFields
        return Dictionary<String, Any?>(self.map { column, value in
            if dateFields.contains(column) { return (column, Date.fromDatabaseValue(value)) }
            if boolFields.contains(column) { return (column, Bool.fromDatabaseValue(value)) }
            return (column, value.storage.value)
        }, uniquingKeysWith: { left, _ in left })
    }
}
