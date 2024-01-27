//
//  TimelineRecorder.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/04/18.
//

import CoreLocation
import Combine

public extension NSNotification.Name {
    static let newTimelineItem = Notification.Name("newTimelineItem")
    static let updatedTimelineItem = Notification.Name("updatedTimelineItem")
    static let currentItemChanged = Notification.Name("currentItemChanged")
    static let currentItemTitleChanged = Notification.Name("currentItemTitleChanged")
}

public class TimelineRecorder: ObservableObject {

    // MARK: - Settings

    /**
     The maximum number of samples to record per minute.

     - Note: The actual number of samples recorded per minute may be less than this, depending on data availability.
     */
    public var samplesPerMinute: Double = 10

    private(set) public var store: TimelineStore
    
    public lazy var classifier = {
        return ActivityClassifier(store: store)
    }()

    private(set) public var lastClassifierResults: ClassifierResults? {
        didSet {
            Task { @MainActor in
                objectWillChange.send()
            }
        }
    }

    // MARK: - Recorder creation

    public init(store: TimelineStore) {
        self.store = store
        store.recorder = self

        let loco = LocomotionManager.highlander

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
            if loco.recordingState.isCurrentRecorder {
                store.connectToDatabase()
            }
        }
        notes.addObserver(forName: .tookOverRecording, object: nil, queue: nil) { [weak self] _ in
            self?.updateCurrentItem()
            loco.resetLocationFilter() // reset the Kalmans
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
        return classifier.canClassify(coordinate) == true
    }

    // MARK: - Starting and stopping recording

    public func startRecording() {
        if isRecording { return }
        store.connectToDatabase()
        if LocomotionManager.highlander.appGroup?.currentRecorder == nil {
            addDataGapItem()
        }
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
            if let item = _currentItem, !item.invalidated { return item }
            _currentItem = store.mostRecentItem
            return _currentItem
        }
        set(newValue) {
            _currentItem = newValue
            onMain { self.objectWillChange.send() }
        }
    }

    public func updateCurrentItem() {
        let beforeId = _currentItem?.itemId
        _currentItem = store.mostRecentItem
        onMain { self.objectWillChange.send() }
        if beforeId != _currentItem?.itemId {
            onMain { NotificationCenter.default.post(Notification(name: .currentItemChanged)) }
        }
    }

    public var currentVisit: Visit? { return currentItem as? Visit }

    private var currentItemTitle: String?

    private var lastRecorded: Date?
    
    private func recordSample() {
        guard isRecording else { return }

        // don't record too soon
        if let lastRecorded = lastRecorded, lastRecorded.age < 60.0 / samplesPerMinute { return }

        lastRecorded = Date()

        let sample = store.createSample(from: ActivityBrain.highlander.presentSample)
        Task(priority: .background) { sample.updateRTree() }

        // classify the sample, if a classifier has been provided
        if classifier.canClassify(sample.location?.coordinate) {
            sample.classifierResults = classifier.classify(sample)
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

    public func process(_ sample: PersistentSample) {
        defer {
            if currentItem?.title != currentItemTitle {
                NotificationCenter.default.post(Notification(name: .currentItemTitleChanged))
            }
            currentItemTitle = currentItem?.title
        }

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

        // if in sleep mode, only retain the last X sleep / stationary samples
        if RecordingState.sleepStates.contains(sample.recordingState), let currentVisit = currentVisit {
            TimelineProcessor.pruneSamples(for: currentVisit)
        }

        // reclassify the sample, now that there'll be a sinceVisitStart value
        if classifier.canClassify(sample.location?.coordinate) {
            sample.classifierResults = classifier.classify(sample)
            lastClassifierResults = sample.classifierResults
        }
    }

    private func updateSleepModeAcceptability() {
        let loco = LocomotionManager.highlander

        // don't muck about with recording state if it's been explicitly turned off
        if loco.recordingState == .off { return }

        // don't be fiddling when someone else is responsible for recording
        if loco.recordingState == .standby { return }

        // sleep mode requires currentItem to be a keeper visit
        store.connectToDatabase()
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
            NotificationCenter.default.post(Notification(name: .currentItemChanged))
        }
    }
    
    // MARK: - ObservableObject

    public let objectWillChange = ObservableObjectPublisher()

}
