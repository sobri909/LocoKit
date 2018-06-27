//
//  TimelineProcessor.swift
//  LocoKit
//
//  Created by Matt Greenfield on 30/04/18.
//

import os.log

public class TimelineProcessor {

    public static var debugLogging = false

    // MARK: - Sequential item processing

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

            var merges: Set<Merge> = []
            for workingItem in items {
                workingItem.sanitiseEdges()

                // add in the merges for one step forward
                if let next = workingItem.nextItem {
                    next.sanitiseEdges()

                    merges.insert(Merge(keeper: workingItem, deadman: next))
                    merges.insert(Merge(keeper: next, deadman: workingItem))

                    // if next has a lesser keepness, look at doing a merge against next-next
                    if !workingItem.isDataGap, next.keepnessScore < workingItem.keepnessScore {
                        if let nextNext = next.nextItem, !nextNext.isDataGap, nextNext.keepnessScore > next.keepnessScore {
                            nextNext.sanitiseEdges()

                            merges.insert(Merge(keeper: workingItem, betweener: next, deadman: nextNext))
                            merges.insert(Merge(keeper: nextNext, betweener: next, deadman: workingItem))
                        }
                    }
                }

                // add in the merges for one step backward
                if let previous = workingItem.previousItem {
                    previous.sanitiseEdges()

                    merges.insert(Merge(keeper: workingItem, deadman: previous))
                    merges.insert(Merge(keeper: previous, deadman: workingItem))

                    // clean up edges
                    previous.sanitiseEdges()

                    // if previous has a lesser keepness, look at doing a merge against previous-previous
                    if !workingItem.isDataGap, previous.keepnessScore < workingItem.keepnessScore {
                        if let prevPrev = previous.previousItem, !prevPrev.isDataGap, prevPrev.keepnessScore > previous.keepnessScore {
                            prevPrev.sanitiseEdges()

                            merges.insert(Merge(keeper: workingItem, betweener: previous, deadman: prevPrev))
                            merges.insert(Merge(keeper: prevPrev, betweener: previous, deadman: workingItem))
                        }
                    }
                }

                // if keepness scores allow, add in a bridge merge over top of working item
                if let previous = workingItem.previousItem, let next = workingItem.nextItem,
                    previous.keepnessScore > workingItem.keepnessScore, next.keepnessScore > workingItem.keepnessScore,
                    !previous.isDataGap, !next.isDataGap
                {
                    merges.insert(Merge(keeper: previous, betweener: workingItem, deadman: next))
                    merges.insert(Merge(keeper: next, betweener: workingItem, deadman: previous))
                }
            }

            /** sort the merges by highest to lowest score **/

            let sortedMerges = merges.sorted { $0.score.rawValue > $1.score.rawValue }

            if !sortedMerges.isEmpty {
                var descriptions = ""
                for merge in sortedMerges { descriptions += String(describing: merge) + "\n" }
                if debugLogging { os_log("Considering:\n%@", type: .debug, descriptions) }
            }

            /** find the highest scoring valid merge **/

            guard let winningMerge = sortedMerges.first, winningMerge.score != .impossible else {
                completion?(nil)
                return
            }

            /** do it **/

            let results = winningMerge.doIt()

            completion?(results)
        }
    }

    // MARK: - Item safe deletion

    /**
     Attempt to delete the given timeline item by merging it into an adjacent item.

     Calls the completion handler with the timeline item that the deleted item was merged into,
     or nil if a safe delete wasn't possible.
     */
    public static func safeDelete(_ deadman: TimelineItem, completion: ((TimelineItem?) -> Void)? = nil) {
        guard let store = deadman.store else { return }
        store.process {
            deadman.sanitiseEdges()

            var merges: Set<Merge> = []

            // merge next and previous
            if let next = deadman.nextItem, let previous = deadman.previousItem {
                merges.insert(Merge(keeper: next, betweener: deadman, deadman: previous))
                merges.insert(Merge(keeper: previous, betweener: deadman, deadman: next))
            }

            // merge into previous
            if let previous = deadman.previousItem {
                merges.insert(Merge(keeper: previous, deadman: deadman))
            }

            // merge into next
            if let next = deadman.nextItem {
                merges.insert(Merge(keeper: next, deadman: deadman))
            }

            let sortedMerges = merges.sorted { $0.score.rawValue > $1.score.rawValue }

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
            if let winningMerge = sortedMerges.first, winningMerge.score != .impossible {
                results = winningMerge.doIt()
                return
            }

            // fall back to doing an "impossible" (ie completely undesirable) merge
            if let shittyMerge = sortedMerges.first {
                results = shittyMerge.doIt()
                return
            }
        }
    }

}
