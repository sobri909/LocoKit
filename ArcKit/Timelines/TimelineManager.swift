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
    public static let timelineItemUpdated = Notification.Name("timelineItemUpdated")
}

@objc public class TimelineManager: NSObject {

    private var recording = false
    private var lastRecorded: Date?
    
    @objc private(set) public var timelineItems: [TimelineItem] = []

    // MARK: The Singleton

    /// The TimelineManager singleton instance, through which all actions should be performed.
    public static let highlander = TimelineManager()

    // MARK: Settings

    /**
     The target number of samples to record per minute.

     - Note: The actual number of samples recorded per minute may be less than this, depending on data availability.
     */
    public var samplesPerMinute: Double = 10

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
    private(set) public var currentItem: TimelineItem?

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
            NotificationCenter.default.post(Notification(name: .timelineItemUpdated, object: self, userInfo: nil))
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

        processTimelineItems()
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

        currentItem = newItem
        timelineItems.append(newItem)

        NotificationCenter.default.post(Notification(name: .newTimelineItem, object: self,
                                                     userInfo: ["timelineItem": newItem]))
    }

    private func processTimelineItems() {
        if timelineItems.isEmpty {
            return
        }

        // only process from a keeper current item
        guard let current = currentItem, current.isWorthKeeping else {
            return
        }

        var workingItem = current

        var merges: [Merge] = []

        // collect all possible merges
        while true {

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

        print("merges: \(merges)")

        // do the highest scoring valid merge
        if let winningMerge = merges.first, winningMerge.score != .impossible {
            print("DOING: \(winningMerge)")

            let results = winningMerge.doIt()

            // sweep up the dead bodies
            timelineItems.removeObjects(results.killed)

            // recurse until no valid merges left to do
            processTimelineItems()
        }
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .locomotionSampleUpdated, object: nil, queue: nil) { _ in
            self.sampleUpdated()
        }
    }
}
