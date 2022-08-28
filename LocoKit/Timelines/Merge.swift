//
// Created by Matt Greenfield on 25/05/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

import Foundation

public extension NSNotification.Name {
    static let mergedTimelineItems = Notification.Name("mergedTimelineItems")
}

typealias MergeScore = ConsumptionScore
public typealias MergeResult = (kept: TimelineItem, killed: [TimelineItem])

internal class Merge: Hashable, CustomStringConvertible {

    var keeper: TimelineItem
    var betweener: TimelineItem?
    var deadman: TimelineItem

    var isValid: Bool {
        if keeper.deleted || deadman.deleted || betweener?.deleted == true { return false }
        if keeper.invalidated || deadman.invalidated || betweener?.invalidated == true { return false }

        // check for dupes (which should be impossible, but weird stuff happens)
        var itemIds: Set<UUID> = [keeper.itemId, deadman.itemId]
        if let betweener = betweener {
            itemIds.insert(betweener.itemId)
            if itemIds.count != 3 { return false }
        } else {
            if itemIds.count != 2 { return false }
        }

        if let betweener = betweener {
            // keeper -> betweener -> deadman
            if keeper.nextItem == betweener, betweener.nextItem == deadman { return true }
            // deadman -> betweener -> keeper
            if deadman.nextItem == betweener, betweener.nextItem == keeper { return true }
        } else {
            // keeper -> deadman
            if keeper.nextItem == deadman { return true }
            // deadman -> keeper
            if deadman.nextItem == keeper { return true }
        }

        return false
    }

    lazy var score: MergeScore = {
        if keeper.isMergeLocked || deadman.isMergeLocked || betweener?.isMergeLocked == true { return .impossible }
        guard isValid else { return .impossible }
        return self.keeper.scoreForConsuming(item: self.deadman)
    }()

    init(keeper: TimelineItem, betweener: TimelineItem? = nil, deadman: TimelineItem) {
        self.keeper = keeper
        self.deadman = deadman
        if let betweener = betweener {
            self.betweener = betweener
        }
    }

    @discardableResult func doIt() -> MergeResult {
        let description = String(describing: self)
        if TimelineProcessor.debugLogging { logger.debug("Doing:\n\(description)") }

        merge(deadman, into: keeper)

        let results: MergeResult
        if let betweener = betweener {
            results = (kept: keeper, killed: [deadman, betweener])
        } else {
            results = (kept: keeper, killed: [deadman])
        }

        // notify listeners
        let note = Notification(name: .mergedTimelineItems, object: self,
                                userInfo: ["description": description, "results": results])
        NotificationCenter.default.post(note)

        return results
    }

    private func merge(_ deadman: TimelineItem, into keeper: TimelineItem) {
        guard isValid else { logger.error("Invalid merge"); return }
        
        // deadman is previous
        if keeper.previousItem == deadman || (betweener != nil && keeper.previousItem == betweener) {
            keeper.previousItem = deadman.previousItem

            // deadman is next
        } else if keeper.nextItem == deadman || (betweener != nil && keeper.nextItem == betweener) {
            keeper.nextItem = deadman.nextItem

        } else {
            return
        }

        // deal with a betweener
        if let betweener = betweener {
            keeper.willConsume(item: betweener)
            keeper.add(betweener.samples.filter { !$0.disabled })

            if betweener.samples.filter({ $0.disabled }).isEmpty {
                betweener.delete()
            } else {
                betweener.disabled = true
                betweener.breakEdges()
            }
        }

        // deal with the deadman
        keeper.willConsume(item: deadman)
        keeper.add(deadman.samples.filter { !$0.disabled })

        if deadman.samples.filter({ $0.disabled }).isEmpty {
            deadman.delete()
        } else {
            deadman.disabled = true
            deadman.breakEdges()
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(keeper)
        hasher.combine(deadman)
        if let betweener = betweener {
            hasher.combine(betweener)
        }
        if let startDate = keeper.startDate {
            hasher.combine(startDate)
        }
    }

    static func == (lhs: Merge, rhs: Merge) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }

    // MARK: - CustomStringConvertible

    var description: String {
        if let betweener = betweener {
            return String(format: "score: %d (%@) <- (%@) <- (%@)", score.rawValue, String(describing: keeper),
                          String(describing: betweener), String(describing: deadman))
        } else {
            return String(format: "score: %d (%@) <- (%@)", score.rawValue, String(describing: keeper),
                          String(describing: deadman))
        }
    }
    
}
