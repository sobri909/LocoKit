//
//  TimelineObject.swift
//  LocoKit
//
//  Created by Matt Greenfield on 27/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB

public protocol TimelineObject: class, PersistableRecord {

    var objectId: UUID { get }
    var source: String { get set }
    var store: TimelineStore? { get }

    var transactionDate: Date? { get set }
    var lastSaved: Date? { get set }
    var unsaved: Bool { get }
    var hasChanges: Bool { get set }
    var needsSave: Bool { get }

    func save(immediate: Bool)
    func save(in db: Database) throws

}

public extension TimelineObject {
    var unsaved: Bool { return lastSaved == nil }
    var needsSave: Bool { return unsaved || hasChanges }
    func save(immediate: Bool = false) { store?.save(self, immediate: immediate) }
    func save(in db: Database) throws {
        if unsaved { try insert(db) } else if hasChanges { try update(db) }
        hasChanges = false
    }
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        return PersistenceConflictPolicy(insert: .replace, update: .abort)
    }
}

