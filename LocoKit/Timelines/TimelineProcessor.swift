//
//  TimelineProcessor.swift
//  LocoKit
//
//  Created by Matt Greenfield on 30/04/18.
//

import Foundation
import GRDB

public class TimelineProcessor {

    public static var debugLogging = false
    public static var maximumItemsInProcessingLoop = 21
    public static var maximumPotentialMergesInProcessingLoop = 10

    // MARK: - Sequential item processing

    public static func itemsToProcess(from fromItem: TimelineItem) -> [TimelineItem] {
        var items: [TimelineItem] = [fromItem]

        // collect items before fromItem, up to two keepers
        var keeperCount = 0
        var workingItem = fromItem
        while keeperCount < 2, items.count < maximumItemsInProcessingLoop, let previous = workingItem.previousItem {
            items.append(previous)
            if previous.isWorthKeeping { keeperCount += 1 }
            workingItem = previous
        }

        // collect items after fromItem, up to two keepers
        keeperCount = 0
        workingItem = fromItem
        while keeperCount < 2, items.count < maximumItemsInProcessingLoop, let next = workingItem.nextItem {
            items.append(next)
            if next.isWorthKeeping { keeperCount += 1 }
            workingItem = next
        }

        return items
    }

    public static func process(from fromItem: TimelineItem) {
        fromItem.store?.process {
            let items = itemsToProcess(from: fromItem)

            // recurse until no remaining possible merges
            process(items) { results in
                if let kept = results?.kept {
                    delay(0.3) { process(from: kept) }
                }
            }
        }
    }

    private static var lastCleansedSamples: Set<LocomotionSample> = []

    public static func process(_ givenItems: [TimelineItem], completion: ((MergeResult?) -> Void)? = nil) {
        guard let store = givenItems.first?.store else { return }

        let startDate = givenItems.compactMap({ $0.startDate }).min()
        let endDate = givenItems.compactMap({ $0.startDate }).max()

        // sanitise the store in the items date range
        if let start = startDate, let end = endDate {
            sanitise(store: store, inRange: DateInterval(start: start, end: end))
        }

        store.process {
            var items = givenItems

            // look for all timeline items in the range, not just the given ones (might be new ones from sanitise or cache might be invalid)
            if let start = startDate, let end = endDate {
                items = store.items(where: "startDate >= ? AND endDate <= ?", arguments: [start, end])
            }

            var merges: Set<Merge> = []
            var itemsToSanitise: Set<TimelineItem> = []

            /** collate all the potential merges **/

            for workingItem in items {
                // if there's at least one possible merge, stop collating more once we're at the limit
                if merges.count >= maximumPotentialMergesInProcessingLoop, merges.first(where: { $0.score != .impossible }) != nil {
                    break
                }
                
                itemsToSanitise.insert(workingItem)

                // add in the merges for one step forward
                if let next = workingItem.nextItem {
                    itemsToSanitise.insert(next)

                    merges.insert(Merge(keeper: workingItem, deadman: next))
                    merges.insert(Merge(keeper: next, deadman: workingItem))

                    // if next has a lesser keepness, look at doing a merge against next-next
                    if !workingItem.isDataGap, next.keepnessScore < workingItem.keepnessScore {
                        if let nextNext = next.nextItem, !nextNext.isDataGap, nextNext.keepnessScore > next.keepnessScore {
                            itemsToSanitise.insert(nextNext)

                            merges.insert(Merge(keeper: workingItem, betweener: next, deadman: nextNext))
                            merges.insert(Merge(keeper: nextNext, betweener: next, deadman: workingItem))
                        }
                    }
                }

                // add in the merges for one step backward
                if let previous = workingItem.previousItem {
                    itemsToSanitise.insert(previous)

                    merges.insert(Merge(keeper: workingItem, deadman: previous))
                    merges.insert(Merge(keeper: previous, deadman: workingItem))

                    // if previous has a lesser keepness, look at doing a merge against previous-previous
                    if !workingItem.isDataGap, previous.keepnessScore < workingItem.keepnessScore {
                        if let prevPrev = previous.previousItem, !prevPrev.isDataGap, prevPrev.keepnessScore > previous.keepnessScore {
                            itemsToSanitise.insert(prevPrev)

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

            /** sanitise the edges **/
            var allMoved: Set<LocomotionSample> = []
            itemsToSanitise.forEach {
                for segment in $0.segments where segment.activityType == .stationary {
                    pruneSamples(segment.samples)
                }
                let moved = $0.sanitiseEdges(excluding: lastCleansedSamples)
                allMoved.formUnion(moved)
            }
            
            if debugLogging, !allMoved.isEmpty { logger.debug("Moved \(allMoved.count) samples between item edges") }

            // infinite loop breakers, for the next processing cycle
            lastCleansedSamples = allMoved

            // check for invalid merges
            for merge in merges {
                if !merge.isValid {
                    if debugLogging { logger.debug("Invalid merge. Breaking edges.") }
                    merge.keeper.breakEdges()
                    merge.betweener?.breakEdges()
                    merge.deadman.breakEdges()
                }
            }

            /** sort the merges by highest to lowest score **/

            let sortedMerges = merges.sorted { $0.score.rawValue > $1.score.rawValue }

            if !sortedMerges.isEmpty {
                var descriptions = ""
                for merge in sortedMerges { descriptions += String(describing: merge) + "\n" }
                if debugLogging { logger.debug("Considering \(merges.count) merges:\n\(descriptions)") }
            }

            /** find the highest scoring valid merge **/

            guard let winningMerge = sortedMerges.first, winningMerge.score != .impossible else {
                completion?(nil)
                return
            }

            /** do it **/

            let results = winningMerge.doIt()

            // don't need infinite loop breakers now, because the merge broke the loop
            lastCleansedSamples = []

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

    // MARK: - ItemSegment brexiting

    public static func extractItem(for segment: ItemSegment, in store: TimelineStore) async -> TimelineItem? {
        return await withCheckedContinuation { continuation in
            extractItem(for: segment, in: store) { item in
                continuation.resume(returning: item)
            }
        }
    }

    public static func extractItem(for segment: ItemSegment, in store: TimelineStore, completion: ((TimelineItem?) -> Void)? = nil) {
        store.process {
            guard let segmentRange = segment.dateRange else {
                completion?(nil)
                return
            }

            // don't mess with merge locked parent
            if let item = segment.timelineItem, item.isMergeLocked { return }

            // find the overlapping items
            let overlappers = store.items(
                where: "endDate > :startDate AND startDate < :endDate AND deleted = 0 AND disabled = 0 ORDER BY startDate",
                arguments: ["startDate": segmentRange.start, "endDate": segmentRange.end])

            var modifiedItems: [TimelineItem] = []
            var samplesToSteal: Set<PersistentSample> = Set(segment.samples)

            // find existing samples that fall inside the segment's range
            for overlapper in overlappers {
                if overlapper.isMergeLocked {
                    logger.debug("An overlapper is merge locked. Aborting extraction.")
                    completion?(nil)
                    return
                }

                var lostPrevEdge = false, lostNextEdge = false

                // find samples inside the segment's range
                for sample in overlapper.samples where segmentRange.contains(sample.date) {
                    if sample == overlapper.samples.first { lostPrevEdge = true }
                    if sample == overlapper.samples.last { lostNextEdge = true }
                    samplesToSteal.insert(sample)
                }

                // detach previous edge, if modified
                if lostPrevEdge {
                    overlapper.previousItem = nil
                    modifiedItems.append(overlapper)
                }

                // detach next edge, if modified
                if lostNextEdge {
                    overlapper.nextItem = nil
                    modifiedItems.append(overlapper)
                }
            }

            // create the new item
            let newItem = segment.activityType == .stationary
                ? store.createVisit(from: segment.samples)
                : store.createPath(from: segment.samples)

            // add the stolen samples to the new item
            if !samplesToSteal.isEmpty {
                newItem.add(Array(samplesToSteal))
            }

            // delete any newly empty items
            for modifiedItem in modifiedItems where modifiedItem.samples.isEmpty {
                modifiedItem.delete()
            }

            // if the new item is inside an overlapper, split that overlapper in two
            for overlapper in overlappers where !overlapper.deleted {
                guard let newItemRange = newItem.dateRange else { break }
                guard let overlapperRange = overlapper.dateRange else { continue }
                guard let intersection = overlapperRange.intersection(with: newItemRange) else { continue }
                guard intersection.duration < overlapper.duration else { continue }

                logger.debug("Splitting an overlapping item in two")

                // get all samples from overlapper up to the point of overlap
                let samplesToExtract = overlapper.samples.prefix { $0.date < newItemRange.start }

                // create a new item from those samples
                let splitItem = overlapper is Path
                    ? store.createPath(from: Array(samplesToExtract))
                    : store.createVisit(from: Array(samplesToExtract))
                modifiedItems.append(splitItem)

                // detach the edge to allow proper reconnect at healing time
                overlapper.previousItem = nil

                // copy metadata to the splitter
                splitItem.copyMetadata(from: overlapper)
            }

            // attempt to connect up the new item
            healEdges(of: newItem)

            // edge heal all modified items, or delete if empty
            for modifiedItem in modifiedItems {
                healEdges(of: modifiedItem)
            }

            // extract paths around a new visit, as appropriate
            if let visit = newItem as? Visit {
                extractPathEdgesFor(visit, in: store)
            }

            // keep currentItem sane
            store.process {
                store.recorder?.updateCurrentItem()
            }

            // complete with the new item
            completion?(newItem)
        }
    }

    public static func extractPathEdgesFor(_ visit: Visit, in store: TimelineStore) {
        if visit.deleted || visit.isMergeLocked { return }

        if let previousVisit = visit.previousItem as? Visit {
            extractPathBetween(visit: visit, and: previousVisit, in: store)
        }

        if let nextVisit = visit.nextItem as? Visit {
            extractPathBetween(visit: visit, and: nextVisit, in: store)
        }
    }

    public static func extractPathBetween(visit: Visit, and otherVisit: Visit, in store: TimelineStore) {
        if visit.deleted || visit.isMergeLocked { return }
        if otherVisit.deleted || otherVisit.isMergeLocked { return }
        guard visit.nextItem == otherVisit || visit.previousItem == otherVisit else { return }

        let previousVisit = visit.nextItem == otherVisit ? visit : otherVisit
        let nextVisit = visit.nextItem == otherVisit ? otherVisit : visit

        var pathSegment: ItemSegment
        if let nextStart = nextVisit.segmentsByActivityType.first, nextStart.activityType != .stationary {
            pathSegment = nextStart
        } else if let previousEnd = previousVisit.segmentsByActivityType.last, previousEnd.activityType != .stationary {
            pathSegment = previousEnd
        } else {
            return
        }

        extractItem(for: pathSegment, in: store)
    }

    // MARK: - Item edge healing

    public static func healEdges(of items: [TimelineItem]) {
        items.forEach { healEdges(of: $0) }
    }

    public static func healEdges(of brokenItem: TimelineItem) {
        guard brokenItem.hasBrokenEdges else { return }
        guard let store = brokenItem.store else { return }

        store.process {
            self.healPreviousEdge(of: brokenItem)
            self.healNextEdge(of: brokenItem)

            // it's wholly contained by another item?
            if !brokenItem.isMergeLocked, let dateRange = brokenItem.dateRange {
                guard brokenItem.hasBrokenPreviousItemEdge && brokenItem.hasBrokenNextItemEdge else { return }

                if let overlapper = store.item(
                    where: """
                startDate <= :startDate AND endDate >= :endDate AND startDate IS NOT NULL AND endDate IS NOT NULL
                AND deleted = 0 AND disabled = 0 AND itemId != :itemId
                """,
                    arguments: ["startDate": dateRange.start, "endDate": dateRange.end,
                                "itemId": brokenItem.itemId.uuidString]),
                   !overlapper.deleted && !overlapper.isMergeLocked
                {
                    overlapper.add(brokenItem.samples)
                    brokenItem.delete()
                    return
                }
            }
        }
    }

    private static func healNextEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store else { return }
        guard brokenItem.hasBrokenNextItemEdge else { return }
        guard let dateRange = brokenItem.dateRange else { return }

        // TODO: this looks wrong
        // it's an item that only overlaps the start of the broken item,
        // but it's being used to consume the whole broken item
        if !brokenItem.isMergeLocked {
            if let overlapper = store.item(
                where: """
            startDate < :endDate1 AND endDate > :endDate2 AND startDate IS NOT NULL AND endDate IS NOT NULL
            AND isVisit = :isVisit AND deleted = 0 AND disabled = 0 AND itemId != :itemId
            """,
                arguments: ["endDate1": dateRange.end, "endDate2": dateRange.end, "isVisit": brokenItem is Visit,
                            "itemId": brokenItem.itemId.uuidString]),
               !overlapper.deleted && !overlapper.isMergeLocked && overlapper.source == brokenItem.source
            {
                overlapper.add(brokenItem.samples)
                brokenItem.delete()
                return
            }
        }

        if let nearest = store.item(
            for: """
            SELECT *, ABS(strftime('%s', startDate) - :timestamp) AS gap FROM TimelineItem
            WHERE startDate IS NOT NULL AND startDate > :startDate AND gap < 86400 AND deleted = 0 AND disabled = 0 AND itemId != :itemId
            ORDER BY gap
            """,
            arguments: ["startDate": dateRange.start, "itemId": brokenItem.itemId.uuidString,
                        "timestamp": dateRange.end.timeIntervalSince1970]),
            !nearest.deleted && !nearest.isMergeLocked
        {
            // nearest is already this item's edge? eh?
            if nearest.previousItemId == brokenItem.itemId { return }

            // nearest is already this item's other edge? wtf no
            if brokenItem.previousItemId == nearest.itemId {
                brokenItem.previousItem = nil
                return
            }

            if let gap = nearest.timeInterval(from: brokenItem) {

                // nearest already has an edge connection?
                if let theirEdge = nearest.previousItem {

                    if let theirGap = nearest.timeInterval(from: theirEdge) {

                        // broken item's edge is closer than nearest's current edge? steal it
                        if abs(gap) < abs(theirGap) {
                            brokenItem.nextItem = nearest
                            return
                        }
                    }

                } else { // they don't have an edge connection, so it's safe to connect
                    brokenItem.nextItem = nearest
                    return
                }
            }
        }
    }

    private static func healPreviousEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store else { return }
        guard brokenItem.hasBrokenPreviousItemEdge else { return }
        guard let dateRange = brokenItem.dateRange else { return }

        // TODO: this looks wrong
        // it's an item that only overlaps the start of the broken item,
        // but it's being used to consume the whole broken item
        if !brokenItem.isMergeLocked {
            if let overlapper = store.item(
                where: """
            startDate < :startDate1 AND endDate > :startDate2 AND startDate IS NOT NULL AND endDate IS NOT NULL
            AND isVisit = :isVisit AND deleted = 0 AND disabled = 0 AND itemId != :itemId
            """,
                arguments: ["startDate1": dateRange.start, "startDate2": dateRange.start, "isVisit": brokenItem is Visit,
                            "itemId": brokenItem.itemId.uuidString]),
               !overlapper.deleted && !overlapper.isMergeLocked && overlapper.source == brokenItem.source
            {
                overlapper.add(brokenItem.samples)
                brokenItem.delete()
                return
            }
        }

        if let nearest = store.item(
            for: """
            SELECT *, ABS(strftime('%s', endDate) - :timestamp) AS gap FROM TimelineItem
            WHERE endDate IS NOT NULL AND endDate < :endDate AND gap < 86400 AND deleted = 0 AND disabled = 0 AND itemId != :itemId
            ORDER BY gap
            """,
            arguments: ["endDate": dateRange.end, "itemId": brokenItem.itemId.uuidString,
                        "timestamp": dateRange.start.timeIntervalSince1970]),
            !nearest.deleted && !nearest.isMergeLocked
        {
            // nearest is already this item's edge? eh?
            if nearest.nextItemId == brokenItem.itemId { return }

            // nearest is already this item's other edge? wtf no
            if brokenItem.nextItemId == nearest.itemId {
                brokenItem.nextItem = nil
                return
            }

            if let gap = nearest.timeInterval(from: brokenItem) {

                // nearest already has an edge connection?
                if let theirEdge = nearest.nextItem {

                    if let theirGap = nearest.timeInterval(from: theirEdge) {

                        // broken item's edge is closer than nearest's current edge? steal it
                        if abs(gap) < abs(theirGap) {
                            brokenItem.previousItem = nearest
                            return
                        }
                    }

                } else { // they don't have an edge connection, so it's safe to connect
                    brokenItem.previousItem = nearest
                    return
                }
            }
        }
    }

    // MARK: - Visit sample pruning
    
    /**
     * these return true if changes were made, ie sample(s) deleted
     */

    public static func pruneSamples(for visit: Visit) {
        visit.samples.first?.store?.process {
            pruneSamples(visit.samples)
        }
    }
    
    public static func pruneSamples(for segment: ItemSegment) {
        segment.samples.first?.store?.process {
            pruneSamples(segment.samples)
        }
    }
    
    private static func pruneSamples(_ samples: [PersistentSample]) {
        guard samples.count >= 4 else { return }
        guard let dateRange = samples.dateRange else { return }
        
        // collect the contiguous sleep & stationary samples from the end
        let edgeSamples = samples.reversed().prefix {
            RecordingState.sleepStates.contains($0.recordingState) || $0.activityType == .stationary
        }
        
        /** settings **/
        let keeperBoundary: TimeInterval = .oneMinute * 30 // keep all samples within the first and last X minutes
        let durationBetween: TimeInterval = .oneMinute * 2 // beyond that, keep only one sample per X minutes
        
        var lastKept: PersistentSample? = edgeSamples.last
        var samplesToKill: [PersistentSample] = []
        
        for sample in edgeSamples.reversed() {
            // sample within the "don't touch" end boundary? then we done
            if sample.date > dateRange.end - keeperBoundary { break }
            
            // sample within the "don't touch" start boundary? skip it
            if sample.date < dateRange.start + keeperBoundary { continue }
            
            // sample has confirmed non-stationary type? keep it
            if let type = sample.confirmedType, type != .stationary {
                lastKept = sample
                continue
            }
            
            // sample is too close to the previously kept one?
            if let lastKept = lastKept, sample.date.timeIntervalSince(lastKept.date) < durationBetween {
                samplesToKill.append(sample)
                continue
            }
            
            // must've kept it
            lastKept = sample
        }
        
        if !samplesToKill.isEmpty {
            let slimmedCount = edgeSamples.count - samplesToKill.count
            let savings = 1.0 - Double(slimmedCount) / Double(edgeSamples.count)
            logger.debug("pruneSamples() \(savings * 100, format: .fixed(precision: 0), align: .right(columns: 2))% reduction, \(edgeSamples.count, align: .right(columns: 4)) -> \(slimmedCount, align: .right(columns: 4)) (samples.startDate: \(String(describing: dateRange.start)))")
        }
        
        samplesToKill.forEach { $0.delete() }
    }

    // MARK: - Data gap insertion

    public static func insertDataGapBetween(newer newerItem: TimelineItem, older olderItem: TimelineItem) {
        guard let store = newerItem.store else { return }
        store.process {
            guard !newerItem.isDataGap && !olderItem.isDataGap else { return }

            guard let gap = newerItem.timeInterval(from: olderItem), gap > 60 * 5 else { return }

            guard let startDate = olderItem.endDate else { return }
            guard let endDate = newerItem.startDate else { return }

            // the edge samples
            let startSample = store.createSample(date: startDate, recordingState: .off)
            let endSample = store.createSample(date: endDate, recordingState: .off)

            // the gap item
            let gapItem = store.createPath(from: startSample)
            gapItem.previousItem = olderItem
            gapItem.nextItem = newerItem
            gapItem.add(endSample)
        }
    }

    // MARK: - Enabling/disabling items

    public static func enable(timelineItem: TimelineItem) async {
        guard let store = timelineItem.store else { return }
        guard let dateRange = timelineItem.dateRange else { return }

        print("TimelineProcessor.enable(timelineItem:) duration: \(duration: dateRange.duration), dateRange: \(dateRange.debugDescription)")

        await store.process {
            // 1. disable all overlapped samples
            let overlappedSamples = store.samples(
                where: "date BETWEEN ? AND ? AND timelineItemId IS NOT ? AND disabled = 0",
                arguments: [dateRange.start, dateRange.end, timelineItem.itemId.uuidString]
            )
            print("overlappedSamples: \(overlappedSamples.count)")
            for sample in overlappedSamples {
                sample.timelineItem?.breakEdges()
                sample.disabled = true
                sample.save()
            }

            store.save() // flush to db

            // 2. disable and break egdges of fully overlapped items
            let overlappedItems = store.items(
                where: "startDate >= ? AND endDate <= ? AND itemId != ? AND disabled = 0",
                arguments: [dateRange.start, dateRange.end, timelineItem.itemId.uuidString]
            )
            print("overlappedItems: \(overlappedItems.count)")
            overlappedItems.forEach { item in
                let samples = item.samples
                item.disabled = true
                item.breakEdges()
                samples.forEach { $0.disabled = true; $0.save() }
                item.save()
            }

            store.save() // flush to db

            // 4. it an item entirely overlaps the range, split it in two
            let biggerItem = store.item(
                where: "startDate < ? AND endDate > ? AND itemId != ? AND disabled = 0",
                arguments: [timelineItem.startDate, timelineItem.endDate, timelineItem.itemId.uuidString]
            )
            if let biggerItem {
                print("biggerItem.samples \(biggerItem.samples.count), duration: \(duration: biggerItem.duration), dateRange: \(biggerItem.dateRange?.debugDescription ?? "nil")")
                let endSamples = biggerItem.samples.filter { $0.date > dateRange.end }
                if !endSamples.isEmpty {
                    let endItem: TimelineItem
                    if biggerItem.isVisit {
                        endItem = store.createVisit(from: endSamples)
                    } else {
                        endItem = store.createPath(from: endSamples)
                    }
                    endItem.copyMetadata(from: biggerItem)
                    endItem.save()
                }
                biggerItem.breakEdges()
                biggerItem.save()
            }

            store.save() // flush to db

            // 6. enable the target item
            let samples = timelineItem.samples
            samples.forEach { $0.disabled = false; $0.save() }
            timelineItem.disabled = false
            timelineItem.add(samples)
            timelineItem.save()

            if #available(iOS 15.0, *) {
                if let newRange = timelineItem.dateRange {
                    print("ENABLED samples: \(timelineItem.samples.count), duration: \(duration: timelineItem.duration), \(newRange.debugDescription)")
                } else {
                    print("ENABLED **doesn't have dateRange!**")
                }
            }

            // 6. heal the edges
            healEdges(of: timelineItem)

            // current item might be wrong
            store.process {
                store.recorder?.updateCurrentItem()
            }
        }
    }

    public static func disable(timelineItem: TimelineItem) async {
        guard let store = timelineItem.store else { return }
        guard let dateRange = timelineItem.dateRange else { return }

        print("TimelineProcessor.disable(timelineItem:) duration: \(duration: dateRange.duration), dateRange: \(dateRange.debugDescription)")

        await store.process {
            // 1. enable all disabled samples inside the range
            let overlappedSamples = store.samples(
                where: "date BETWEEN ? AND ? AND timelineItemId IS NOT ? and disabled = 1",
                arguments: [dateRange.start, dateRange.end, timelineItem.itemId.uuidString]
            )
            print("overlappedSamples: \(overlappedSamples.count)")
            overlappedSamples.forEach { sample in
                sample.disabled = false
                sample.save()
                if let parent = sample.timelineItem {
                    parent.disabled = false
                    parent.add(sample)
                    parent.save()
                }
            }

            store.save() // flush to db

            // 2. enable all disabled items inside the range
            let overlappedItems = store.items(
                where: "((startDate BETWEEN ? AND ?) OR (endDate BETWEEN ? AND ?)) AND itemId != ? AND disabled = 1",
                arguments: [dateRange.start, dateRange.end, dateRange.start, dateRange.end, timelineItem.itemId.uuidString]
            )
            print("overlappedItems: \(overlappedItems.count)")
            overlappedItems.forEach { item in
                let samples = item.samples
                samples.forEach { $0.disabled = false; $0.save() }
                item.disabled = false
                item.add(samples)
                item.save()
            }

            store.save() // flush to db

            // 3. disable the item and its samples
            let samples = timelineItem.samples
            samples.forEach { $0.disabled = true; $0.save() }
            timelineItem.disabled = true
            timelineItem.add(samples)
            timelineItem.breakEdges()
            timelineItem.save()
        }

        // 4. there might be orphans that need help
        TimelineProcessor.sanitise(store: store, inRange: dateRange)
    }

    // MARK: - Database sanitising

    public static func sanitise(store: TimelineStore, inRange dateRange: DateInterval? = nil) {
        store.process {
            orphanSamplesFromDeadParents(in: store, inRange: dateRange)
            adoptOrphanedSamples(in: store, inRange: dateRange)
            detachDeadmenEdges(in: store, inRange: dateRange)
        }
    }

    private static func adoptOrphanedSamples(in store: TimelineStore, inRange dateRange: DateInterval? = nil) {
        store.connectToDatabase()

        var query = "timelineItemId IS NULL AND deleted = 0"
        var arguments: [DatabaseValueConvertible] = []
        if let dateRange = dateRange {
            query += " AND date BETWEEN ? AND ?"
            arguments = [dateRange.start, dateRange.end]
        }

        let orphans = store.samples(where: query + " ORDER BY date DESC", arguments: StatementArguments(arguments))

        if orphans.isEmpty { return }

        logger.debug("Found orphaned samples: \(orphans.count)")

        var newParents: [TimelineItem] = []

        for orphan in orphans where orphan.timelineItem == nil && !orphan.deleted {
            if let item = store.item(where: "startDate <= ? AND endDate >= ? AND deleted = 0 AND source = ?",
                                     arguments: [orphan.date, orphan.date, orphan.source]) {
                if #available(iOS 15.0, *) {
                    logger.debug("ADOPTED AN ORPHAN source: \(orphan.source), disabled: \(orphan.disabled), date: \(orphan.date.formatted(date: .abbreviated, time: .shortened))")
                }
                item.add(orphan)

            } else if orphan.source == "LocoKit" && !orphan.disabled { // create new items for LcooKit orphans
                if orphan.movingState == .stationary {
                    newParents.append(store.createVisit(from: orphan))
                } else {
                    newParents.append(store.createPath(from: orphan))
                }
                if #available(iOS 15.0, *) {
                    logger.debug("CREATED NEW PARENT FOR ORPHAN source: \(orphan.source), disabled: \(orphan.disabled), date: \(orphan.date.formatted(date: .abbreviated, time: .shortened))")
                }
            } else {
                if #available(iOS 15.0, *) {
                    print("COULDN'T ADOPT ORPHAN source: \(orphan.source), disabled: \(orphan.disabled), date: \(orphan.date.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }

        store.save()

        // clean up the new parents
        newParents.forEach {
            TimelineProcessor.healEdges(of: $0)
            TimelineProcessor.process(from: $0)
        }
    }

    private static func orphanSamplesFromDeadParents(in store: TimelineStore, inRange dateRange: DateInterval? = nil) {
        store.connectToDatabase()

        var query = """
                SELECT LocomotionSample.* FROM LocomotionSample
                    JOIN TimelineItem ON timelineItemId = TimelineItem.itemId
                WHERE TimelineItem.deleted = 1
                """
        var arguments: [DatabaseValueConvertible] = []
        if let dateRange = dateRange {
            query += " AND date >= ? AND date <= ?"
            arguments = [dateRange.start, dateRange.end]
        }

        let orphans = store.samples(for: query, arguments: StatementArguments(arguments))

        if orphans.isEmpty { return }

        logger.debug("Samples holding onto dead parents: \(orphans.count)")

        for orphan in orphans where orphan.timelineItemId != nil {
            orphan.timelineItemId = nil
        }

        store.save()
    }

    private static func detachDeadmenEdges(in store: TimelineStore, inRange dateRange: DateInterval? = nil) {
        store.connectToDatabase()

        var query = "(deleted = 1 OR disabled = 1) AND (previousItemId IS NOT NULL OR nextItemId IS NOT NULL)"
        var arguments: [DatabaseValueConvertible] = []
        if let dateRange = dateRange {
            query += " AND startDate >= ? AND endDate <= ?"
            arguments = [dateRange.start, dateRange.end]
        }

        let deadmen = store.items(where: query, arguments: StatementArguments(arguments))

        if deadmen.isEmpty { return }

        logger.debug("Deadmen to edge detach: \(deadmen.count)")

        for deadman in deadmen {
            deadman.previousItemId = nil
            deadman.nextItemId = nil
        }

        store.save()
    }

}
