//
//  TimelineStore.swift
//  ArcKit
//
//  Created by Matt Greenfield on 18/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import ArcKitCore

/// An in-memory timeline data store. For persistent timeline data storage, see `PersistentTimelineStore`.
open class TimelineStore {

    public weak var manager: TimelineManager?
    public let cacheDelegate = TimelineStoreCacheDelegate()

    public let itemCache = NSCache<NSUUID, TimelineItem>()
    public let sampleCache = NSCache<NSUUID, LocomotionSample>()

    init() {
        self.itemCache.delegate = cacheDelegate
        self.sampleCache.delegate = cacheDelegate
    }

    open func item(for itemId: UUID) -> TimelineItem? { return itemCache.object(forKey: itemId as NSUUID) }

    open func sample(for sampleId: UUID) -> LocomotionSample? { return sampleCache.object(forKey: sampleId as NSUUID) }
    
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

    open func add(_ timelineItem: TimelineItem) {
        timelineItem.store = self
        itemCache.setObject(timelineItem, forKey: timelineItem.itemId as NSUUID)
        timelineItem.inTheStore = true
    }

    open func add(_ sample: LocomotionSample) {
        sample.store = self
        sampleCache.setObject(sample, forKey: sample.sampleId as NSUUID)
        sample.inTheStore = true
    }

}
