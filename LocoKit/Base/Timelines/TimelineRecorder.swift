//
//  TimelineRecorder.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/04/18.
//

import LocoKitCore
import CoreLocation

public extension NSNotification.Name {
    public static let newTimelineItem = Notification.Name("newTimelineItem")
    public static let updatedTimelineItem = Notification.Name("updatedTimelineItem")
}

public class TimelineRecorder {

    // MARK: - Settings

    /**
     The maximum number of samples to record per minute.

     - Note: The actual number of samples recorded per minute may be less than this, depending on data availability.
     */
    public var samplesPerMinute: Double = 10

    // MARK: - Recorder creation

    private(set) public var store: TimelineStore
    private(set) public var classifier: MLCompositeClassifier?

    // convenience access to an often used optional bool
    public func canClassify(_ coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        return classifier?.canClassify(coordinate) == true
    }

    public init(store: TimelineStore, classifier: MLCompositeClassifier? = nil) {
        self.store = store
        store.recorder = self
        self.classifier = classifier

        let notes = NotificationCenter.default
        notes.addObserver(forName: .locomotionSampleUpdated, object: nil, queue: nil) { [weak self] _ in
            self?.recordSample()
        }
        notes.addObserver(forName: .startedSleepMode, object: nil, queue: nil) { [weak self] _ in
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
        store.process {
            guard let lastItem = self.currentItem, let lastEndDate = lastItem.endDate else { return }

            // don't add a data gap after a data gap
            if lastItem.isDataGap { return }

            // is the gap too short to be worth filling?
            if lastEndDate.age < LocomotionManager.highlander.sleepCycleDuration { return }

            // the edge samples
            let startSample = PersistentSample(date: lastEndDate, recordingState: .off, in: self.store)
            let endSample = PersistentSample(date: Date(), recordingState: .off, in: self.store)

            // the gap item
            let gapItem = self.store.createPath(from: startSample)
            gapItem.previousItem = lastItem
            gapItem.add(endSample)

            // make it current
            self.currentItem = gapItem
        }
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
            sample.classifierResults = classifier.classify(sample, filtered: true)
            sample.unfilteredClassifierResults = classifier.classify(sample, filtered: false)
        }

        // make sure sleep mode doesn't happen prematurely
        updateSleepModeAcceptability()

        store.process {
            self.process(sample)
            self.updateSleepModeAcceptability()
        }
    }

    private func process(_ sample: LocomotionSample) {

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

        // if in sleep mode, only retain the last 10 sleep mode samples
        if RecordingState.sleepStates.contains(sample.recordingState) {

            // collect the contiguous sleep samples from the end
            let edgeSleepSamples = currentItem.samples.reversed().prefix {
                RecordingState.sleepStates.contains($0.recordingState)
            }

            var keptCount = 0
            var samplesToKill: [LocomotionSample] = []
            for sample in edgeSleepSamples {

                // always keep the oldest sleep sample
                if sample == edgeSleepSamples.last {
                    break
                }

                // keep 15 most recent samples, plus one sample per 15 mins
                let allowedCount: Double = 15 + (sample.date.age / (60 * 15))

                // sample would go over the limit?
                if keptCount + 1 > Int(allowedCount) {
                    samplesToKill.append(sample)
                    continue
                }

                keptCount += 1
            }

            samplesToKill.forEach { $0.delete() }
        }

        currentItem.add(sample)
    }

    private func updateSleepModeAcceptability() {
        let loco = LocomotionManager.highlander

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

    private func createTimelineItem(from sample: LocomotionSample) {
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
