//
//  TimelineObject.swift
//  LocoKit
//
//  Created by Matt Greenfield on 27/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import os.log
import Foundation
import GRDB

public protocol TimelineObject: AnyObject, Encodable, PersistableRecord {

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

    var invalidated: Bool { get }
    func invalidate()
    
}

public extension TimelineObject {
    var unsaved: Bool { return lastSaved == nil }
    var needsSave: Bool { return unsaved || hasChanges }
    func save(immediate: Bool = false) { store?.save(self, immediate: immediate) }
    func save(in db: Database) throws {
        if invalidated { os_log(.error, "Can't save changes to an invalid object"); return }
        if unsaved { try insert(db) } else if hasChanges { try update(db) }
        hasChanges = false
    }
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        return PersistenceConflictPolicy(insert: .replace, update: .abort)
    }
}

