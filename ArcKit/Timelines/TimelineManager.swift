//
//  TimelineManagerProtocol.swift
//  ArcKit
//
//  Created by Matt Greenfield on 18/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import CoreLocation

public protocol TimelineManager: class {

    associatedtype ItemFactory: TimelineItemFactory

    static var highlander: Self { get }

    var samplesPerMinute: Double { get }
    var timelineItemHistoryRetention: TimeInterval { get }
    var activityTypeClassifySamples: Bool { get }
    var minimumTransportCoverage: Double { get }

    var currentItem: TimelineItem? { get }

    var activeTimelineItems: [TimelineItem] { get }
    var finalisedTimelineItems: [TimelineItem] { get }

    var recording: Bool { get set }
    var lastRecorded: Date? { get set }

    func startRecording()
    func stopRecording()

    func add(_ timelineItem: TimelineItem)
    func remove(_ timelineItem: TimelineItem)
    func remove(_ timelineItems: [TimelineItem])
    func finalise(_ timelineItems: [TimelineItem])

    func sampleUpdated()
    func processSample(_ sample: LocomotionSample)
    func processTimelineItems()

    var baseClassifier: ActivityTypeClassifier<ActivityTypesCache>? { get }
    var transportClassifier: ActivityTypeClassifier<ActivityTypesCache>? { get }
    func classify(_ classifiable: ActivityTypeClassifiable) -> ClassifierResults?

}

extension TimelineManager {

    public func startRecording() {
        recording = true
    }

    public func stopRecording() {
        recording = false
    }

    public var currentItem: TimelineItem? {
        return activeTimelineItems.last
    }

    public func remove(_ timelineItem: TimelineItem) {
        remove([timelineItem])
    }

    public func sampleUpdated() {
        guard recording else {
            return
        }

        // don't record too soon
        if let lastRecorded = lastRecorded, lastRecorded.age < 60.0 / samplesPerMinute {
            return
        }

        lastRecorded = Date()

        let sample = LocomotionManager.highlander.locomotionSample()

        if activityTypeClassifySamples {
            sample.classifierResults = classify(sample)
        }

        processSample(sample)

        processTimelineItems()

        NotificationCenter.default.post(Notification(name: .updatedTimelineItem, object: self, userInfo: nil))
    }

    public func processSample(_ sample: LocomotionSample) {
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
                    if currentSpeed > Path.maximumModeShiftSpeed && sampleSpeed > Path.maximumModeShiftSpeed {
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
        let newItem: TimelineItem = sample.movingState == .moving || sample.movingState == .uncertain
            ? ItemFactory.highlander.createPath(from: sample)
            : ItemFactory.highlander.createVisit(from: sample)

        // keep the list linked
        newItem.previousItem = currentItem
        currentItem?.nextItem = newItem

        // new item becomes current
        add(newItem)

        NotificationCenter.default.post(Notification(name: .newTimelineItem, object: self,
                                                     userInfo: ["timelineItem": newItem]))
    }

    public func processTimelineItems() {
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
            remove(results.killed)

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
        if let finalised = itemsToTrim {
            finalise(Array(finalised))
        }
    }

    private func trimTheFinalisedItems() {
        let itemsToTrim = finalisedTimelineItems.prefix {
            guard let end = $0.endDate else {
                return true
            }
            return end.age > timelineItemHistoryRetention
        }
        if !itemsToTrim.isEmpty {
            remove(Array(itemsToTrim))
            os_log("Released %d historical timeline item(s).", type: .debug, itemsToTrim.count)
        }
    }
}

