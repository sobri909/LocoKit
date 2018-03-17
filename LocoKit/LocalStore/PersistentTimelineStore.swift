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

    open var saveBatchSize = 50
    open let keepDeletedItemsFor: TimeInterval = 60 * 60
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

    // MARK: Adding Items / Samples to the store

    open override func add(_ timelineItem: TimelineItem) {
        guard let persistentItem = timelineItem as? PersistentItem else { fatalError("NOT A PERSISTENT ITEM") }
        super.add(persistentItem)
        if persistentItem.unsaved { persistentItem.save() }
    }

    open override func release(_ objects: [TimelineObject]) {
        var filtered: [TimelineObject] = []
        mutex.sync {
            // don't release objects that're in the save queues
            for object in objects {
                if let item = object as? TimelineItem, itemsToSave.contains(item) { continue }
                if let sample = object as? PersistentSample, samplesToSave.contains(sample) { continue }
                filtered.append(object)
            }
        }
        super.release(filtered)
    }

    // MARK: Item / Sample creation

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
        if let cached = cachedObject(for: UUID(uuidString: itemId)!) as? TimelineItem { return cached }
        guard let isVisit = row["isVisit"] as Bool? else { fatalError("MISSING ISVISIT BOOL") }
        return isVisit
            ? PersistentVisit(from: row.asDict(in: self), in: self)
            : PersistentPath(from: row.asDict(in: self), in: self)
    }

    open func sample(for row: Row) -> PersistentSample {
        guard let sampleId = row["sampleId"] as String? else { fatalError("MISSING SAMPLEID") }
        if let cached = cachedObject(for: UUID(uuidString: sampleId)!) as? PersistentSample { return cached }
        return PersistentSample(from: row.asDict(in: self), in: self)
    }

    // MARK: Item fetching

    open override func item(for itemId: UUID) -> TimelineItem? {
        if let cached = cachedObject(for: itemId) as? TimelineItem { return cached }
        return item(for: "SELECT * FROM TimelineItem WHERE itemId = ? LIMIT 1", arguments: [itemId.uuidString])
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
        if let cached = cachedObject(for: sampleId) as? PersistentSample { return cached }
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
        return try! pool.read { db in
            var samples: [PersistentSample] = []
            let rows = try Row.fetchCursor(db, query, arguments: arguments)
            while let row = try rows.next() { samples.append(sample(for: row)) }
            return samples
        }
    }

    // MARK: Counting

    public func countItems(where query: String, arguments: StatementArguments? = nil) -> Int {
        return try! pool.read { db in
            return try Int.fetchOne(db, "SELECT COUNT(*) FROM TimelineItem WHERE " + query, arguments: arguments)!
        }
    }

    public func countSamples(where query: String, arguments: StatementArguments? = nil) -> Int {
        return try! pool.read { db in
            return try Int.fetchOne(db, "SELECT COUNT(*) FROM LocomotionSample WHERE " + query, arguments: arguments)!
        }
    }

    // MARK: Saving

    public func save(_ object: PersistentObject, immediate: Bool = false) {
        if !object.inTheStore {
            if object is TimelineItem {
                os_log("UNSAFE SAVE: Item not in the store")
            }
        }
        retain(object)
        mutex.sync {
            if let item = object as? TimelineItem {
                itemsToSave.insert(item)
            } else if let sample = object as? PersistentSample {
                samplesToSave.insert(sample)
            }
        }
        save(immediate: immediate)
    }

    open override func save(immediate: Bool = true) {
        var savingItems: Set<TimelineItem> = []
        var savingSamples: Set<PersistentSample> = []

        mutex.sync {
            guard immediate || (itemsToSave.count + samplesToSave.count >= saveBatchSize) else { return }

            savingItems = itemsToSave
            itemsToSave.removeAll(keepingCapacity: true)

            savingSamples = samplesToSave
            samplesToSave.removeAll(keepingCapacity: true)
        }

        if !savingItems.isEmpty {
            try! pool.writeInTransaction { db in
                let now = Date()
                for case let item as PersistentObject in savingItems { item.transactionDate = now }
                for case let item as PersistentObject in savingItems { try item.save(in: db) }
                db.afterNextTransactionCommit { db in
                    for case let item as PersistentObject in savingItems { item.lastSaved = item.transactionDate }
                    self.release(Array(savingItems))
                }
                return .commit
            }
        }
        if !savingSamples.isEmpty {
            try! pool.writeInTransaction { db in
                let now = Date()
                for case let sample as PersistentObject in savingSamples { sample.transactionDate = now  }
                for case let sample as PersistentObject in savingSamples { try sample.save(in: db) }
                db.afterNextTransactionCommit { db in
                    for case let sample as PersistentObject in savingSamples { sample.lastSaved = sample.transactionDate }
                    self.release(Array(savingSamples))
                }
                return .commit
            }
        }
    }

    // MARK: Database housekeeping

    open func hardDeleteSoftDeletedItems() {
        let deadline = Date(timeIntervalSinceNow: -keepDeletedItemsFor)
        try! pool.write { db in
            try db.execute("DELETE FROM TimelineItem WHERE deleted = 1 AND endDate < ?", arguments: [deadline])
        }
    }

    // MARK: Database creation and migrations

    public var migrator = DatabaseMigrator()

    open func migrateDatabase() {
        migrator.registerMigration("CreateTables") { db in
            try db.create(table: "TimelineItem") { table in
                table.column("itemId", .text).primaryKey()

                table.column("lastSaved", .datetime).notNull().indexed()
                table.column("deleted", .boolean).notNull().indexed()
                table.column("isVisit", .boolean).notNull().indexed()
                table.column("startDate", .datetime).indexed()
                table.column("endDate", .datetime).indexed()

                table.column("previousItemId", .text).indexed()
                    .references("TimelineItem", onDelete: .setNull, deferred: true)
                    .check(sql: "previousItemId != itemId AND (previousItemId IS NULL OR deleted = 0)")
                table.column("nextItemId", .text).indexed()
                    .references("TimelineItem", onDelete: .setNull, deferred: true)
                    .check(sql: "nextItemId != itemId AND (nextItemId IS NULL OR deleted = 0)")

                table.column("radiusMean", .double)
                table.column("radiusSD", .double)
                table.column("altitude", .double)
                table.column("stepCount", .integer)
                table.column("floorsAscended", .integer)
                table.column("floorsDescended", .integer)
                table.column("activityType", .text)

                // item.center
                table.column("latitude", .double)
                table.column("longitude", .double)
            }
            try db.create(table: "LocomotionSample") { table in
                table.column("sampleId", .text).primaryKey()

                table.column("date", .datetime).notNull().indexed()
                table.column("lastSaved", .datetime).notNull()
                table.column("movingState", .text).notNull()
                table.column("recordingState", .text).notNull()

                table.column("timelineItemId", .text).references("TimelineItem", deferred: true).indexed()

                table.column("stepHz", .double)
                table.column("courseVariance", .double)
                table.column("xyAcceleration", .double)
                table.column("zAcceleration", .double)
                table.column("coreMotionActivityType", .text)
                table.column("confirmedType", .text)

                // sample.location
                table.column("latitude", .double).indexed()
                table.column("longitude", .double).indexed()
                table.column("altitude", .double)
                table.column("horizontalAccuracy", .double)
                table.column("verticalAccuracy", .double)
                table.column("speed", .double)
                table.column("course", .double)
            }

            // maintain the linked list from the nextItem side
            try db.execute("""
                CREATE TRIGGER TimelineItem_update_nextItemId AFTER UPDATE OF nextItemId ON TimelineItem
                    BEGIN
                        UPDATE TimelineItem SET previousItemId = NULL WHERE itemId = OLD.nextItemId;
                        UPDATE TimelineItem SET previousItemId = NEW.itemId WHERE itemId = NEW.nextItemId;
                    END
                """)

            // maintain the linked list from the previousItem side
            try db.execute("""
                CREATE TRIGGER TimelineItem_update_previousItemId AFTER UPDATE OF previousItemId ON TimelineItem
                    BEGIN
                        UPDATE TimelineItem SET nextItemId = NULL WHERE itemId = OLD.previousItemId;
                        UPDATE TimelineItem SET nextItemId = NEW.itemId WHERE itemId = NEW.previousItemId;
                    END
                """)

            // maintain the linked list at insert time
            try db.execute("""
                CREATE TRIGGER TimelineItem_insert AFTER INSERT ON TimelineItem
                    BEGIN
                        UPDATE TimelineItem SET previousItemId = NEW.itemId WHERE itemId = NEW.nextItemId;
                        UPDATE TimelineItem SET nextItemId = NEW.itemId WHERE itemId = NEW.previousItemId;
                    END
                """)
        }
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

        do {
            let marks = repeatElement("?", count: rowIds.count).joined(separator: ",")
            let query = "SELECT itemId, previousItemId, nextItemId FROM TimelineItem WHERE rowId IN (\(marks))"
            let rows = try Row.fetchCursor(db, query, arguments: StatementArguments(rowIds))

            while let row = try rows.next() {
                let previousItemIdString = row["previousItemId"] as String?
                let nextItemIdString = row["nextItemId"] as String?
                
                guard let uuidString = row["itemId"] as String?, let itemId = UUID(uuidString: uuidString) else { continue }
                guard let item = store.cachedObject(for: itemId) as? TimelineItem else { continue }

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
