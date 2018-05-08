//
//  TimelineStore.swift
//  LocoKit
//
//  Created by Matt Greenfield on 18/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import LocoKitCore

/// An in-memory timeline data store. For persistent timeline data storage, see `PersistentTimelineStore`.
open class TimelineStore {

    public var recorder: TimelineRecorder?

    public let mutex = UnfairLock()

    private let itemMap = NSMapTable<NSUUID, TimelineItem>.strongToWeakObjects()
    private let sampleMap = NSMapTable<NSUUID, LocomotionSample>.strongToWeakObjects()
    private let processingQueue = DispatchQueue(label: "TimelineProcessing")

    public var itemsInStore: Int { return mutex.sync { itemMap.count } }
    public var samplesInStore: Int { return mutex.sync { sampleMap.count } }

    public func object(for objectId: UUID) -> TimelineObject? {
        return mutex.sync {
            if let item = itemMap.object(forKey: objectId as NSUUID) { return item }
            if let sample = sampleMap.object(forKey: objectId as NSUUID) { return sample }
            return nil
        }
    }

    open var mostRecentItem: TimelineItem? { return nil }

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

    open func add(_ timelineItem: TimelineItem) {
        mutex.sync { itemMap.setObject(timelineItem, forKey: timelineItem.itemId as NSUUID) }
    }

    open func add(_ sample: LocomotionSample) {
        mutex.sync { sampleMap.setObject(sample, forKey: sample.sampleId as NSUUID) }
    }

    public func process(changes: @escaping () -> Void) {
        processingQueue.async {
            changes()
            self.save(immediate: true)
        }
    }

    open func save(immediate: Bool) {}

}
