//
//  TimelineStore.swift
//  LocoKit
//
//  Created by Matt Greenfield on 18/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import LocoKitCore
import CoreLocation
import GRDB

public extension NSNotification.Name {
    static let processingStarted = Notification.Name("processingStarted")
    static let processingStopped = Notification.Name("processingStopped")
}

/// An SQL database backed persistent timeline store.
open class TimelineStore {

    public init() {
        migrateDatabases()
        pool.add(transactionObserver: itemsObserver)

        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] note in
            self?.didBecomeActive()
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] note in
            self?.didEnterBackground()
        }
    }
    
    open var keepDeletedObjectsFor: TimeInterval = 60 * 60
    public var sqlDebugLogging = false

    public var recorder: TimelineRecorder?

    public let mutex = UnfairLock()

    private let itemMap = NSMapTable<NSUUID, TimelineItem>.strongToWeakObjects()
    private let sampleMap = NSMapTable<NSUUID, PersistentSample>.strongToWeakObjects()
    private let modelMap = NSMapTable<NSString, ActivityType>.strongToWeakObjects()
    private let segmentMap = NSMapTable<NSNumber, TimelineSegment>.strongToWeakObjects()

    public private(set) var processing = false {
        didSet {
            guard processing != oldValue else { return }
            let noteName: NSNotification.Name = processing ? .processingStarted : .processingStopped
            onMain { NotificationCenter.default.post(Notification(name: noteName, object: self, userInfo: nil)) }
        }
    }

    public var itemsInStore: Int { return mutex.sync { itemMap.objectEnumerator()?.allObjects.count ?? 0 } }
    public var samplesInStore: Int { return mutex.sync { sampleMap.objectEnumerator()?.allObjects.count ?? 0 } }
    public var modelsInStore: Int { return mutex.sync { modelMap.objectEnumerator()?.allObjects.count ?? 0 } }
    public var segmentsInStore: Int { return mutex.sync { segmentMap.objectEnumerator()?.allObjects.count ?? 0 } }

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

    open lazy var auxiliaryDbUrl: URL = {
        return try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("LocoKitAuxiliary.sqlite")
    }()

    public lazy var poolConfig: Configuration = {
        var config = Configuration()
        config.maximumReaderCount = 12
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

    public lazy var auxiliaryPool: DatabasePool = {
        return try! DatabasePool(path: self.auxiliaryDbUrl.path, configuration: self.poolConfig)
    }()

    // MARK: - Object creation

    open func createVisit(from sample: PersistentSample) -> Visit {
        let visit = Visit(in: self)
        visit.add(sample)
        return visit
    }

    open func createPath(from sample: PersistentSample) -> Path {
        let path = Path(in: self)
        path.add(sample)
        return path
    }

    open func createVisit(from samples: [PersistentSample]) -> Visit {
        let visit = Visit(in: self)
        visit.add(samples)
        return visit
    }

    open func createPath(from samples: [PersistentSample]) -> Path {
        let path = Path(in: self)
        path.add(samples)
        return path
    }

    open func createSample(from sample: ActivityBrainSample) -> PersistentSample {
        let sample = PersistentSample(from: sample, in: self)
        saveOne(sample) // save the sample immediately, to avoid mystery data loss
        return sample
    }

    open func createSample(date: Date, location: CLLocation? = nil, movingState: MovingState = .uncertain,
                                    recordingState: RecordingState) -> PersistentSample {
        let sample = PersistentSample(date: date, location: location, recordingState: recordingState, in: self)
        saveOne(sample) // save the sample immediately, to avoid mystery data loss
        return sample
    }

    // MARK: - Object adding

    open func add(_ timelineItem: TimelineItem) {
        mutex.sync { itemMap.setObject(timelineItem, forKey: timelineItem.itemId as NSUUID) }
    }

    open func add(_ sample: PersistentSample) {
        mutex.sync { sampleMap.setObject(sample, forKey: sample.sampleId as NSUUID) }
    }

    open func add(_ model: ActivityType) {
        mutex.sync { modelMap.setObject(model, forKey: model.geoKey as NSString) }
    }

    open func add(_ segment: TimelineSegment) {
        mutex.sync { segmentMap.setObject(segment, forKey: NSNumber(value: segment.hashValue)) }
    }

    // MARK: - Object fetching

    public func object(for objectId: UUID) -> TimelineObject? {
        return mutex.sync {
            if let item = itemMap.object(forKey: objectId as NSUUID) { return item }
            if let sample = sampleMap.object(forKey: objectId as NSUUID) { return sample }
            return nil
        }
    }

    public func itemInStore(matching: (TimelineItem) -> Bool) -> TimelineItem? {
        return mutex.sync {
            guard let enumerator = itemMap.objectEnumerator() else { return nil }
            for case let item as TimelineItem in enumerator {
                if matching(item) { return item }
            }
            return nil
        }
    }

    public func object(for row: Row) -> TimelineObject {
        if row["itemId"] as String? != nil { return item(for: row) }
        if row["sampleId"] as String? != nil { return sample(for: row) }
        fatalError("Couldn't create an object for the row.")
    }

    // MARK: - Item fetching

    open var mostRecentItem: TimelineItem? {
        return item(where: "deleted = 0 ORDER BY endDate DESC")
    }

    open func item(for itemId: UUID) -> TimelineItem? {
        if let item = object(for: itemId) as? TimelineItem { return item }
        return item(where: "itemId = ?", arguments: [itemId.uuidString])
    }

    public func item(where query: String, arguments: StatementArguments = StatementArguments()) -> TimelineItem? {
        return item(for: "SELECT * FROM TimelineItem WHERE " + query, arguments: arguments)
    }

    public func items(where query: String, arguments: StatementArguments = StatementArguments()) -> [TimelineItem] {
        return items(for: "SELECT * FROM TimelineItem WHERE " + query, arguments: arguments)
    }

    public func item(for query: String, arguments: StatementArguments = StatementArguments()) -> TimelineItem? {
        return try! pool.read { db in
            guard let row = try Row.fetchOne(db, sql: query, arguments: arguments) else { return nil }
            return item(for: row)
        }
    }

    public func items(for query: String, arguments: StatementArguments = StatementArguments()) -> [TimelineItem] {
        return try! pool.read { db in
            var items: [TimelineItem] = []
            let itemRows = try Row.fetchCursor(db, sql: query, arguments: arguments)
            while let row = try itemRows.next() { items.append(item(for: row)) }
            return items
        }
    }

    open func item(for row: Row) -> TimelineItem {
        guard let itemId = row["itemId"] as String? else { fatalError("MISSING ITEMID") }
        if let item = object(for: UUID(uuidString: itemId)!) as? TimelineItem { return item }
        guard let isVisit = row["isVisit"] as Bool? else { fatalError("MISSING ISVISIT BOOL") }
        return isVisit
            ? Visit(from: row.asDict(in: self), in: self)
            : Path(from: row.asDict(in: self), in: self)
    }

    // MARK: Sample fetching

    open func sample(for sampleId: UUID) -> PersistentSample? {
        if let sample = object(for: sampleId) as? PersistentSample { return sample }
        return sample(for: "SELECT * FROM LocomotionSample WHERE sampleId = ?", arguments: [sampleId.uuidString])
    }

    public func sample(where query: String, arguments: StatementArguments = StatementArguments()) -> PersistentSample? {
        return sample(for: "SELECT * FROM LocomotionSample WHERE " + query, arguments: arguments)
    }

    public func samples(where query: String, arguments: StatementArguments = StatementArguments()) -> [PersistentSample] {
        return samples(for: "SELECT * FROM LocomotionSample WHERE " + query, arguments: arguments)
    }

    public func sample(for query: String, arguments: StatementArguments = StatementArguments()) -> PersistentSample? {
        return try! pool.read { db in
            guard let row = try Row.fetchOne(db, sql: query, arguments: arguments) else { return nil }
            return sample(for: row)
        }
    }

    public func samples(for query: String, arguments: StatementArguments = StatementArguments()) -> [PersistentSample] {
        let rows = try! pool.read { db in
            return try Row.fetchAll(db, sql: query, arguments: arguments)
        }
        return rows.map { sample(for: $0) }
    }

    open func sample(for row: Row) -> PersistentSample {
        guard let sampleId = row["sampleId"] as String? else { fatalError("MISSING SAMPLEID") }
        if let sample = object(for: UUID(uuidString: sampleId)!) as? PersistentSample { return sample }
        return PersistentSample(from: row.asDict(in: self), in: self)
    }

    // MARK: - Model fetching

    public func model(where query: String, arguments: StatementArguments = StatementArguments()) -> ActivityType? {
        return model(for: "SELECT * FROM ActivityTypeModel WHERE " + query, arguments: arguments)
    }

    public func model(for query: String, arguments: StatementArguments = StatementArguments()) -> ActivityType? {
        return try! auxiliaryPool.read { db in
            guard let row = try Row.fetchOne(db, sql: query, arguments: arguments) else { return nil }
            return model(for: row)
        }
    }

    public func models(for query: String, arguments: StatementArguments = StatementArguments()) -> [ActivityType] {
        let rows = try! auxiliaryPool.read { db in
            return try Row.fetchAll(db, sql: query, arguments: arguments)
        }
        return rows.map { model(for: $0) }
    }

    func model(for row: Row) -> ActivityType {
        guard let geoKey = row["geoKey"] as String? else { fatalError("MISSING GEOKEY") }
        if let cached = mutex.sync(execute: { modelMap.object(forKey: geoKey as NSString) }) { return cached }
        if let model = ActivityType(dict: row.asDict(in: self), in: self) { return model }
        fatalError("FAILED MODEL INIT FROM ROW")
    }

    // MARK: - Segments

    public func segment(for dateRange: DateInterval) -> TimelineSegment {
        let segment = self.segment(where: "endDate > :startDate AND startDate < :endDate AND deleted = 0 ORDER BY startDate",
                                   arguments: ["startDate": dateRange.start, "endDate": dateRange.end])
        segment.dateRange = dateRange
        return segment
    }

    public func segment(where query: String, arguments: StatementArguments? = nil) -> TimelineSegment {
        var hasher = Hasher()
        hasher.combine("SELECT * FROM TimelineItem WHERE " + query)
        if let arguments = arguments { hasher.combine(arguments.description) }
        let hashValue = hasher.finalize()

        // have an existing one?
        if let cached = segmentMap.object(forKey: NSNumber(value: hashValue)) { return cached }

        // make a fresh one
        let segment = TimelineSegment(where: query, arguments: arguments, in: self)
        self.add(segment)
        return segment
    }

    // MARK: - Counting

    public func countItems(where query: String = "1", arguments: StatementArguments = StatementArguments()) -> Int {
        return try! pool.read { db in
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM TimelineItem WHERE " + query, arguments: arguments)!
        }
    }

    public func countSamples(where query: String = "1", arguments: StatementArguments = StatementArguments()) -> Int {
        return try! pool.read { db in
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM LocomotionSample WHERE " + query, arguments: arguments)!
        }
    }

    public func countModels(where query: String = "1", arguments: StatementArguments = StatementArguments()) -> Int {
        return try! auxiliaryPool.read { db in
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ActivityTypeModel WHERE " + query, arguments: arguments)!
        }
    }

    // MARK: - Saving

    public func save(_ object: TimelineObject, immediate: Bool) {
        mutex.sync {
            if let item = object as? TimelineItem {
                itemsToSave.insert(item)
            } else if let sample = object as? PersistentSample {
                samplesToSave.insert(sample)
            }
        }
        if immediate { save() }
    }

    open func save() {
        var savingItems: Set<TimelineItem> = []
        var savingSamples: Set<PersistentSample> = []

        mutex.sync {
            savingItems = itemsToSave.filter { $0.needsSave }
            itemsToSave.removeAll(keepingCapacity: true)

            savingSamples = samplesToSave.filter { $0.needsSave }
            samplesToSave.removeAll(keepingCapacity: true)
        }

        if !savingItems.isEmpty {
            try! pool.write { db in
                let now = Date()
                for case let item as TimelineObject in savingItems {
                    item.transactionDate = now
                    do { try item.save(in: db) }
                    catch PersistenceError.recordNotFound { os_log("PersistenceError.recordNotFound", type: .error) }
                    catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                        // constraint fails (linked list inconsistencies) are non fatal
                        // so let's break the edges and put the item back in the queue
                        (item as? TimelineItem)?.previousItemId = nil
                        (item as? TimelineItem)?.nextItemId = nil
                        save(item, immediate: false)
                    }
                }
                db.afterNextTransactionCommit { db in
                    for case let item as TimelineObject in savingItems { item.lastSaved = item.transactionDate }
                }
            }
        }
        if !savingSamples.isEmpty {
            try! pool.write { db in
                let now = Date()
                for case let sample as TimelineObject in savingSamples {
                    sample.transactionDate = now
                    do { try sample.save(in: db) }
                    catch PersistenceError.recordNotFound { os_log("PersistenceError.recordNotFound", type: .error) }
                }
                db.afterNextTransactionCommit { db in
                    for case let sample as TimelineObject in savingSamples { sample.lastSaved = sample.transactionDate }
                }
            }
        }
    }

    public func saveOne(_ object: TimelineObject) {
        do {
            try pool.write { db in
                object.transactionDate = Date()
                do { try object.save(in: db) }
                catch PersistenceError.recordNotFound { os_log("PersistenceError.recordNotFound", type: .error) }
                db.afterNextTransactionCommit { db in
                    object.lastSaved = object.transactionDate
                }
            }
        } catch {
            os_log("%@", type: .error, error.localizedDescription)
        }
    }

    // MARK: - Processing

    public func process(changes: @escaping () -> Void) {
        Jobs.addPrimaryJob("TimelineStore.process") {
            self.processing = true
            changes()
            self.save()
            self.processing = false
        }
    }

    // MARK: - Background and Foreground

    private func didBecomeActive() {
        guard let segments = mutex.sync(execute: { segmentMap.objectEnumerator()?.allObjects as? [TimelineSegment] }) else { return }
        segments.forEach { $0.shouldReclassifySamples = true }
    }

    private func didEnterBackground() {
        guard let segments = mutex.sync(execute: { segmentMap.objectEnumerator()?.allObjects as? [TimelineSegment] }) else { return }
        segments.forEach { $0.shouldReclassifySamples = false }
    }

    // MARK: - Database housekeeping

    open func hardDeleteSoftDeletedObjects() {
        let deadline = Date(timeIntervalSinceNow: -keepDeletedObjectsFor)
        do {
            try pool.write { db in
                try db.execute(sql: "DELETE FROM LocomotionSample WHERE deleted = 1 AND date < ?", arguments: [deadline])
                try db.execute(sql: "DELETE FROM TimelineItem WHERE deleted = 1 AND (endDate < ? OR endDate IS NULL)", arguments: [deadline])
            }
        } catch {
            os_log("%@", error.localizedDescription)
        }
    }

    open func deleteStaleSharedModels() {
        let deadline = Date(timeIntervalSinceNow: -ActivityTypesCache.staleLastUpdatedAge)
        do {
            try auxiliaryPool.write { db in
                try db.execute(sql: "DELETE FROM ActivityTypeModel WHERE isShared = 1 AND version = 0")
                try db.execute(sql: "DELETE FROM ActivityTypeModel WHERE isShared = 1 AND lastUpdated IS NULL")
                try db.execute(sql: "DELETE FROM ActivityTypeModel WHERE isShared = 1 AND lastUpdated < ?", arguments: [deadline])
            }
        } catch {
            os_log("%@", error.localizedDescription)
        }
    }

    // MARK: - Database creation and migrations

    public var migrator = DatabaseMigrator()
    public var auxiliaryDbMigrator = DatabaseMigrator()

    open func migrateDatabases() {
        registerMigrations()
        try! migrator.migrate(pool)

        registerAuxiliaryDbMigrations()
        try! auxiliaryDbMigrator.migrate(auxiliaryPool)

        delay(10, onQueue: DispatchQueue.global()) {
            self.registerDelayedMigrations()
            try! self.migrator.migrate(self.pool)
        }
    }

    open var dateFields: [String] { return ["lastSaved", "lastUpdated", "startDate", "endDate", "date"] }
    open var boolFields: [String] { return ["isVisit", "deleted", "locationIsBogus", "isShared", "needsUpdate"] }

}

public extension Row {
    func asDict(in store: TimelineStore) -> [String: Any?] {
        let dateFields = store.dateFields
        let boolFields = store.boolFields
        return Dictionary<String, Any?>(self.map { column, value in
            if dateFields.contains(column) { return (column, Date.fromDatabaseValue(value)) }
            if boolFields.contains(column) { return (column, Bool.fromDatabaseValue(value)) }
            return (column, value.storage.value)
        }, uniquingKeysWith: { left, _ in left })
    }
}

public extension Database {
    func explain(query: String, arguments: StatementArguments = StatementArguments()) throws {
        for explain in try Row.fetchAll(self, sql: "EXPLAIN QUERY PLAN " + query, arguments: arguments) {
            print("EXPLAIN: \(explain)")
        }
    }
}
