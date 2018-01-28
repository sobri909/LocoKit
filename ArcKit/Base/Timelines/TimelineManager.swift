//
//  TimelineManager.swift
//  ArcKit
//
//  Created by Matt Greenfield on 18/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import ArcKitCore
import CoreLocation

/// Custom notification events that the TimelineManager may send.
public extension NSNotification.Name {
    public static let newTimelineItem = Notification.Name("newTimelineItem")
    public static let updatedTimelineItem = Notification.Name("updatedTimelineItem")
    public static let finalisedTimelineItem = Notification.Name("finalisedTimelineItem")
    public static let mergedTimelineItems = Notification.Name("mergedTimelineItems")
    public static let debugInfo = Notification.Name("debugInfo")
}

open class TimelineManager {

    private lazy var _store = TimelineStore()
    open var store: TimelineStore { return _store }
    
    private(set) open var classifier = TimelineClassifier.highlander
    public let processingQueue = DispatchQueue(label: "TimelineProcessing")

    public init() {
        self.store.manager = self
        
        let notes = NotificationCenter.default
        notes.addObserver(forName: .locomotionSampleUpdated, object: nil, queue: nil) { _ in self.sampleUpdated() }
        notes.addObserver(forName: .willStartSleepMode, object: nil, queue: nil) { _ in self.sampleUpdated() }
    }

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

    public var activityTypeClassifySamples = true

    // MARK: The Recorded Timeline Items

    /**
     The current (most recent) timeline item.

     - Note: This value is equivalent to `activeTimelineItems.last`.
     */
    public var currentItem: TimelineItem? { return activeItems.last?.currentInstance }

    /**
     The timeline items that are still being considered for modification by the processing engine, in ascending date
     order.

     Once each timeline item is finalised, it is moved to `finalisedTimelineItems`, at which point it will no longer
     be modified by the processing engine.
     */
    private(set) public var activeItems: [TimelineItem] = []

    /**
     The timeline items that have received their final processing and will no longer be modified, in ascending date
     order.

     - Note: The last item in this array will usually be linked to the first item in `activeTimelineItems` by its
     `nextItem` property. And in turn, that item will be linked back by its `previousItem` property.
     */
    private(set) public var finalisedItems: [TimelineItem] = []

    public func startRecording() { recording = true }
    public func stopRecording() { recording = false }

    public var recording: Bool = false {
        willSet(start) {
            if start {
                LocomotionManager.highlander.startRecording()
            } else {
                LocomotionManager.highlander.stopRecording()
            }
        }
    }

    private(set) public var lastRecorded: Date?

    public func add(_ timelineItem: TimelineItem) {
        if activeItems.isEmpty { activeItems.append(timelineItem); return }
        guard let prevIndex = activeItems.index(where: { $0 == timelineItem.previousItem }) else { return }
        activeItems.insert(timelineItem, at: prevIndex + 1)
    }

    public func remove(_ timelineItem: TimelineItem) { remove([timelineItem]) }

    public func remove(_ timelineItems: [TimelineItem]) {
        activeItems.removeObjects(timelineItems)
        finalisedItems.removeObjects(timelineItems)
    }

    public func finalise(_ timelineItems: [TimelineItem]) {
        if timelineItems.isEmpty { return }
        activeItems.removeObjects(timelineItems)
        finalisedItems.append(contentsOf: timelineItems)
        for item in timelineItems {
            let note = Notification(name: .finalisedTimelineItem, object: self, userInfo: ["timelineItem": item])
            NotificationCenter.default.post(note)
        }
    }

    public func sampleUpdated() {
        guard recording else { return }

        // don't record too soon
        if let lastRecorded = lastRecorded, lastRecorded.age < 60.0 / samplesPerMinute { return }

        lastRecorded = Date()

        let sample = store.createSample(from: ActivityBrain.highlander.presentSample)

        if activityTypeClassifySamples {
            sample.classifierResults = classifier.classify(sample, filtered: true)
            sample.unfilteredClassifierResults = classifier.classify(sample, filtered: false)
        }

        processingQueue.async {
            self.processSample(sample)
            self.processTimelineItems()
            onMain {
                NotificationCenter.default.post(Notification(name: .updatedTimelineItem, object: self, userInfo: nil))
            }
        }
    }

    public func processSample(_ sample: LocomotionSample) {
        let loco = LocomotionManager.highlander

        // first timeline item?
        guard let currentItem = currentItem else {
            createTimelineItem(from: sample)
            return
        }

        let previouslyMoving = currentItem is Path
        let currentlyMoving = sample.movingState == .moving || sample.movingState == .uncertain

        // stationary -> stationary
        if !currentlyMoving && !previouslyMoving {

            // if in sleep mode, only retain the last 10 sleep mode samples
            if loco.recordingState != .recording {
                let sleepSamples = currentItem.samples.suffix(10).filter { $0.recordingState != .recording }
                if sleepSamples.count == 10, let oldestSleep = sleepSamples.first {
                    currentItem.remove(oldestSleep)
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

        // switched between stationary and moving, so let's make a new timeline item
        createTimelineItem(from: sample)
    }

    private func createTimelineItem(from sample: LocomotionSample) {
        let newItem: TimelineItem = sample.movingState == .stationary
            ? store.createVisit(from: sample)
            : store.createPath(from: sample)

        // keep the list linked
        newItem.previousItem = currentItem

        // new item becomes current
        add(newItem)

        onMain {
            NotificationCenter.default.post(Notification(name: .newTimelineItem, object: self,
                                                         userInfo: ["timelineItem": newItem]))
        }
    }

    public func processTimelineItems() {
        if activeItems.isEmpty { return }

        // only process from a keeper current item
        guard let current = currentItem, current.isWorthKeeping else { return }

        var workingItem = current

        var merges: [Merge] = []

        // collect all possible merges for active items
        while activeItems.contains(workingItem) {

            // clean up item edges before calculating any merge scores
            workingItem.sanitiseEdges()

            // if the chain is broken, we can't do merges
            guard let previous = workingItem.previousItem else { break }

            // don't do merges against finalised items
            guard activeItems.contains(previous) else { break }

            merges.append(Merge(keeper: workingItem, deadman: previous))
            merges.append(Merge(keeper: previous, deadman: workingItem))

            // if previous has a lesser keepness, look at doing a merge against previous-previous
            if previous.keepnessScore < workingItem.keepnessScore {
                if let prevPrev = previous.previousItem, prevPrev.keepnessScore > previous.keepnessScore,
                    activeItems.contains(prevPrev)
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
            for merge in merges { descriptions += String(describing: merge) + "\n" }
            os_log("Considering:\n%@", type: .debug, descriptions)
        }

        // do the highest scoring valid merge
        if let winningMerge = merges.first, winningMerge.score != .impossible {
            let description = String(describing: winningMerge)
            os_log("Doing:\n%@", type: .debug, description)

            let results = winningMerge.doIt()

            // sweep up the dead bodies
            remove(results.killed)

            onMain {
                NotificationCenter.default.post(Notification(name: .mergedTimelineItems, object: self,
                                                             userInfo: ["merge": description]))
            }

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

        for item in activeItems.reversed() {
            if item.isWorthKeeping { keeperCount += 1 }
            if keeperCount == 2 {
                itemsToTrim = activeItems.prefix { $0 != item }
                break
            }
        }

        // move the newly finalised items to their new home
        if let finalised = itemsToTrim { finalise(Array(finalised)) }
    }

    private func trimTheFinalisedItems() {
        let itemsToTrim = finalisedItems.prefix {
            guard let end = $0.endDate else { return true }
            return end.age > timelineItemHistoryRetention
        }
        if !itemsToTrim.isEmpty {
            remove(Array(itemsToTrim))
            os_log("Released %d historical timeline item(s).", type: .debug, itemsToTrim.count)
        }
    }

    /// Processing timeline items from an arbitrary point in the timeline.
    public func processTimelineItems(from fromItem: TimelineItem) {
        processingQueue.async {
            guard let workingItem = fromItem.currentInstance else { os_log("WORKINGITEM NOT AVAILABLE"); return }

            if workingItem.deleted { fatalError("CAN'T PROCESS A DELETED ITEM") }

            var merges: [Merge] = []

            // clean up starting point's edges before calculating merge scores
            workingItem.sanitiseEdges()

            // add in the merges for one step forward
            if let next = workingItem.nextItem, !next.isCurrentItem || next.isWorthKeeping {
                merges.append(Merge(keeper: workingItem, deadman: next))
                merges.append(Merge(keeper: next, deadman: workingItem))

                // clean up edges
                next.sanitiseEdges()

                // if next has a lesser keepness, look at doing a merge against next-next
                if next.keepnessScore < workingItem.keepnessScore {
                    if let nextNext = next.nextItem, nextNext.keepnessScore > next.keepnessScore {
                        merges.append(Merge(keeper: workingItem, betweener: next, deadman: nextNext))
                        merges.append(Merge(keeper: nextNext, betweener: next, deadman: workingItem))
                    }
                }
            }

            // add in the merges for one step backward
            if let previous = workingItem.previousItem {
                merges.append(Merge(keeper: workingItem, deadman: previous))
                merges.append(Merge(keeper: previous, deadman: workingItem))

                // clean up edges
                previous.sanitiseEdges()

                // if previous has a lesser keepness, look at doing a merge against previous-previous
                if previous.keepnessScore < workingItem.keepnessScore {
                    if let prevPrev = previous.previousItem, prevPrev.keepnessScore > previous.keepnessScore {
                        merges.append(Merge(keeper: workingItem, betweener: previous, deadman: prevPrev))
                        merges.append(Merge(keeper: prevPrev, betweener: previous, deadman: workingItem))
                    }
                }
            }

            // if keepness scores allow, add in a bridge merge over top of working item
            if let previous = workingItem.previousItem, let next = workingItem.nextItem,
                previous.keepnessScore > workingItem.keepnessScore && next.keepnessScore > workingItem.keepnessScore
            {
                merges.append(Merge(keeper: previous, betweener: workingItem, deadman: next))
                merges.append(Merge(keeper: next, betweener: workingItem, deadman: previous))
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
                self.remove(results.killed)

                onMain {
                    NotificationCenter.default.post(Notification(name: .mergedTimelineItems, object: self,
                                                                 userInfo: ["merge": description]))
                }

                // recurse until no valid merges left to do
                self.processTimelineItems(from: results.kept)
            }
        }
    }

    /// Attempt to safely delete a timeline item by merging it into a neighbouring item.
    public func delete(_ deadman: TimelineItem) {
        processingQueue.async {
            var merges: [Merge] = []

            // merge next and previous
            if let next = deadman.nextItem, let previous = deadman.previousItem {
                merges.append(Merge(keeper: next, betweener: deadman, deadman: previous))
                merges.append(Merge(keeper: previous, betweener: deadman, deadman: next))
            }

            // merge into previous
            if let previous = deadman.previousItem {
                merges.append(Merge(keeper: previous, deadman: deadman))
            }

            // merge into next
            if let next = deadman.nextItem {
                merges.append(Merge(keeper: next, deadman: deadman))
            }

            merges = merges.sorted { $0.score.rawValue > $1.score.rawValue }

            var results: (kept: TimelineItem, killed: [TimelineItem])?

            // clean up the dead bodies after all's said and done
            defer {
                if let results = results {
                    self.remove(results.killed)
                    self.processTimelineItems(from: results.kept)
                }
            }

            // do the highest scoring valid merge
            if let winningMerge = merges.first, winningMerge.score != .impossible {
                results = winningMerge.doIt()
                return
            }

            // fall back to doing an "impossible" (ie completely undesirable) merge
            if let shittyMerge = merges.first {
                results = shittyMerge.doIt()
                return
            }

            /**
             - Note: if we got this far, that means the item has no next or previous, so there's no possible
             merges. at this point it's up to someone else to decide how to do the delete. ArcKit can't
             arbitrarily make that decision.
             */

            os_log("COULDN'T SAFE DELETE TIMELINE ITEM: %@", deadman.itemId.uuidString)
        }
    }
}

