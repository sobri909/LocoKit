//
//  TimelineProcessor.swift
//  LocoKit
//
//  Created by Matt Greenfield on 30/04/18.
//

import os.log

public class TimelineProcessor {

    public static func process(from fromItem: TimelineItem) {
        fromItem.store?.process {
            var items: [TimelineItem] = [fromItem]

            // collect items before fromItem, up to two keepers
            var keeperCount = 0
            var workingItem = fromItem
            while keeperCount < 2, let previous = workingItem.previousItem {
                items.append(previous)
                if previous.isWorthKeeping { keeperCount += 1 }
                workingItem = previous
            }

            // collect items after fromItem, up to two keepers
            keeperCount = 0
            workingItem = fromItem
            while keeperCount < 2, let next = workingItem.nextItem {
                items.append(next)
                if next.isWorthKeeping { keeperCount += 1 }
                workingItem = next
            }

            // recurse until no remaining possible merges
            process(items) { results in
                if let kept = results?.kept {
                    process(from: kept)
                }
            }
        }
    }

    public static func process(_ items: [TimelineItem], completion: ((MergeResult?) -> Void)? = nil) {
        guard let store = items.first?.store else { return }
        store.process {

            /** collate all the potential merges **/

            var merges: [Merge] = []
            for workingItem in items {
                workingItem.sanitiseEdges()

                // add in the merges for one step forward
                if let next = workingItem.nextItem, !next.isCurrentItem || next.isWorthKeeping {
                    next.sanitiseEdges()

                    merges.append(Merge(keeper: workingItem, deadman: next))
                    merges.append(Merge(keeper: next, deadman: workingItem))

                    // if next has a lesser keepness, look at doing a merge against next-next
                    if next.keepnessScore < workingItem.keepnessScore {
                        if let nextNext = next.nextItem, nextNext.keepnessScore > next.keepnessScore {
                            nextNext.sanitiseEdges()

                            merges.append(Merge(keeper: workingItem, betweener: next, deadman: nextNext))
                            merges.append(Merge(keeper: nextNext, betweener: next, deadman: workingItem))
                        }
                    }
                }

                // add in the merges for one step backward
                if let previous = workingItem.previousItem {
                    previous.sanitiseEdges()

                    merges.append(Merge(keeper: workingItem, deadman: previous))
                    merges.append(Merge(keeper: previous, deadman: workingItem))

                    // clean up edges
                    previous.sanitiseEdges()

                    // if previous has a lesser keepness, look at doing a merge against previous-previous
                    if previous.keepnessScore < workingItem.keepnessScore {
                        if let prevPrev = previous.previousItem, prevPrev.keepnessScore > previous.keepnessScore {
                            prevPrev.sanitiseEdges()

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
            }

            /** sort the merges by highest to lowest score **/

            merges = merges.sorted { $0.score.rawValue > $1.score.rawValue }

            if !merges.isEmpty {
                var descriptions = ""
                for merge in merges { descriptions += String(describing: merge) + "\n" }
                os_log("Considering:\n%@", type: .debug, descriptions)
            }

            /** find the highest scoring valid merge **/

            guard let winningMerge = merges.first, winningMerge.score != .impossible else {
                completion?(nil)
                return
            }

            /** do it **/

            let results = winningMerge.doIt()

            completion?(results)
        }
    }

    /**
     Attempt to delete the given timeline item by merging it into an adjacent item.

     Calls the completion handler with the timeline item that the deleted item was merged into,
     or nil if a safe delete wasn't possible.
     */
    public static func safeDelete(_ deadman: TimelineItem, completion: ((TimelineItem?) -> Void)? = nil) {
        guard let store = deadman.store else { return }
        store.process {
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

            defer {
                if let results = results {
                    // clean up the leftovers
                    self.process(from: results.kept)
                    completion?(results.kept)

                } else {
                    completion?(nil)
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
        }
    }

    public static func healEdges(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store else { return }
        store.process {
            if brokenItem.isMergeLocked { return }
            if !brokenItem.hasBrokenEdges { return }

            print("\(brokenItem.itemId)")

            self.healNextEdge(of: brokenItem)
            self.healPreviousEdge(of: brokenItem)
        }
    }

    private static func healNextEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store as? PersistentTimelineStore else { return }

        guard brokenItem.nextItem == nil && !brokenItem.isCurrentItem else { return }

        guard let endDate = brokenItem.endDate else {
            print("UNFIXABLE NEXTITEM EDGE (endDate: nil)")
            return
        }

        if let nearest = store.item(
            where: "deleted = 0 AND itemId != ? AND startDate >= ? ORDER BY ABS(strftime('%s', startDate) - ?)",
            arguments: [brokenItem.itemId.uuidString, endDate, endDate.timeIntervalSince1970])
        {
            print("NEAREST NEXTITEM (separation: \(String(format: "%.0fs", nearest.timeInterval(from: brokenItem)!)), hasPrevious: \(nearest.previousItem != nil))")

            if nearest.previousItem == nil, let gap = nearest.timeInterval(from: brokenItem), gap < 60 * 2 {
                print("HEALED NEXTITEM")
                brokenItem.nextItem = nearest
                return
            }
        }

        if let overlapper = store.item(
            where: "deleted = 0 AND itemId != ? AND startDate IS NOT NULL AND endDate IS NOT NULL AND startDate < ? AND endDate > ?",
            arguments: [brokenItem.itemId.uuidString, endDate, endDate])
        {
            print("MERGED INTO OVERLAPPING ITEM")
            overlapper.add(brokenItem.samples)
            brokenItem.deleted = true
            return
        }

        print("COULDN'T HEAL NEXTITEM EDGE")
    }

    private static func healPreviousEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store as? PersistentTimelineStore else { return }
        guard brokenItem.previousItem == nil else { return }

        guard let startDate = brokenItem.startDate else {
            print("UNFIXABLE PREVIOUSITEM EDGE (endDate: nil)")
            return
        }

        if let nearest = store.item(
            where: "deleted = 0 AND itemId != ? AND endDate <= ? ORDER BY ABS(strftime('%s', endDate) - ?)",
            arguments: [brokenItem.itemId.uuidString, startDate, startDate.timeIntervalSince1970])
        {
            print("NEAREST PREVIOUSITEM (separation: \(String(format: "%0.fs", nearest.timeInterval(from: brokenItem)!)), hasNext: \(nearest.nextItem != nil))")

            if nearest.nextItem == nil, let gap = nearest.timeInterval(from: brokenItem), gap < 60 * 2 {
                print("HEALED PREVIOUSITEM")
                brokenItem.previousItem = nearest
                return
            }
        }

        if let overlapper = store.item(
            where: "deleted = 0 AND itemId != ? AND startDate IS NOT NULL AND endDate IS NOT NULL AND startDate < ? AND endDate > ?",
            arguments: [brokenItem.itemId.uuidString, startDate, startDate])
        {
            print("MERGED INTO OVERLAPPING ITEM")
            overlapper.add(brokenItem.samples)
            brokenItem.deleted = true
            return
        }

        print("COULDN'T HEAL PREVIOUSITEM EDGE")
    }

    public static func insertDataGapBetween(newer newerItem: TimelineItem, older olderItem: TimelineItem) {
        guard let store = newerItem.store else { return }
        store.process {
            guard !newerItem.isDataGap && !olderItem.isDataGap else { return }

            guard let gap = newerItem.timeInterval(from: olderItem), gap > 60 * 5 else { print("TOO CLOSE"); return }

            guard let startDate = olderItem.endDate else { return }
            guard let endDate = newerItem.startDate else { return }

            // the edge samples
            let startSample = PersistentSample(date: startDate, recordingState: .off, in: store)
            let endSample = PersistentSample(date: endDate, recordingState: .off, in: store)

            // the gap item
            let gapItem = store.createPath(from: startSample)
            gapItem.previousItem = olderItem
            gapItem.nextItem = newerItem
            gapItem.add(endSample)
        }
    }

}
