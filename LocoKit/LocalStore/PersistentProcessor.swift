//
//  PersistentProcessor.swift
//  LocoKit
//
//  Created by Matt Greenfield on 26/5/18.
//

public class PersistentProcessor {

    // MARK: - ItemSegment brexiting

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

                // if only extracted from middle, split the item in two
                if !lostPrevEdge && !lostNextEdge && !samplesToSteal.isEmpty {
                    // TODO: split the item in two
                    print("TODO: split the item in two")
                }
            }

            // create the new item
            let newItem = createItem(from: segment, in: store)

            // add the stolen samples to the new item
            if !samplesToSteal.isEmpty {
                print("Moving \(samplesToSteal.count) samples from overlappers to inserted item")
                newItem.add(samplesToSteal)
            }

            // delete any newly empty items
            for modifiedItem in modifiedItems where modifiedItem.samples.isEmpty {
                modifiedItem.delete()
            }

            // attempt to connect up the new item
            healEdges(of: newItem)

            // edge heal all modified items, or delete if empty
            for modifiedItem in modifiedItems {
                healEdges(of: modifiedItem)
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
        brokenItem.store?.process { self.healPreviousEdge(of: brokenItem) }
        brokenItem.store?.process { self.healNextEdge(of: brokenItem) }
    }

    private static func healNextEdge(of brokenItem: TimelineItem) {
        guard let store = brokenItem.store as? PersistentTimelineStore else { return }
        if brokenItem.isMergeLocked { return }
        guard brokenItem.hasBrokenNextItemEdge else { return }
        guard let endDate = brokenItem.endDate else { return }

        print("healNextEdge(of: \(brokenItem.itemId.shortString))")

        if let nearest = store.item(
            where: "deleted = 0 AND itemId != ? AND startDate >= ? ORDER BY ABS(strftime('%s', startDate) - ?)",
            arguments: [brokenItem.itemId.uuidString, endDate, endDate.timeIntervalSince1970]), !nearest.deleted
        {
            if nearest.previousItemId == brokenItem.itemId {
                print("healNextEdge(of: \(brokenItem.itemId.shortString)) NOT BROKEN")
                return
            }

            if let gap = nearest.timeInterval(from: brokenItem) {

                // nearest already has an edge connection?
                if let theirEdge = nearest.previousItem {

                    // broken item's edge is closer than nearest's current edge? steal it
                    if let theirGap = nearest.timeInterval(from: theirEdge), abs(gap) < abs(theirGap) {
                        print("healNextEdge(of: \(brokenItem.itemId.shortString)) HEALED: (\(nearest.itemId.shortString)) (my edge is closer)")
                        brokenItem.nextItem = nearest
                        return
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
            where: "deleted = 0 AND itemId != ? AND isVisit = ? AND startDate IS NOT NULL AND endDate IS NOT NULL AND startDate < ? AND endDate > ?",
            arguments: [brokenItem.itemId.uuidString, brokenItem is Visit, endDate, endDate]), !overlapper.deleted
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
            where: "deleted = 0 AND itemId != ? AND endDate <= ? ORDER BY ABS(strftime('%s', endDate) - ?)",
            arguments: [brokenItem.itemId.uuidString, startDate, startDate.timeIntervalSince1970]), !nearest.deleted
        {
            if nearest.nextItemId == brokenItem.itemId {
                print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) NOT BROKEN")
                return
            }

            if let gap = nearest.timeInterval(from: brokenItem) {

                // nearest already has an edge connection?
                if let theirEdge = nearest.nextItem {

                    // broken item's edge is closer than nearest's current edge? steal it
                    if let theirGap = nearest.timeInterval(from: theirEdge), abs(gap) < abs(theirGap) {
                        print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) HEALED: (\(nearest.itemId.shortString)) (my edge is closer)")
                        brokenItem.previousItem = nearest
                        return
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
            where: "deleted = 0 AND itemId != ? AND isVisit = ? AND startDate IS NOT NULL AND endDate IS NOT NULL AND startDate < ? AND endDate > ?",
            arguments: [brokenItem.itemId.uuidString, brokenItem is Visit, startDate, startDate]), !overlapper.deleted
        {
            print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) MERGED INTO OVERLAPPING ITEM")
            overlapper.add(brokenItem.samples)
            brokenItem.delete()
            return
        }

        print("healPreviousEdge(of: \(brokenItem.itemId.shortString)) FAILED")
    }

}
