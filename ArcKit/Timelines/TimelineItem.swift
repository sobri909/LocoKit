//
//  TimelineItem.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public class TimelineItem {

    private var _samples: [LocomotionSample] = []

    private(set) public var itemId: UUID

    /// The LocomotionSamples recorded between the item's `start` and `end` dates.
    public var samples: [LocomotionSample] {
        return _samples
    }
    private(set) public var dateRange: DateInterval?

    /// The timeline item's start date
    public var start: Date? {
        return dateRange?.start
    }

    /// The timeline item's end date
    public var end: Date? {
        return dateRange?.end
    }

    public weak var previousItem: TimelineItem?
    public weak var nextItem: TimelineItem?

    public convenience init(sample: LocomotionSample) {
        self.init(samples: [sample])
    }

    public init(samples: [LocomotionSample]) {
        self.itemId = UUID()
        self.add(samples)
    }

    // MARK: Timeline item validity

    public var isInvalid: Bool {
        return !isValid
    }

    // this is defined properly in the subclasses
    public var isValid: Bool {
        fatalError("Shouldn't be here.")
    }

    // this is defined properly in the subclasses
    public var isWorthKeeping: Bool {
        fatalError("Shouldn't be here.")
    }

    internal var keepnessScore: Int {
        if isWorthKeeping {
            return 2
        }
        if isValid {
            return 1
        }
        return 0
    }

    /// The duration of the timeline item, as the time interval between the start and end dates.
    public var duration: TimeInterval {
        guard let dateRange = dateRange else {
            return 0
        }
        return dateRange.duration
    }

    /**
     The time interval between this item and the given item.

     - Note: A negative value indicates overlapping items, and thus the duration of their overlap.
     */
    public func timeIntervalFrom(_ otherItem: TimelineItem) -> TimeInterval? {
        guard let myRange = self.dateRange, let theirRange = otherItem.dateRange else {
            return nil
        }
        if myRange < theirRange {
            return theirRange.start.timeIntervalSince(myRange.end)
        }
        if myRange > theirRange {
            return myRange.start.timeIntervalSince(theirRange.end)
        }
        if let intersection = myRange.intersection(with: theirRange) {
            return -intersection.duration
        }
        return nil
    }

    internal func edgeSample(with otherItem: TimelineItem) -> LocomotionSample? {
        if otherItem == previousItem {
            return samples.first
        }
        if otherItem == nextItem {
            return samples.last
        }
        return nil
    }

    internal func secondToEdgeSample(with otherItem: TimelineItem) -> LocomotionSample? {
        if otherItem == previousItem {
            return samples.second
        }
        if otherItem == nextItem {
            return samples.secondToLast
        }
        return nil
    }

    // MARK: Modifying the timeline item

    public func add(_ sample: LocomotionSample) {
        add([sample])
    }

    public func add(_ samples: [LocomotionSample]) {
        for sample in samples {
            sample.timelineItem?.remove(sample)
            sample.timelineItem = self
        }
        _samples += samples
        _samples.sort { $0.date < $1.date }
        samplesChanged()
    }

    public func remove(_ sample: LocomotionSample) {
        remove([sample])
    }

    public func remove(_ samples: [LocomotionSample]) {
        for sample in samples {
            sample.timelineItem = nil
        }
        _samples.removeObjects(samples)
        samplesChanged()
    }

    // subclasses handle this
    internal func distance(from: TimelineItem) -> CLLocationDistance? {
        fatalError("Shouldn't be here.")
    }

    // subclasses handle this
    internal func maximumMergeableDistance(from: TimelineItem) -> CLLocationDistance {
        fatalError("Shouldn't be here.")
    }

    // implemented in the subclasses
    public func sanitiseEdges() {
        fatalError("Shouldn't be here.")
    }

    internal func samplesChanged() {
        if let start = samples.first?.date, let end = samples.last?.date {
            dateRange = DateInterval(start: start, end: end)
        } else {
            dateRange = nil
        }
    }
}

extension TimelineItem: Equatable {

    public static func ==(lhs: TimelineItem, rhs: TimelineItem) -> Bool {
        return lhs.itemId == rhs.itemId
    }

}
