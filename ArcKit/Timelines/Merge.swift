//
// Created by Matt Greenfield on 25/05/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

typealias MergeScore = ConsumptionScore

public class Merge {

    var keeper: TimelineItem
    var betweener: TimelineItem?
    var deadman: TimelineItem

    lazy var score: MergeScore = {
        return MergeScores.consumptionScoreFor(self.keeper, toConsume: self.deadman)
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

    fileprivate func merge(_ deadman: TimelineItem, into keeper: TimelineItem) {

        // deadman is previous
        if keeper.previousItem == deadman || (betweener != nil && keeper.previousItem == betweener) {
            keeper.previousItem = deadman.previousItem
            
        } else { // keeper is previous
            keeper.nextItem = deadman.nextItem
        }

        // reassign the deadman's samples
        keeper.add(deadman.samples)
        
        // deal with a betweener
        if let betweener = betweener {
           
            // reassign the betweener's samples
            keeper.add(betweener.samples)
        }
    }

}

extension Merge: CustomStringConvertible {

    public var description: String {
        if let betweener = betweener {
            return String(format: "\nscore: %d (%@) <- (%@) <- (%@)", score.rawValue, String(describing: keeper),
                          String(describing: betweener), String(describing: deadman))
        } else {
            return String(format: "\nscore: %d (%@) <- (%@)", score.rawValue, String(describing: keeper),
                          String(describing: deadman))
        }
    }

}
