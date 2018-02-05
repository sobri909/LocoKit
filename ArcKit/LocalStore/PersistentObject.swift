//
//  PersistentObject.swift
//  ArcKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import os.log
import GRDB

public typealias PersistentItem = PersistentObject & TimelineItem

public protocol PersistentObject: TimelineObject, Persistable {

    var persistentStore: PersistentTimelineStore { get }
    var transactionDate: Date? { get set }
    var lastSaved: Date? { get set }
    var unsaved: Bool { get }

    func save(immediate: Bool)
    func save(in db: Database) throws

}

public extension PersistentObject {
    public var unsaved: Bool { return lastSaved == nil }
    public func save(immediate: Bool = false) { persistentStore.save(self, immediate: immediate) }
    public func save(in db: Database) throws { if unsaved { try insert(db) } else { try update(db) } }
}

public extension PersistentObject where Self: TimelineItem {
    public var persistentStore: PersistentTimelineStore { return store as! PersistentTimelineStore }
}

