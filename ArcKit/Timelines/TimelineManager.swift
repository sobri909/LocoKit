//
//  TimelineManager.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log

/// Custom notification events that the TimelineManager may send.
public extension NSNotification.Name {
    public static let newTimelineItem = Notification.Name("newTimelineItem")
    public static let updatedTimelineItem = Notification.Name("updatedTimelineItem")
    public static let finalisedTimelineItem = Notification.Name("finalisedTimelineItem")
    public static let mergedTimelineItems = Notification.Name("mergedTimelineItems")
}

@objc public class TimelineManager: NSObject {

    private var recording = false
    private var lastRecorded: Date?

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

    // MARK: Starting and Stopping Recording

    @objc public func startRecording() {
        LocomotionManager.highlander.startRecording()
        recording = true
    }

    @objc public func stopRecording() {
        LocomotionManager.highlander.stopRecording()
        recording = false
    }

    /// The current timeline item.
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
     `nextItem` property (and in turn, that item will be linked back by its `previousItem` property).
     */
    @objc private(set) public var finalisedTimelineItems: [TimelineItem] = []

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

        defer {
            processTimelineItems()
            NotificationCenter.default.post(Notification(name: .updatedTimelineItem, object: self, userInfo: nil))
        }

        // first timeline item?
        if currentItem == nil {
            createTimelineItem(from: sample)
            return
        }

        // can continue the last timeline item?
        if let item = currentItem {
            if item is Path && (sample.movingState == .moving || sample.movingState == .uncertain) {
                item.add(sample)
                return
            }
            if item is Visit && sample.movingState == .stationary {
                item.add(sample)
                return
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

            // the only escape
            guard let previous = workingItem.previousItem else {
                break
            }

            merges.append(Merge(keeper: workingItem, deadman: previous))
            merges.append(Merge(keeper: previous, deadman: workingItem))

            // if previous has a lesser keepness, look at doing a merge against previous-previous
            if previous.keepnessScore < workingItem.keepnessScore {
                if let prevPrev = previous.previousItem, prevPrev.keepnessScore > previous.keepnessScore {
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

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .locomotionSampleUpdated, object: nil, queue: nil) { _ in
            self.sampleUpdated()
        }
    }
}
