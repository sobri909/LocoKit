//
//  ItemSegment.swift
//  ArcKit
//
//  Created by Matt Greenfield on 24/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public class ItemSegment: Equatable {

    public weak var timelineItem: TimelineItem?

    private(set) public var samples: [LocomotionSample] = []

    // MARK: Initialisers

    public init(samples: [LocomotionSample], timelineItem: TimelineItem? = nil) {
        self.timelineItem = timelineItem
        self.add(samples)
    }

    public init(startDate: Date, activityType: ActivityTypeName, recordingState: RecordingState) {
        self.manualStartDate = startDate
        self.manualActivityType = activityType
        self.manualRecordingState = recordingState
    }

    /**
     A final sample, to mark the end of this segment outside of the `samples` array.

     Typically this is shared with (and owned by) the following item segment, acting as a bridge to allow this segment
     to end at the point where the next begins, without the shared sample being incorrectly subjected to modifications
     made to this segment (eg activity type changes).
     */
    public var endSample: LocomotionSample? { didSet { samplesChanged() } }

    private var manualStartDate: Date?
    private var manualEndDate: Date?
    private var manualRecordingState: RecordingState?
    private var manualActivityType: ActivityTypeName?

    public var startDate: Date? { return manualStartDate ?? samples.first?.date }
    public var endDate: Date? {
        get { return manualEndDate ?? endSample?.date ?? samples.last?.date }
        set(newValue) {
            manualEndDate = newValue
            samplesChanged()
        }
    }
    public var recordingState: RecordingState? { return manualRecordingState ?? samples.first?.recordingState }
    public var activityType: ActivityTypeName? { return manualActivityType ?? samples.first?.activityType }
    public var duration: TimeInterval { return dateRange?.duration ?? 0 }

    private var _dateRange: DateInterval?
    public var dateRange: DateInterval? {
        if let cached = _dateRange { return cached }
        if let start = startDate, let end = endDate { _dateRange = DateInterval(start: start, end: end) }
        return _dateRange
    }

    private var _center: CLLocation?
    public var center: CLLocation? {
        if let center = _center { return center }
        _center = samples.weightedCenter
        return _center
    }

    private var _radius: Radius?
    public var radius: Radius {
        if let radius = _radius { return radius }
        if let center = center { _radius = samples.radius(from: center) }
        else { _radius = Radius.zero }
        return _radius!
    }

    private var _distance: CLLocationDistance?
    public var distance: CLLocationDistance {
        if let distance = _distance { return distance }
        let distance = samples.distance
        _distance = distance
        return distance
    }

    // MARK: Activity Types

    private var _classifierResults: ClassifierResults? = nil
    public var classifierResults: ClassifierResults? {
        if let results = _classifierResults { return results }
        guard let results = timelineItem?.classifier?.classify(self, filtered: true) else { return nil }
        if results.moreComing { return results }
        _classifierResults = results
        return results
    }

    private var _unfilteredClassifierResults: ClassifierResults? = nil
    public var unfilteredClassifierResults: ClassifierResults? {
        if let results = _unfilteredClassifierResults { return results }
        guard let results = timelineItem?.classifier?.classify(self, filtered: false) else { return nil }
        if results.moreComing { return results }
        _unfilteredClassifierResults = results
        return results
    }

    // MARK: Modifying the item segment

    func canAdd(_ sample: LocomotionSample) -> Bool {
        // exact match
        if sample.recordingState == recordingState && sample.activityType == activityType { return true }

        guard let recordingState = self.recordingState else { return false }

        // off samples go together, regardless of activity type
        if recordingState == .off && sample.recordingState == .off { return true }

        // sleep samples go together, regardless of activity type
        let sleepTypes: [RecordingState] = [.wakeup, .sleeping]
        if sleepTypes.contains(recordingState) && sleepTypes.contains(sample.recordingState) { return true }

        return false
    }

    public func add(_ sample: LocomotionSample) {
        add([sample])
    }

    public func add(_ samples: [LocomotionSample]) {
        self.samples = Set(self.samples + samples).sorted { $0.date < $1.date }
        samplesChanged()
    }

    public func remove(_ sample: LocomotionSample) {
        remove([sample])
    }

    public func remove(_ samples: [LocomotionSample]) {
        self.samples.removeObjects(samples)
        samplesChanged()
    }

    public func samplesChanged() {
        _dateRange = nil
        _center = nil
        _radius = nil
        _distance = nil
        _classifierResults = nil
        _unfilteredClassifierResults = nil
    }

    // MARK: Equatable

    public static func ==(lhs: ItemSegment, rhs: ItemSegment) -> Bool {
        return lhs.dateRange == rhs.dateRange && lhs.samples.count == rhs.samples.count
    }
}

