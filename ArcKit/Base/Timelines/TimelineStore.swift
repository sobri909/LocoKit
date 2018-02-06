//
//  TimelineStore.swift
//  ArcKit
//
//  Created by Matt Greenfield on 18/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import ArcKitCore

/// An in-memory timeline data store. For persistent timeline data storage, see `PersistentTimelineStore`.
open class TimelineStore {

    public weak var manager: TimelineManager?
    public let cacheDelegate = TimelineStoreCacheDelegate()

    public let mutex = UnfairLock()
    private let itemCache = NSCache<NSUUID, TimelineItem>()
    private let sampleCache = NSCache<NSUUID, LocomotionSample>()
    private var retainedObjects = Dictionary<UUID, TimelineObject>()

    init() {
        self.itemCache.delegate = cacheDelegate
        self.sampleCache.delegate = cacheDelegate
    }

    public func object(for objectId: UUID) -> TimelineObject? {
        let retained = mutex.sync { retainedObjects[objectId] }
        if let object = retained { return object }
        if let item = itemCache.object(forKey: objectId as NSUUID) { return item }
        if let sample = sampleCache.object(forKey: objectId as NSUUID) { return sample }
        return nil
    }

    open func item(for itemId: UUID) -> TimelineItem? { return object(for: itemId) as? TimelineItem }

    open func sample(for sampleId: UUID) -> LocomotionSample? { return object(for: sampleId) as? LocomotionSample }
    
    open func createVisit(from sample: LocomotionSample) -> Visit {
        let visit = Visit(in: self)
        visit.add(sample)
        return visit
    }

    open func createPath(from sample: LocomotionSample) -> Path {
        let path = Path(in: self)
        path.add(sample)
        return path
    }

    open func createSample(from sample: ActivityBrainSample) -> LocomotionSample {
        return LocomotionSample(from: sample, in: self)
    }

    // Managing object presence in the store

    // Add a timeline item to the store, but don't retain it.
    open func add(_ timelineItem: TimelineItem) {
        timelineItem.store = self
        itemCache.setObject(timelineItem, forKey: timelineItem.itemId as NSUUID)
        timelineItem.inTheStore = true
    }

    // Add a locomotion sample to the store, but don't retain it.
    open func add(_ sample: LocomotionSample) {
        sample.store = self
        sampleCache.setObject(sample, forKey: sample.sampleId as NSUUID)
        sample.inTheStore = true
    }

    /**
     Add a timeline object to the store, and retain it. This ensures that the object will not be removed until it is
     explictly released.
     */
    public func retain(_ object: TimelineObject) { retain([object]) }

    public func retain(_ objects: [TimelineObject]) {
        mutex.sync {
            for object in objects {
                retainedObjects[object.objectId] = object
                if let item = object as? TimelineItem {
                    itemCache.removeObject(forKey: item.itemId as NSUUID)
                    item.inTheStore = true
                } else if let sample = object as? LocomotionSample {
                    sampleCache.removeObject(forKey: sample.sampleId as NSUUID)
                    sample.inTheStore = true
                }
            }
        }
    }

    /**
     Release a timeline object from the store. Note that the object will still remain in the store's cache until iOS
     decides to evict it.
     */
    public func release(_ object: TimelineObject) { release([object]) }

    open func release(_ objects: [TimelineObject]) {
        mutex.sync {
            for object in objects {
                guard object.inTheStore else { continue }
                if let item = object as? TimelineItem, manager!.activeItems.contains(item) { continue }

                // release it
                retainedObjects[object.objectId] = nil

                // store it in the volatile caches
                if let item = object as? TimelineItem {
                    itemCache.setObject(item, forKey: item.itemId as NSUUID)
                } else if let sample = object as? LocomotionSample {
                    sampleCache.setObject(sample, forKey: sample.sampleId as NSUUID)
                }
            }
        }
    }

    open func save(immediate: Bool = true) {}
}
