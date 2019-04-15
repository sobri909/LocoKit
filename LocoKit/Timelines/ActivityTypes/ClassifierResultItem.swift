//
//  ClassifierResultItem.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 13/10/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

public enum ClassifierResultScoreGroup: Int {
    case perfect = 5
    case veryGood = 4
    case good = 3
    case bad = 2
    case veryBad = 1
    case terrible = 0
}

/**
 An individual result row in a `ClassifierResults` instance, for a single activity type.
 */
public struct ClassifierResultItem: Equatable {

    /**
     The activity type name for the result.
     */
    public let name: ActivityTypeName

    /**
     The match probability score for the result, in the range of 0.0 to 1.0 (0% match to 100% match).
     */
    public let score: Double

    public let modelAccuracyScore: Double?

    public init(name: ActivityTypeName, score: Double, modelAccuracyScore: Double? = nil) {
        self.name = name
        self.score = score
        self.modelAccuracyScore = modelAccuracyScore
    }

    public func normalisedScore(in results: ClassifierResults) -> Double {
        let scoresTotal = results.scoresTotal
        guard scoresTotal > 0 else { return 0 }
        return score / scoresTotal
    }

    public func normalisedScoreGroup(in results: ClassifierResults) -> ClassifierResultScoreGroup {
        let normalisedScore = self.normalisedScore(in: results)
        switch Int(round(normalisedScore * 100)) {
        case 100: return .perfect
        case 80...100: return .veryGood
        case 50...80: return .good
        case 20...50: return .bad
        case 1...20: return .veryBad
        default: return .terrible
        }
    }

    /**
     Result items are considered equal if they have matching `name` values.
     */
    public static func ==(lhs: ClassifierResultItem, rhs: ClassifierResultItem) -> Bool {
        return lhs.name == rhs.name
    }

}
