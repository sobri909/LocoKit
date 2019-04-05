//
//  MergeScores.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 15/12/16.
//  Copyright © 2016 Big Paua. All rights reserved.
//

import os.log
import Foundation

public enum ConsumptionScore: Int {
    case perfect = 5
    case high = 4
    case medium = 3
    case low = 2
    case veryLow = 1
    case impossible = 0
}

class MergeScores {

    // MARK: - SOMETHING <- SOMETHING
    static func consumptionScoreFor(_ consumer: TimelineItem, toConsume consumee: TimelineItem) -> ConsumptionScore {

        // can't do anything with merge locked items
        if consumer.isMergeLocked || consumee.isMergeLocked { return .impossible }

        // deadmen can't consume anyone
        if consumer.deleted { return .impossible }
        
        // if consumee has zero samples, call it a perfect merge
        if consumee.samples.isEmpty { return .perfect }
        
        // if consumer has zero samples, call it impossible
        if consumer.samples.isEmpty { return .impossible }

        // data gaps can only consume data gaps
        if consumer.isDataGap { return consumee.isDataGap ? .perfect : .impossible }

        // anyone can consume an invalid data gap, but no one can consume a valid data gap
        if consumee.isDataGap { return consumee.isInvalid ? .medium : .impossible }

        // nolos can only consume nolos
        if consumer.isNolo { return consumee.isNolo ? .perfect : .impossible }

        // anyone can consume an invalid nolo
        if consumee.isNolo && consumee.isInvalid { return .medium }

        // test for impossible separation distance
        guard consumer.withinMergeableDistance(from: consumee) else { return .impossible }

        // visit <- something
        if let visit = consumer as? Visit { return consumptionScoreFor(visit: visit, toConsume: consumee) }

        // path <- something
        if let path = consumer as? Path { return consumptionScoreFor(path: path, toConsume: consumee) }

        return .impossible
    }

    // MARK: - PATH <- SOMETHING
    private static func consumptionScoreFor(path consumer: Path, toConsume consumee: TimelineItem) -> ConsumptionScore {

        // consumer is invalid
        if consumer.isInvalid {
            
            // invalid <- invalid
            if consumee.isInvalid { return .veryLow }
            
            // invalid <- valid
            return .impossible
        }

        // path <- visit
        if let visit = consumee as? Visit { return consumptionScoreFor(path: consumer, toConsumeVisit: visit) }

        // path <- vpath
        if let path = consumee as? Path { return consumptionScoreFor(path: consumer, toConsumePath: path) }

        return .impossible
    }
    
    // MARK: - PATH <- VISIT
    private static func consumptionScoreFor(path consumer: Path, toConsumeVisit consumee: Visit) -> ConsumptionScore {

        // can't consume a keeper visit
        if consumee.isWorthKeeping { return .impossible }

        // consumer is keeper
        if consumer.isWorthKeeping {
            
            // keeper <- invalid
            if consumee.isInvalid { return .medium }
            
            // keeper  <- valid
            return .low
        }
        
        // consumer is valid
        if consumer.isValid {
            
            // valid <- invalid
            if consumee.isInvalid { return .low }
            
            // valid <- valid
            return .veryLow
        }
        
        // consumer is invalid (actually already dealt with in previous method)
        return .impossible
    }

    // MARK: - PATH <- PATH
    private static func consumptionScoreFor(path consumer: Path, toConsumePath consumee: Path) -> ConsumptionScore {
        let consumerType = consumer.modeMovingActivityType ?? consumer.modeActivityType
        let consumeeType = consumee.modeMovingActivityType ?? consumee.modeActivityType

        // no types means it's a random guess
        if consumerType == nil && consumeeType == nil { return .medium }

        // perfect type match
        if consumeeType == consumerType { return .perfect }

        // can't consume a keeper path
        if consumee.isWorthKeeping { return .impossible }

        // a path with nil type can't consume anyone
        guard let scoringType = consumerType else { return .impossible }

        guard let typeResult = consumee.classifierResults?.first(where: { $0.name == scoringType }) else {
            return .impossible
        }

        // consumee's type score for consumer's type, as a usable Int
        let typeScore = Int(floor(typeResult.score * 1000))

        switch typeScore {
        case 75...Int.max:
            return .perfect
        case 50...75:
            return .high
        case 25...50:
            return .medium
        case 10...25:
            return .low
        default:
            return .veryLow
        }
    }

    // MARK: - VISIT <- SOMETHING
    private static func consumptionScoreFor(visit consumer: Visit, toConsume consumee: TimelineItem) -> ConsumptionScore {

        // visit <- visit
        if let visit = consumee as? Visit { return consumptionScoreFor(visit: consumer, toConsumeVisit: visit) }

        // visit <- path
        if let path = consumee as? Path { return consumptionScoreFor(visit: consumer, toConsumePath: path) }
        
        return .impossible
    }
    
    // MARK: - VISIT <- VISIT
    private static func consumptionScoreFor(visit consumer: Visit, toConsumeVisit consumee: Visit) -> ConsumptionScore {
        
        // overlapping visits
        if consumer.overlaps(consumee) {
            return consumer.duration > consumee.duration ? .perfect : .high
        }
        
        return .impossible
    }
    
    // MARK: - VISIT <- PATH
    private static func consumptionScoreFor(visit consumer: Visit, toConsumePath consumee: Path) -> ConsumptionScore {

        // percentage of path inside the visit
        let pctInsideScore = Int(floor(consumee.percentInside(consumer) * 10))
        
        // valid / keeper visit <- invalid path
        if consumer.isValid && consumee.isInvalid {
            switch pctInsideScore {
            case 10: // 100%
                return .low
            default:
                return .veryLow
            }
        }
        
        return .impossible
    }

}
