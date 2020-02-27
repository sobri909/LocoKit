//
//  TimelineRecorder.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/04/18.
//

import LocoKitCore
import CoreLocation

public extension NSNotification.Name {
    static let newTimelineItem = Notification.Name("newTimelineItem")
    static let updatedTimelineItem = Notification.Name("updatedTimelineItem")
}

public class TimelineRecorder {

    // MARK: - Settings

    /**
     The maximum number of samples to record per minute.

     - Note: The actual number of samples recorded per minute may be less than this, depending on data availability.
     */
    public var samplesPerMinute: Double = 10

    private(set) public var store: TimelineStore
    private(set) public var classifier: MLCompositeClassifier?
    private(set) public var lastClassifierResults: ClassifierResults?

    // MARK: - Recorder creation

    public init(store: TimelineStore, classifier: MLCompositeClassifier? = nil) {
        self.store = store
        store.recorder = self
        self.classifier = classifier

        let notes = NotificationCenter.default
        notes.addObserver(forName: .locomotionSampleUpdated, object: nil, queue: nil) { [weak self] _ in
            self?.recordSample()
        }
        notes.addObserver(forName: .wentFromRecordingToSleepMode, object: nil, queue: nil) { [weak self] _ in
            if let currentItem = self?.currentItem {
                TimelineProcessor.process(from: currentItem)
            }
        }
        notes.addObserver(forName: .willStartSleepMode, object: nil, queue: nil) { [weak self] _ in
            self?.recordSample()
        }
        notes.addObserver(forName: .recordingStateChanged, object: nil, queue: nil) { [weak self] _ in
            self?.updateSleepModeAcceptability()
        }

        // keep currentItem sane after merges
        notes.addObserver(forName: .mergedTimelineItems, object: nil, queue: nil) { [weak self] note in
            guard let results = note.userInfo?["results"] as? MergeResult else { return }
            guard let current = self?.currentItem else { return }
            if results.killed.contains(current) {
                self?.currentItem = results.kept
            }
        }
    }

    // convenience access to an often used optional bool
    public func canClassify(_ coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        return classifier?.canClassify(coordinate) == true
    }

    // MARK: - Starting and stopping recording

    public func startRecording() {
        if isRecording { return }
        addDataGapItem()
        LocomotionManager.highlander.startRecording()
    }

    public func stopRecording() {
        LocomotionManager.highlander.stopRecording()
    }

    public var isRecording: Bool {
        return LocomotionManager.highlander.recordingState != .off
    }

    // MARK: - Startup

    private func addDataGapItem() {
        guard let lastItem = currentItem, let lastEndDate = lastItem.endDate else { return }

        // don't add a data gap after a data gap
        if lastItem.isDataGap { return }

        // is the gap too short to be worth filling?
        if lastEndDate.age < LocomotionManager.highlander.sleepCycleDuration { return }

        // the edge samples
        let startSample = store.createSample(date: lastEndDate, recordingState: .off)
        let endSample = store.createSample(date: Date(), recordingState: .off)

        // the gap item
        let gapItem = self.store.createPath(from: startSample)
        gapItem.previousItem = lastItem
        gapItem.add(endSample)

        // need to explicitly save because not in a process() block
        store.save()

        // make it current
        currentItem = gapItem
    }

    // MARK: - The recording cycle

    private var _currentItem: TimelineItem?
    public private(set) var currentItem: TimelineItem? {
        get {
            if let item = _currentItem { return item }
            _currentItem = store.mostRecentItem
            return _currentItem
        }
        set(newValue) {
            _currentItem = newValue
        }
    }

    public func updateCurrentItem() {
        _currentItem = store.mostRecentItem
    }

    public var currentVisit: Visit? { return currentItem as? Visit }

    private var lastRecorded: Date?
    
    private func recordSample() {
        guard isRecording else { return }

        // don't record too soon
        if let lastRecorded = lastRecorded, lastRecorded.age < 60.0 / samplesPerMinute { return }

        lastRecorded = Date()

        let sample = store.createSample(from: ActivityBrain.highlander.presentSample)

        // classify the sample, if a classifier has been provided
        if let classifier = classifier, classifier.canClassify(sample.location?.coordinate) {
            sample.classifierResults = classifier.classify(sample, previousResults: lastClassifierResults)
            lastClassifierResults = sample.classifierResults
        }

        // make sure sleep mode doesn't happen prematurely
        updateSleepModeAcceptability()

        store.process {
            self.process(sample)
            self.updateSleepModeAcceptability()
        }

        // recreate the location manager on nolo, to work around iOS 13.3 bug
        if sample.isNolo {
            LocomotionManager.highlander.recreateTheLocationManager()
        }
    }

    private func process(_ sample: PersistentSample) {

        /** first timeline item **/
        guard let currentItem = currentItem else {
            createTimelineItem(from: sample)
            return
        }

        /** datagap -> anything **/
        if currentItem.isDataGap {
            createTimelineItem(from: sample)
            return
        }

        let previouslyMoving = currentItem is Path
        let currentlyMoving = sample.movingState != .stationary

        /** stationary -> moving || moving -> stationary **/
        if currentlyMoving != previouslyMoving {
            createTimelineItem(from: sample)
            return
        }

        /** moving -> moving **/
        if previouslyMoving && currentlyMoving {

            // if activityType hasn't changed, reuse current
            if sample.activityType == currentItem.movingActivityType {
                currentItem.add(sample)
                return
            }

            // if edge speeds are above the mode change threshold, reuse current
            if let currentSpeed = currentItem.samples.last?.location?.speed, let sampleSpeed = sample.location?.speed {
                if currentSpeed > Path.maximumModeShiftSpeed && sampleSpeed > Path.maximumModeShiftSpeed {
                    currentItem.add(sample)
                    return
                }
            }

            // couldn't reuse current path
            createTimelineItem(from: sample)
            return
        }

        /** stationary -> stationary **/

        currentItem.add(sample)

        // if in sleep mode, only retain the last X sleep mode samples
        if RecordingState.sleepStates.contains(sample.recordingState) {
            pruneSleepModeSamples(for: currentItem)
        }
    }

    private func pruneSleepModeSamples(for item: TimelineItem) {
        guard let endDate = item.endDate else { return }

        // collect the contiguous sleep samples from the end
        let edgeSleepSamples = item.samples.reversed().prefix {
            RecordingState.sleepStates.contains($0.recordingState)
        }

        // keep most recent 20 minutes of sleep samples
        let keeperBoundary: TimeInterval = .oneMinute * 20
        let durationBetween: TimeInterval = .oneMinute * 5

        var lastKept: PersistentSample? = edgeSleepSamples.last
        var samplesToKill: [PersistentSample] = []

        for sample in edgeSleepSamples.reversed() {
            // sample younger than the time window? then we done
            if endDate.timeIntervalSince(sample.date) < keeperBoundary { break }

            // always keep the newest sleep sample
            if sample == edgeSleepSamples.first { break }

            // always keep the oldest sleep sample
            if sample == edgeSleepSamples.last { continue }

            // sample is too close to the previously kept one?
            if let lastKept = lastKept, sample.date.timeIntervalSince(lastKept.date) < durationBetween {
                samplesToKill.append(sample)
                continue
            }

            // must've kept it
            lastKept = sample
        }

        samplesToKill.forEach { $0.delete() }
    }

    private func updateSleepModeAcceptability() {
        let loco = LocomotionManager.highlander

        // don't muck about with recording state if it's been explicitly turned off
        if loco.recordingState == .off { return }

        // sleep mode requires currentItem to be a keeper visit
        guard let currentVisit = currentVisit, currentVisit.isWorthKeeping else {
            loco.useLowPowerSleepModeWhileStationary = false

            // not recording, but should be?
            if loco.recordingState != .recording { loco.startRecording() }

            return
        }

        // permit sleep mode
        loco.useLowPowerSleepModeWhileStationary = true
    }

    // MARK: - Timeline item creation

    private func createTimelineItem(from sample: PersistentSample) {
        let newItem: TimelineItem = sample.movingState == .stationary
            ? store.createVisit(from: sample)
            : store.createPath(from: sample)

        // keep the list linked
        newItem.previousItem = currentItem

        // new item becomes current
        currentItem = newItem

        onMain {
            let note = Notification(name: .newTimelineItem, object: self, userInfo: ["timelineItem": newItem])
            NotificationCenter.default.post(note)
        }
    }

}
