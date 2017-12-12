//
//  TimelineItem.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

@objc public class TimelineItem: NSObject {

    private var _samples: [LocomotionSample] = []

    internal var _radius: (mean: CLLocationDistance, sd: CLLocationDistance) = (0, 0)

    @objc private(set) public var center: CLLocation?

    private(set) public var itemId: UUID

    /// The LocomotionSamples recorded between the item's `start` and `end` dates.
    public var samples: [LocomotionSample] {
        return _samples
    }

    @objc private(set) public var dateRange: DateInterval?

    /// The timeline item's start date
    @objc public var start: Date? {
        return dateRange?.start
    }

    /// The timeline item's end date
    @objc public var end: Date? {
        return dateRange?.end
    }

    public weak var previousItem: TimelineItem?
    public weak var nextItem: TimelineItem?

    public convenience init(sample: LocomotionSample) {
        self.init(samples: [sample])
    }

    public init(samples: [LocomotionSample]) {
        self.itemId = UUID()
        super.init()
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
    @objc public var isWorthKeeping: Bool {
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
    @objc public var duration: TimeInterval {
        guard let dateRange = dateRange else {
            return 0
        }
        return dateRange.duration
    }

    // ~50% of samples
    public var radius0sd: Double {
        return _radius.mean.clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
    }

    // ~84% of samples
    public var radius1sd: Double {
        return (_radius.mean + _radius.sd).clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
    }

    // ~98% of samples
    public var radius2sd: Double {
        return (_radius.mean + (_radius.sd * 2)).clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
    }

    // ~100% of samples
    public var radius3sd: Double {
        return (_radius.mean + (_radius.sd * 3)).clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
    }

    // MARK: Activity Types

    private var _classifierResults: ClassifierResults?

    /// The `ActivityTypeClassifier` results for the timeline item.
    public var classifierResults: ClassifierResults? {
        if let results = _classifierResults {
            return results
        }

        guard let results = ActivityTypeSetClassifier.classify(self) else {
            return nil
        }

        // don't cache if it's incomplete
        if results.moreComing {
            return results
        }

        _classifierResults = results
        return results
    }

    /// The highest scoring activity type for the timeline's samples.
    public var activityType: ActivityTypeName? {
        return classifierResults?.first?.name
    }

    /// The highest scoring moving (ie not stationary) activity type for the timeline item.
    public var movingActivityType: ActivityTypeName? {
        guard let results = classifierResults else {
            return nil
        }
        for result in results {
            if result.name != .stationary {
                return result.name
            }
        }
        return nil
    }

    private var _modeActivityType: ActivityTypeName?

    /// The most common activity type for the timeline item's samples.
    public var modeActivityType: ActivityTypeName? {
        if let modeType = _modeActivityType {
            return modeType
        }
        let sampleTypes = samples.flatMap { $0.activityType }

        if sampleTypes.isEmpty {
            return nil
        }

        let counted = NSCountedSet(array: sampleTypes)
        let modeType = counted.max { counted.count(for: $0) < counted.count(for: $1) }

        _modeActivityType = modeType as? ActivityTypeName
        return _modeActivityType
    }

    private var _modeMovingActivityType: ActivityTypeName?

    /// The most common moving activity type for the timeline item's samples.
    public var modeMovingActivityType: ActivityTypeName? {
        if let modeType = _modeMovingActivityType {
            return modeType
        }
        let sampleTypes = samples.flatMap { $0.activityType != .stationary ? $0.activityType : nil }

        if sampleTypes.isEmpty {
            return nil
        }

        let counted = NSCountedSet(array: sampleTypes)
        let modeType = counted.max { counted.count(for: $0) < counted.count(for: $1) }

        _modeMovingActivityType = modeType as? ActivityTypeName
        return _modeMovingActivityType
    }

    // MARK: Comparisons and Helpers

    /**
     The time interval between this item and the given item.

     - Note: A negative value indicates overlapping items, and thus the duration of their overlap.
     */
    public func timeIntervalFrom(_ otherItem: TimelineItem) -> TimeInterval? {
        guard let myRange = self.dateRange, let theirRange = otherItem.dateRange else {
            return nil
        }

        if let intersection = myRange.intersection(with: theirRange) {
            return -intersection.duration
        }
        if myRange.end <= theirRange.start {
            return theirRange.start.timeIntervalSince(myRange.end)
        }
        if myRange.start >= theirRange.end {
            return myRange.start.timeIntervalSince(theirRange.end)
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
    public func distance(from: TimelineItem) -> CLLocationDistance? {
        fatalError("Shouldn't be here.")
    }

    public func withinMergeableDistance(from otherItem: TimelineItem) -> Bool {
        if let gap = distance(from: otherItem), gap <= maximumMergeableDistance(from: otherItem) {
            return true
        }
        return false
    }

    // subclasses handle this
    public func maximumMergeableDistance(from: TimelineItem) -> CLLocationDistance {
        fatalError("Shouldn't be here.")
    }

    internal func sanitiseEdges() {
        var lastPreviousChanged: LocomotionSample?
        var lastNextChanged: LocomotionSample?

        while true {
            var previousChanged: LocomotionSample?
            var nextChanged: LocomotionSample?

            if let previousPath = previousItem as? Path {
                previousChanged = cleanseEdge(with: previousPath)
            }

            if let nextPath = nextItem as? Path {
                nextChanged = cleanseEdge(with: nextPath)
            }

            // no changes, so we're done
            if previousChanged == nil && nextChanged == nil {
                break
            }

            // break from an infinite loop
            if previousChanged == lastPreviousChanged && nextChanged == lastNextChanged {
                NotificationCenter.default.post(Notification(name: .debugInfo, object: TimelineManager.highlander,
                                                             userInfo: ["info": "sanitiseEdges: break from infinite loop"]))
                break
            }

            lastPreviousChanged = previousChanged
            lastNextChanged = nextChanged
        }
    }

    // subclasses handle this
    internal func cleanseEdge(with path: Path) -> LocomotionSample? {
        fatalError("Shouldn't be here.")
    }

    internal func samplesChanged() {
        if let start = samples.first?.date, let end = samples.last?.date {
            dateRange = DateInterval(start: start, end: end)
        } else {
            dateRange = nil
        }

        _classifierResults = nil
        _modeMovingActivityType = nil
        _modeActivityType = nil
        
        updateCenter()
        updateRadius()
    }

    private func updateCenter() {
        center = samples.weightedCenter
    }

    private func updateRadius() {
        if let center = center {
            _radius = samples.radiusFrom(center: center)
        } else {
            _radius = (0, 0)
        }
    }
}

extension TimelineItem {

    public override func isEqual(_ object: Any?) -> Bool {
        guard let item = object as? TimelineItem else {
            return false
        }
        return item.itemId == self.itemId
    }

}
