//
// Created by Matt Greenfield on 25/05/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

import os.log

typealias MergeScore = ConsumptionScore

public class Merge: CustomStringConvertible {

    var keeper: TimelineItem
    var betweener: TimelineItem?
    var deadman: TimelineItem

    lazy var score: MergeScore = {
        // if there's a locked betweener, the merge is invalid
        if betweener?.isMergeLocked == true { return .impossible }
        return self.keeper.scoreForConsuming(item: self.deadman)
    }()

    init(keeper: TimelineItem, deadman: TimelineItem) {
        self.keeper = keeper
        self.deadman = deadman
    }
    
    init(keeper: TimelineItem, betweener: TimelineItem, deadman: TimelineItem) {
        self.keeper = keeper
        self.betweener = betweener
        self.deadman = deadman
    }

    func doIt() -> (kept: TimelineItem, killed: [TimelineItem]) {
        merge(deadman, into: keeper)
        
        if let betweener = betweener {
            return (kept: keeper, killed: [deadman, betweener])
        } else {
            return (kept: keeper, killed: [deadman])
        }
    }

    private func merge(_ deadman: TimelineItem, into keeper: TimelineItem) {

        // deadman is previous
        if keeper.previousItem == deadman || (betweener != nil && keeper.previousItem == betweener) {
            keeper.previousItem = deadman.previousItem

        } else { // keeper is previous
            keeper.nextItem = deadman.nextItem
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

    public var description: String {
        if let betweener = betweener {
            return String(format: "score: %d (%@) <- (%@) <- (%@)", score.rawValue, String(describing: keeper),
                          String(describing: betweener), String(describing: deadman))
        } else {
            return String(format: "score: %d (%@) <- (%@)", score.rawValue, String(describing: keeper),
                          String(describing: deadman))
        }
    }
}
