//
// Created by Matt Greenfield on 25/05/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

import os.log

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
        if keeper.isMergeLocked || deadman.isMergeLocked || betweener?.isMergeLocked == true { return false }
        if keeper.deleted || deadman.deleted || betweener?.deleted == true { return false }
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
        if TimelineProcessor.debugLogging { os_log("Doing:\n%@", type: .debug, description) }

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
        guard isValid else { os_log("Invalid merge", type: .error); return }
        
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
            keeper.add(betweener.samples)
            betweener.delete()
        }

        // deal with the deadman
        keeper.willConsume(item: deadman)
        keeper.add(deadman.samples)
        deadman.delete()
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
