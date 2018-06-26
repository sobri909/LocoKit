//
//  PersistentProcessor.swift
//  LocoKit
//
//  Created by Matt Greenfield on 26/5/18.
//

import os.log

public class PersistentProcessor {

    // MARK: - ItemSegment brexiting

    public static func extractItem(for segment: ItemSegment, in store: PersistentTimelineStore, completion: ((TimelineItem?) -> Void)? = nil) {
        store.process {
            guard let segmentRange = segment.dateRange else {
                completion?(nil)
                return
            }

            // find the overlapping items
            let overlappers = store.items(
                where: "endDate > :startDate AND startDate < :endDate AND deleted = 0 ORDER BY startDate",
                arguments: ["startDate": segmentRange.start, "endDate": segmentRange.end])

            var modifiedItems: [TimelineItem] = []
            var samplesToSteal: [LocomotionSample] = []

            // find existing samples that fall inside the segment's range
            for overlapper in overlappers {
                if overlapper.isMergeLocked {
                    print("An overlapper is merge locked. Aborting extraction.")
                    completion?(nil)
                    return
                }

                var lostPrevEdge = false, lostNextEdge = false

                // find samples inside the segment's range
                for sample in overlapper.samples where segmentRange.contains(sample.date) {
                    if sample == overlapper.samples.first { lostPrevEdge = true }
                    if sample == overlapper.samples.last { lostNextEdge = true }
                    samplesToSteal.append(sample)
                }

                // detach previous edge, if modified
                if lostPrevEdge {
                    print("Detaching overlapper.previousItem")
                    overlapper.previousItem = nil
                    modifiedItems.append(overlapper)
                }

                // detach next edge, if modified
                if lostNextEdge {
                    print("Detaching overlapper.nextItem")
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
                print("Moving \(samplesToSteal.count) samples from overlappers to inserted item")
                newItem.add(samplesToSteal)
            }

            // delete any newly empty items
            for modifiedItem in modifiedItems where modifiedItem.samples.isEmpty {
                print("Deleting a newly empty item")
                modifiedItem.delete()
            }

            // if the new item is inside an overlapper, split that overlapper in two
            for overlapper in overlappers where !overlapper.deleted {
                guard let newItemRange = newItem.dateRange else { break }
                guard let overlapperRange = overlapper.dateRange else { continue }
                guard let intersection = overlapperRange.intersection(with: newItemRange) else { continue }
                guard intersection.duration < overlapper.duration else { continue }

                print("Splitting an overlapping item in two")

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

            // complete with the new item
            completion?(newItem)
        }
    }

    public static func extractPathEdgesFor(_ visit: Visit, in store: PersistentTimelineStore) {
        if visit.deleted || visit.isMergeLocked { return }

        if let previousVisit = visit.previousItem as? Visit {
            extractPathBetween(visit: visit, and: previousVisit, in: store)
        }

        if let nextVisit = visit.nextItem as? Visit {
            extractPathBetween(visit: visit, and: nextVisit, in: store)
        }
    }

    public static func extractPathBetween(visit: Visit, and otherVisit: Visit, in store: PersistentTimelineStore) {
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

        print("Extracting a path between visits")

        extractItem(for: pathSegment, in: store)
    }

    // MARK: - Item edge healing

    public static func healEdges(of items: [TimelineItem]) {
        items.forEach { healEdges(of: $0) }
    }

    public static func healEdges(of brokenItem: TimelineItem) {
        if brokenItem.isMergeLocked { return }
        if !brokenItem.hasBrokenEdges { return }
        guard let store = brokenItem.store as? PersistentTimelineStore else { return }

        store.process { self.healPreviousEdge(of: brokenItem) }
        store.process { self.healNextEdge(of: brokenItem) }

        // it's wholly contained by another item?
        store.process {
            guard brokenItem.hasBrokenPreviousItemEdge && brokenItem.hasBrokenNextItemEdge else { return }
            guard let dateRange = brokenItem.dateRange else { return }

            if let overlapper = store.item(
                where: """
                startDate <= :startDate AND endDate >= :endDate AND startDate IS NOT NULL AND endDate IS NOT NULL
                AND deleted = 0 AND itemId != :itemId
                """,
                arguments: ["startDate": dateRange.start, "endDate": dateRange.end,
                            "itemId": brokenItem.itemId.uuidString]),
                !overlapper.deleted && !overlapper.isMergeLocked
            {
                print("healEdges(of: \(brokenItem.itemId.shortString)) MERGED INTO CONTAINING ITEM")
                overlapper.add(brokenItem.samples)
                brokenItem.delete()
                return
            }
        }
    }

    private static func healNextEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store as? PersistentTimelineStore else { return }
        if brokenItem.isMergeLocked { return }
        guard brokenItem.hasBrokenNextItemEdge else { return }
        guard let endDate = brokenItem.endDate else { return }

        print("healNextEdge(of: \(brokenItem.itemId.shortString))")

        if let nearest = store.item(
            where: "startDate >= :endDate AND deleted = 0 AND itemId != :itemId ORDER BY ABS(strftime('%s', startDate) - :timestamp)",
            arguments: ["endDate": endDate, "itemId": brokenItem.itemId.uuidString,
                        "timestamp": endDate.timeIntervalSince1970]),
            !nearest.deleted && !nearest.isMergeLocked
        {
            if nearest.previousItemId == brokenItem.itemId {
                print("healNextEdge(of: \(brokenItem.itemId.shortString)) NOT BROKEN")
                return
            }

            if let gap = nearest.timeInterval(from: brokenItem) {

                // nearest already has an edge connection?
                if let theirEdge = nearest.previousItem {

                    if let theirGap = nearest.timeInterval(from: theirEdge) {

                        // broken item's edge is closer than nearest's current edge? steal it
                        if abs(gap) < abs(theirGap) {
                            print("healNextEdge(of: \(brokenItem.itemId.shortString)) HEALED: (\(nearest.itemId.shortString)) (my edge is closer)")
                            brokenItem.nextItem = nearest
                            return

                        } else {
                            print("healNextEdge(of: \(brokenItem.itemId.shortString)) FAILED: (\(nearest.itemId.shortString)) (their edge is closer)")
                        }

                    } else {
                        print("healNextEdge(of: \(brokenItem.itemId.shortString)) FAILED: (\(nearest.itemId.shortString)) (their edge has nil dateRange?)")
                    }

                } else { // they don't have an edge connection, so it's safe to connect
                    print("healNextEdge(of: \(brokenItem.itemId.shortString)) HEALED: (\(nearest.itemId.shortString))")
                    brokenItem.nextItem = nearest
                    return
                }

                print("healNextEdge(of: \(brokenItem.itemId.shortString)) "
                    + "NEAREST (itemId: \(nearest.itemId.shortString), gap: \(String(format: "%0.fs", gap)), "
                    + "previousItemId: \(nearest.previousItemId?.shortString ?? "nil"))")

            } else {
                print("healNextEdge(of: \(brokenItem.itemId.shortString)) "
                    + "NEAREST (itemId: \(nearest.itemId.shortString), gap: nil, "
                    + "previousItemId: \(nearest.previousItemId?.shortString ?? "nil"))")
            }
        }

        if let overlapper = store.item(
            where: """
            startDate < :endDate1 AND endDate > :endDate2 AND startDate IS NOT NULL AND endDate IS NOT NULL
            AND isVisit = :isVisit AND deleted = 0 AND itemId != :itemId
            """,
            arguments: ["endDate1": endDate, "endDate2": endDate, "isVisit": brokenItem is Visit,
                        "itemId": brokenItem.itemId.uuidString]),
            !overlapper.deleted && !overlapper.isMergeLocked
        {
            print("healNextEdge(of: \(brokenItem.itemId.shortString)) MERGED INTO OVERLAPPING ITEM")
            overlapper.add(brokenItem.samples)
            brokenItem.delete()
            return
        }

        print("healNextEdge(of: \(brokenItem.itemId.shortString)) FAILED")
    }

    private static func healPreviousEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store as? PersistentTimelineStore else { return }
        if brokenItem.isMergeLocked { return }
        guard brokenItem.hasBrokenPreviousItemEdge else { return }
        guard let startDate = brokenItem.startDate else { return }

        print("healPreviousEdge(of: \(brokenItem.itemId.shortString))")

        if let nearest = store.item(
            where: "endDate <= :startDate AND deleted = 0 AND itemId != :itemId ORDER BY ABS(strftime('%s', endDate) - :timestamp)",
            arguments: ["startDate": startDate, "itemId": brokenItem.itemId.uuidString,
                        "timestamp": startDate.timeIntervalSince1970]),
            !nearest.deleted && !nearest.isMergeLocked
        {
            if nearest.nextItemId == brokenItem.itemId {
                print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) NOT BROKEN")
                return
            }

            if let gap = nearest.timeInterval(from: brokenItem) {

                // nearest already has an edge connection?
                if let theirEdge = nearest.nextItem {

                    if let theirGap = nearest.timeInterval(from: theirEdge) {

                        // broken item's edge is closer than nearest's current edge? steal it
                        if abs(gap) < abs(theirGap) {
                            print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) HEALED: (\(nearest.itemId.shortString)) (my edge is closer)")
                            brokenItem.previousItem = nearest
                            return

                        } else {
                            print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) FAILED: (\(nearest.itemId.shortString)) (their edge is closer)")
                        }

                    } else {
                        print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) FAILED: (\(nearest.itemId.shortString)) (their edge has nil dateRange?)")
                    }

                } else { // they don't have an edge connection, so it's safe to connect
                    print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) HEALED: (\(nearest.itemId.shortString))")
                    brokenItem.previousItem = nearest
                    return
                }

                print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) "
                    + "NEAREST (itemId: \(nearest.itemId.shortString), gap: \(String(format: "%0.fs", gap)), "
                    + "nextItemId: \(nearest.nextItemId?.shortString ?? "nil"))")

            } else {
                print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) "
                    + "NEAREST (itemId: \(nearest.itemId.shortString), gap: nil, "
                    + "nextItemId: \(nearest.nextItemId?.shortString ?? "nil"))")
            }
        }

        if let overlapper = store.item(
            where: """
            startDate < :startDate1 AND endDate > :startDate2 AND startDate IS NOT NULL AND endDate IS NOT NULL
            AND isVisit = :isVisit AND deleted = 0 AND itemId != :itemId
            """,
            arguments: ["startDate1": startDate, "startDate2": startDate, "isVisit": brokenItem is Visit,
                        "itemId": brokenItem.itemId.uuidString]),
            !overlapper.deleted && !overlapper.isMergeLocked
        {
            print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) MERGED INTO OVERLAPPING ITEM")
            overlapper.add(brokenItem.samples)
            brokenItem.delete()
            return
        }

        print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) FAILED")
    }

    // MARK: - Data gap insertion

    public static func insertDataGapBetween(newer newerItem: TimelineItem, older olderItem: TimelineItem) {
        guard let store = newerItem.store else { return }
        store.process {
            guard !newerItem.isDataGap && !olderItem.isDataGap else { return }

            guard let gap = newerItem.timeInterval(from: olderItem), gap > 60 * 5 else { print("TOO CLOSE"); return }

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

    // MARK: - Database sanitising

    public static func sanitise(store: PersistentTimelineStore) {
        orphanSamplesFromDeadParents(in: store)
        adoptOrphanedSamples(in: store)
        detachDeadmenEdges(in: store)
    }

    private static func adoptOrphanedSamples(in store: PersistentTimelineStore) {
        store.process {
            let orphans = store.samples(where: "timelineItemId IS NULL AND deleted = 0 ORDER BY date DESC")

            if orphans.isEmpty { return }

            os_log("Found orphaned samples: %d", type: .debug, orphans.count)

            var newParents: [TimelineItem] = []

            for orphan in orphans where orphan.timelineItem == nil {
                if let item = store.item(where: "startDate <= ? AND endDate >= ? AND deleted = 0",
                                         arguments: [orphan.date, orphan.date]) {
                    os_log("ADOPTED AN ORPHAN (item: %@, sample: %@, date: %@)", type: .debug, item.itemId.shortString,
                           orphan.sampleId.shortString, String(describing: orphan.date))
                    item.add(orphan)

                } else { // create a new item for the orphan
                    if orphan.movingState == .stationary {
                        newParents.append(store.createVisit(from: orphan))
                    } else {
                        newParents.append(store.createPath(from: orphan))
                    }
                    os_log("CREATED NEW PARENT FOR ORPHAN (sample: %@, date: %@)", type: .debug,
                           orphan.sampleId.shortString, String(describing: orphan.date))
                }
            }

            store.save()

            if newParents.isEmpty { return }

            // clean up the new parents
            newParents.forEach {
                PersistentProcessor.healEdges(of: $0)
                TimelineProcessor.process(from: $0)
            }
        }
    }

    private static func orphanSamplesFromDeadParents(in store: PersistentTimelineStore) {
        store.process {
            let orphans = store.samples(for: """
                SELECT LocomotionSample.* FROM LocomotionSample
                    JOIN TimelineItem ON timelineItemId = TimelineItem.itemId
                WHERE TimelineItem.deleted = 1
                """)

            if orphans.isEmpty { return }

            print("Samples holding onto dead parents: \(orphans.count)")

            for orphan in orphans where orphan.timelineItemId != nil {
                print("Detaching an orphan from dead parent.")
                orphan.timelineItemId = nil
            }

            store.save()
        }
    }

    private static func detachDeadmenEdges(in store: PersistentTimelineStore) {
        store.process {
            let deadmen = store.items(where: "deleted = 1 AND (previousItemId IS NOT NULL OR nextItemId IS NOT NULL)")

            if deadmen.isEmpty { return }

            print("Deadmen to edge detach: \(deadmen.count)")

            for deadman in deadmen {
                print("Detaching edges of a deadman.")
                deadman.previousItemId = nil
                deadman.nextItemId = nil
            }

            store.save()
        }
    }

}
