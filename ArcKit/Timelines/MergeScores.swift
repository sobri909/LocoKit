//
//  MergeScores.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 15/12/16.
//  Copyright © 2016 Big Paua. All rights reserved.
//

import os.log
import Foundation

enum ConsumptionScore: Int {
    case perfect = 5
    case high = 4
    case medium = 3
    case low = 2
    case veryLow = 1
    case impossible = 0
}

class MergeScores {
    
    static func consumptionScoreFor(_ consumer: TimelineItem, toConsume consumee: TimelineItem) -> ConsumptionScore {
        
        // if consumee has zero samples, call it a perfect merge
        if consumee.samples.isEmpty {
            return .perfect
        }
        
        // if consumer has zero samples, call it impossible
        if consumer.samples.isEmpty {
            return .impossible
        }
        
        // test for impossible separation distance
        guard let separation = consumer.distance(from: consumee) else {
            return .impossible
        }
        if separation > consumer.maximumMergeableDistance(from: consumee) {
            return .impossible
        }

        if let visit = consumer as? Visit {
            return consumptionScoreFor(visit: visit, toConsume: consumee)
        }

        if let path = consumer as? Path {
            return consumptionScoreFor(path: path, toConsume: consumee)
        }

        return .impossible
    }
}

extension MergeScores {

    // MARK: PATH <- SOMETHING
    fileprivate static func consumptionScoreFor(path consumer: Path, toConsume consumee: TimelineItem) -> ConsumptionScore {
        
        // consumer is invalid
        if consumer.isInvalid {
            
            // invalid <- invalid
            if consumee.isInvalid {
                return .veryLow
            }
            
            // invalid <- valid
            return .impossible
        }

        if let visit = consumee as? Visit {
            return consumptionScoreFor(path: consumer, toConsumeVisit: visit)
        }

        if let path = consumee as? Path {
            return consumptionScoreFor(path: consumer, toConsumePath: path)
        }

        return .impossible
    }
    
    // MARK: PATH <- VISIT
    fileprivate static func consumptionScoreFor(path consumer: Path, toConsumeVisit consumee: Visit) -> ConsumptionScore {

        // can't consume a keeper visit
        if consumee.isWorthKeeping {
            return .impossible
        }

        // consumer is keeper
        if consumer.isWorthKeeping {
            
            // keeper <- invalid
            if consumee.isInvalid {
                return .medium
            }
            
            // keeper  <- valid
            return .low
        }
        
        // consumer is valid
        if consumer.isValid {
            
            // valid <- invalid
            if consumee.isInvalid {
                return .low
            }
            
            // valid <- valid
            return .veryLow
        }
        
        // consumer is invalid (actually already dealt with in previous method)
        return .impossible
    }

    // MARK: PATH <- PATH
    fileprivate static func consumptionScoreFor(path consumer: Path, toConsumePath consumee: Path) -> ConsumptionScore {

        // let's just call them all medium for now (they've already passed the separation distance test, by this stage)
        return .medium

        // TODO: hook back up the activity type based path-path merge rules

//        let consumerType = consumer.primaryMovingActivityType ?? consumer.primaryActivityType
//        let consumeeType = consumee.activityType

        // perfect type match
//        if consumeeType == consumerType {
//            return .perfect
//        }

        // can't consume a keeper path
//        if consumee.isWorthKeeping {
//            return .impossible
//        }

        // a path with nil type can't consume shit
//        guard let scoringType = consumerType else {
//            return .impossible
//        }
//
//        guard let classifierResult = consumee.classifierResults?.first(where: { $0.name == scoringType }) else {
//            return .impossible
//        }
//
//        // consumee's type score for consumer's primary type, as a usable Int
//        let scoreDoubleBig = floor(classifierResult.score * 1000)
//        let typeScore = Int(scoreDoubleBig)
//
//        log("consumer: \(consumer.typeDescription) consumee: \(consumee.typeDescription) typeScore: \(typeScore)")
//
//        switch typeScore {
//        case 75...Int.max:
//            return .perfect
//        case 50...75:
//            return .high
//        case 25...50:
//            return .medium
//        case 10...25:
//            return .low
//        default:
//            return .veryLow
//        }
//
//        return .impossible
    }
}

extension MergeScores {
    
    // MARK: VISIT <- SOMETHING
    fileprivate static func consumptionScoreFor(visit consumer: Visit, toConsume consumee: TimelineItem) -> ConsumptionScore {
        if let visit = consumee as? Visit {
            return consumptionScoreFor(visit: consumer, toConsumeVisit: visit)
        }

        if let path = consumee as? Path {
            return consumptionScoreFor(visit: consumer, toConsumePath: path)
        }
        
        return .impossible
    }
    
    // MARK: VISIT <- VISIT
    fileprivate static func consumptionScoreFor(visit consumer: Visit, toConsumeVisit consumee: Visit) -> ConsumptionScore {
        
        // overlapping visits
        if consumer.overlaps(consumee) {
            return consumer.duration > consumee.duration ? .perfect : .high
        }
        
        return .impossible
    }
    
    // MARK: VISIT <- PATH
    fileprivate static func consumptionScoreFor(visit consumer: Visit, toConsumePath consumee: Path) -> ConsumptionScore {

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
