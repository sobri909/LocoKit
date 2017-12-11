//
//  TimelineManager.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import CoreLocation
import Reachability

/// Custom notification events that the TimelineManager may send.
public extension NSNotification.Name {
    public static let newTimelineItem = Notification.Name("newTimelineItem")
    public static let updatedTimelineItem = Notification.Name("updatedTimelineItem")
    public static let finalisedTimelineItem = Notification.Name("finalisedTimelineItem")
    public static let mergedTimelineItems = Notification.Name("mergedTimelineItems")
    public static let debugInfo = Notification.Name("debugInfo")
}

@objc public class TimelineManager: NSObject {

    private var recording = false
    private var lastRecorded: Date?

    private let reachability = Reachability()!

    // MARK: The Singleton

    /// The TimelineManager singleton instance, through which all actions should be performed.
    @objc public static let highlander = TimelineManager()

    // MARK: Settings

    /**
     The target number of samples to record per minute.

     - Note: The actual number of samples recorded per minute may be less than this, depending on data availability.
     */
    public var samplesPerMinute: Double = 10

    /**
     The duration of historical timeline items to retain in `finalisedTimelineItems`.

     Once a timeline item is older than this (measured from the item's `end` date) it will be removed from
     `finalisedTimelineItems`.
     */
    public var timelineItemHistoryRetention: TimeInterval = 60 * 60 * 6

    public var separatePathsByActivityType = true

    public var minimumTransportCoverage = 0.10

    public var maxModeShiftSpeed = CLLocationSpeed(kmh: 8)

    // MARK: Starting and Stopping Recording

    @objc public func startRecording() {
        LocomotionManager.highlander.startRecording()
        recording = true
    }

    @objc public func stopRecording() {
        LocomotionManager.highlander.stopRecording()
        recording = false
    }

    // MARK: The Recorded Timeline Items
    
    /**
     The current (most recent) timeline item.

     - Note: This value is equivalent to `activeTimelineItems.last`.
     */
    @objc public var currentItem: TimelineItem? {
        return activeTimelineItems.last
    }

    /**
     The timeline items that are still being considered for modification by the processing engine, in ascending date
     order.

     Once each timeline item is finalised, it is moved to `finalisedTimelineItems`, at which point it will no longer
     be modified by the processing engine.
     */
    @objc private(set) public var activeTimelineItems: [TimelineItem] = []

    /**
     The timeline items that have received their final processing and will no longer be modified, in ascending date
     order.

     - Note: The last item in this array will usually be linked to the first item in `activeTimelineItems` by its
     `nextItem` property. And in turn, that item will be linked back by its `previousItem` property.
     */
    @objc private(set) public var finalisedTimelineItems: [TimelineItem] = []

    // MARK: The Classifiers

    var baseClassifier: ActivityTypeClassifier<ActivityTypesCache>?
    var transportClassifier: ActivityTypeClassifier<ActivityTypesCache>?

    // MARK: Internal Item Processing Stuff

    private func sampleUpdated() {
        guard recording else {
            return
        }

        // don't record too soon
        if let lastRecorded = lastRecorded, lastRecorded.age < 60.0 / samplesPerMinute {
            return
        }

        lastRecorded = Date()

        let sample = LocomotionManager.highlander.locomotionSample()

        if separatePathsByActivityType {
            sample.classifierResults = classify(sample)
        }

        processSample(sample)

        processTimelineItems()

        NotificationCenter.default.post(Notification(name: .updatedTimelineItem, object: self, userInfo: nil))
    }

    private func processSample(_ sample: LocomotionSample) {
        let loco = LocomotionManager.highlander

        // first timeline item?
        if currentItem == nil {
            createTimelineItem(from: sample)
            return
        }

        // can continue the last timeline item?
        if let currentItem = currentItem {
            let previouslyMoving = currentItem is Path
            let currentlyMoving = sample.movingState == .moving || sample.movingState == .uncertain

            // if stationary -> stationary, reuse current
            if !currentlyMoving && !previouslyMoving {

                // if in sleep mode, trim the last sample before adding the new one,
                // to ensure we're only keeping the most recent sample during sleep
                if loco.recordingState != .recording, let lastSample = currentItem.samples.last {

                    // only trim the last if it's old enough to probably be from the previous sleep cycle
                    if sample.date.timeIntervalSince(lastSample.date) > loco.sleepCycleDuration * 0.5 {
                        currentItem.remove(lastSample)
                    }
                }

                currentItem.add(sample)
                return
            }

            // moving -> moving
            if previouslyMoving && currentlyMoving {

                // if activityType hasn't changed, reuse current
                if sample.activityType == currentItem.movingActivityType {
                    currentItem.add(sample)
                    return
                }

                // if edge speeds are above the mode change threshold, reuse current
                if let currentSpeed = currentItem.samples.last?.location?.speed, let sampleSpeed = sample.location?.speed {
                    if currentSpeed > maxModeShiftSpeed && sampleSpeed > maxModeShiftSpeed {
                        currentItem.add(sample)
                        return
                    }
                }
            }
        }

        // switched between path and visit, so let's make a new timeline item
        createTimelineItem(from: sample)
    }

    private func createTimelineItem(from sample: LocomotionSample) {
        let newItem: TimelineItem
        if sample.movingState == .moving || sample.movingState == .uncertain {
            newItem = Path(sample: sample)
        } else {
            newItem = Visit(sample: sample)
        }

        // keep the list linked
        newItem.previousItem = currentItem
        currentItem?.nextItem = newItem

        // new item becomes current
        activeTimelineItems.append(newItem)

        NotificationCenter.default.post(Notification(name: .newTimelineItem, object: self,
                                                     userInfo: ["timelineItem": newItem]))
    }

    private func processTimelineItems() {
        if activeTimelineItems.isEmpty {
            return
        }

        // only process from a keeper current item
        guard let current = currentItem, current.isWorthKeeping else {
            return
        }

        var workingItem = current

        var merges: [Merge] = []

        // collect all possible merges
        while activeTimelineItems.contains(workingItem) {

            // clean up item edges before calculating any merge scores
            workingItem.sanitiseEdges()

            // if the chain is broken, we can't do merges
            guard let previous = workingItem.previousItem else {
                break
            }

            // don't do merges against finalised items
            guard activeTimelineItems.contains(previous) else {
                break
            }

            merges.append(Merge(keeper: workingItem, deadman: previous))
            merges.append(Merge(keeper: previous, deadman: workingItem))

            // if previous has a lesser keepness, look at doing a merge against previous-previous
            if previous.keepnessScore < workingItem.keepnessScore {
                if let prevPrev = previous.previousItem, prevPrev.keepnessScore > previous.keepnessScore,
                    activeTimelineItems.contains(prevPrev)
                {
                    merges.append(Merge(keeper: workingItem, betweener: previous, deadman: prevPrev))
                    merges.append(Merge(keeper: prevPrev, betweener: previous, deadman: workingItem))
                }
            }

            workingItem = previous
        }

        // sort the merges by highest to lowest score
        merges = merges.sorted { $0.score.rawValue > $1.score.rawValue }

        if !merges.isEmpty {
            var descriptions = ""
            for merge in merges {
                descriptions += String(describing: merge) + "\n"
            }
            os_log("Considering:\n%@", type: .debug, descriptions)
        }

        // do the highest scoring valid merge
        if let winningMerge = merges.first, winningMerge.score != .impossible {
            let description = String(describing: winningMerge)
            os_log("Doing:\n%@", type: .debug, description)

            let results = winningMerge.doIt()

            // sweep up the dead bodies
            activeTimelineItems.removeObjects(results.killed)

            NotificationCenter.default.post(Notification(name: .mergedTimelineItems, object: self,
                                                         userInfo: ["merge": description]))

            // recurse until no valid merges left to do
            processTimelineItems()
            return
        }

        // final housekeeping
        trimTheActiveItems()
        trimTheFinalisedItems()

        // make sure sleep mode doesn't happen prematurely
        if let currentVisit = currentItem as? Visit, currentVisit.isWorthKeeping {
            LocomotionManager.highlander.useLowPowerSleepModeWhileStationary = true
        } else {
            LocomotionManager.highlander.useLowPowerSleepModeWhileStationary = false
        }
    }

    private func trimTheActiveItems() {
        var keeperCount = 0
        var itemsToTrim: ArraySlice<TimelineItem>?

        for item in activeTimelineItems.reversed() {
            if item.isWorthKeeping {
                keeperCount += 1
            }
            if keeperCount == 2 {
                itemsToTrim = activeTimelineItems.prefix { $0 != item }
                break
            }
        }

        // move the newly finalised items to their new home
        if let finalised = itemsToTrim, !finalised.isEmpty {
            finalisedTimelineItems.append(contentsOf: finalised)
            activeTimelineItems.removeObjects(Array(finalised))

            for item in finalised {
                NotificationCenter.default.post(Notification(name: .finalisedTimelineItem, object: self,
                                                             userInfo: ["timelineItem": item]))
            }
        }
    }

    private func trimTheFinalisedItems() {
        let itemsToTrim = finalisedTimelineItems.prefix {
            guard let end = $0.end else {
                return true
            }
            return end.age > timelineItemHistoryRetention
        }
        if !itemsToTrim.isEmpty {
            finalisedTimelineItems.removeObjects(Array(itemsToTrim))
            os_log("Released %d historical timeline item(s).", type: .debug, itemsToTrim.count)
        }
    }

    // MARK: Internal Classifier Management

    internal func classify(_ classifiable: ActivityTypeClassifiable) -> ClassifierResults? {

        // attempt to keep the classifiers relevant / fresh
        if let coordinate = classifiable.location?.coordinate {
            updateTheBaseClassifier(for: coordinate)
            updateTheTransportClassifier(for: coordinate)
        }

        // if possible, get the base type results
        guard let classifier = baseClassifier else {
            return nil
        }
        let results = classifier.classify(classifiable)

        // don't need to go further if transport didn't win the base round
        guard results.first?.name == .transport else {
            return results
        }

        // don't include specific transport types if classifier has less than required coverage
        guard let coverageScore = transportClassifier?.coverageScore, coverageScore > minimumTransportCoverage else {
            return results
        }

        // attempt to get the transport type results
        guard let transportClassifier = transportClassifier else {
            return results
        }
        let transportResults = transportClassifier.classify(classifiable)

        // combine and return the results
        return (results - ActivityTypeName.transport) + transportResults
    }

    private func updateTheBaseClassifier(for coordinate: CLLocationCoordinate2D) {

        // don't try to fetch classifiers without a network connection
        guard reachability.connection != .none else {
            return
        }

        // have a classifier already, and it's still valid?
        if let classifier = baseClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        // attempt to get an updated classifier
        if let replacement = ActivityTypeClassifier<ActivityTypesCache>(requestedTypes: ActivityTypeName.baseTypes,
                                                                        coordinate: coordinate) {
            baseClassifier = replacement
        }
    }

    private func updateTheTransportClassifier(for coordinate: CLLocationCoordinate2D) {

        // don't try to fetch classifiers without a network connection
        guard reachability.connection != .none else {
            return
        }

        // have a classifier already, and it's still valid?
        if let classifier = transportClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        // attempt to get an updated classifier
        if let replacement = ActivityTypeClassifier<ActivityTypesCache>(requestedTypes: ActivityTypeName.transportTypes,
                                                                        coordinate: coordinate) {
            transportClassifier = replacement
        }
    }

    // MARK: Only Highlanders Here

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .locomotionSampleUpdated, object: nil, queue: nil) { _ in
            self.sampleUpdated()
        }

        // want to be able to store a sample to mark the start of most recent sleep cycle
        NotificationCenter.default.addObserver(forName: .willStartSleepMode, object: nil, queue: nil) { _ in
            self.sampleUpdated()
        }
    }
}
