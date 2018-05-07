//
// Created by Matt Greenfield on 25/05/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

import os.log

public extension NSNotification.Name {
    public static let mergedTimelineItems = Notification.Name("mergedTimelineItems")
}

typealias MergeScore = ConsumptionScore
public typealias MergeResult = (kept: TimelineItem, killed: [TimelineItem])

internal class Merge: CustomStringConvertible {

    var keeper: TimelineItem
    var betweener: TimelineItem?
    var deadman: TimelineItem

    lazy var score: MergeScore = {
        if keeper.isMergeLocked || deadman.isMergeLocked || betweener?.isMergeLocked == true { return .impossible }
        if keeper.deleted || deadman.deleted || betweener?.deleted == true { return .impossible }
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
        os_log("Doing:\n%@", type: .debug, description)

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
        
        // deadman is previous
        if keeper.previousItem == deadman || (betweener != nil && keeper.previousItem == betweener) {
            keeper.previousItem = deadman.previousItem

            // deadman is next
        } else if keeper.nextItem == deadman || (betweener != nil && keeper.nextItem == betweener) {
            keeper.nextItem = deadman.nextItem

        } else {
            fatalError("BROKEN MERGE")
        }

        // deal with a betweener
        if let betweener = betweener {
            keeper.add(betweener.samples)
            betweener.deleted = true
        }

        // deal with the deadman
        keeper.add(deadman.samples)
        deadman.deleted = true
    }

    // MARK: CustomStringConvertible

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
