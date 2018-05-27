//
//  PersistentProcessor.swift
//  LocoKit
//
//  Created by Matt Greenfield on 26/5/18.
//

public class PersistentProcessor {

    // MARK: - Brexits

    public static func extractItem(for segment: ItemSegment, in store: PersistentTimelineStore, completion: ((TimelineItem?) -> Void)? = nil) {
        store.process {
            guard let segmentRange = segment.dateRange else {
                completion?(nil)
                return
            }

            // find the overlapping items
            let overlappers = store.items(where: "deleted = 0 AND endDate > ? AND startDate < ? ORDER BY startDate",
                                          arguments: [segmentRange.start, segmentRange.end])

            var modifiedItems: [TimelineItem] = []
            var samplesToSteal: [LocomotionSample] = []

            // find existing samples that fall inside the segment's range
            for overlapper in overlappers {
                var lostPrevEdge = false, lostNextEdge = false

                for sample in overlapper.samples {

                    // sample is inside the segment's range?
                    if segmentRange.contains(sample.date) {
                        if sample == overlapper.samples.first { lostPrevEdge = true }
                        if sample == overlapper.samples.last { lostNextEdge = true }
                        print("Moving sample from overlapper to inserted item")
                        samplesToSteal.append(sample)
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

                    // if only extracted from middle, split the item in two
                    if !lostPrevEdge && !lostNextEdge && !samplesToSteal.isEmpty {
                        // TODO: split the item in two
                        print("TODO: split the item in two")
                    }
                }
            }

            // create the new item
            let newItem = createItem(from: segment, in: store)

            // add the stolen samples to the new item
            newItem.add(samplesToSteal)

            // attempt to connect up the new item
            healEdges(of: newItem)

            // edge heal all modified items, or delete if empty
            for modifiedItem in modifiedItems {
                if modifiedItem.samples.isEmpty {
                    modifiedItem.delete()
                } else {
                    healEdges(of: modifiedItem)
                }
            }

            // TODO: should edge healing do the path extraction between visits? if not, then who?

            // complete with the new item
            completion?(newItem)
        }
    }

    private static func createItem(from segment: ItemSegment, in store: PersistentTimelineStore) -> TimelineItem {
        return segment.activityType == .stationary
            ? store.createVisit(from: segment.samples)
            : store.createPath(from: segment.samples)
    }

    // MARK: - Item edge healing

    public static func healEdges(of items: [TimelineItem]) {
        items.forEach { healEdges(of: $0) }
    }

    public static func healEdges(of brokenItem: TimelineItem) {
        if brokenItem.isMergeLocked { return }
        if !brokenItem.hasBrokenEdges { return }

        print("healEdges(of: \(brokenItem.itemId.shortString))")

        brokenItem.store?.process {
            self.healNextEdge(of: brokenItem)
            self.healPreviousEdge(of: brokenItem)
        }
    }

    private static func healNextEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store as? PersistentTimelineStore else { return }
        if brokenItem.isMergeLocked { return }
        guard brokenItem.hasBrokenNextItemEdge else { return }
        guard let endDate = brokenItem.endDate else { return }

        if let nearest = store.item(
            where: "deleted = 0 AND itemId != ? AND startDate >= ? ORDER BY ABS(strftime('%s', startDate) - ?)",
            arguments: [brokenItem.itemId.uuidString, endDate, endDate.timeIntervalSince1970]), !nearest.deleted
        {
            print("NEAREST NEXT (gap: \(String(format: "%.0fs", nearest.timeInterval(from: brokenItem)!)), "
                + "hasPrevious: \(nearest.previousItemId?.shortString ?? "false"))")

            if nearest.previousItem == nil, let gap = nearest.timeInterval(from: brokenItem), gap < 60 * 5 {
                print("HEALED NEXTITEM")
                brokenItem.nextItem = nearest
                return
            }
        }

        if let overlapper = store.item(
            where: "deleted = 0 AND itemId != ? AND startDate IS NOT NULL AND endDate IS NOT NULL AND startDate < ? AND endDate > ?",
            arguments: [brokenItem.itemId.uuidString, endDate, endDate]), !overlapper.deleted
        {
            print("MERGED INTO OVERLAPPING ITEM")
            overlapper.add(brokenItem.samples)
            brokenItem.delete()
            return
        }

        print("COULDN'T HEAL NEXTITEM EDGE")
    }

    private static func healPreviousEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store as? PersistentTimelineStore else { return }
        if brokenItem.isMergeLocked { return }
        guard brokenItem.hasBrokenPreviousItemEdge else { return }
        guard let startDate = brokenItem.startDate else { return }

        if let nearest = store.item(
            where: "deleted = 0 AND itemId != ? AND endDate <= ? ORDER BY ABS(strftime('%s', endDate) - ?)",
            arguments: [brokenItem.itemId.uuidString, startDate, startDate.timeIntervalSince1970]), !nearest.deleted
        {
            print("NEAREST PREVIOUS (gap: \(String(format: "%0.fs", nearest.timeInterval(from: brokenItem)!)), "
                + "hasNext: \(nearest.nextItemId?.shortString ?? "false"))")

            if nearest.nextItem == nil, let gap = nearest.timeInterval(from: brokenItem), gap < 60 * 5 {
                print("HEALED PREVIOUSITEM")
                brokenItem.previousItem = nearest
                return
            }
        }

        if let overlapper = store.item(
            where: "deleted = 0 AND itemId != ? AND startDate IS NOT NULL AND endDate IS NOT NULL AND startDate < ? AND endDate > ?",
            arguments: [brokenItem.itemId.uuidString, startDate, startDate]), !overlapper.deleted
        {
            print("MERGED INTO OVERLAPPING ITEM")
            overlapper.add(brokenItem.samples)
            brokenItem.delete()
            return
        }

        print("COULDN'T HEAL PREVIOUSITEM EDGE")
    }

}
