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
        if betweener?.isMergeLocked == true { return .impossible }
        if keeper.deleted || deadman.deleted { fatalError("TRYING TO MERGE DELETED ITEMS") }
        return self.keeper.scoreForConsuming(item: self.deadman)
    }()

    init(keeper: TimelineItem, betweener: TimelineItem? = nil, deadman: TimelineItem) {
        guard let store = keeper.store else { fatalError("NO STORE") }

        guard let keeper = keeper.currentInstance else { fatalError("NO KEEPER") }
        guard let deadman = deadman.currentInstance else { fatalError("NO DEADMAN") }

        store.retain([keeper, deadman])
        self.keeper = keeper
        self.deadman = deadman

        if let betweener = betweener?.currentInstance {
            store.retain(betweener)
            self.betweener = betweener
        }
    }
    
    deinit {
        guard let store = keeper.store else { fatalError("NO STORE") }
        store.release(keeper)
        store.release(deadman)
        if let betweener = betweener { store.release(betweener) }
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
