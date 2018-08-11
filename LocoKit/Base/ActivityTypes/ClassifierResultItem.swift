//
//  ClassifierResultItem.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 13/10/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

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

    /**
     Result items are considered equal if they have matching `name` values.
     */
    public static func ==(lhs: ClassifierResultItem, rhs: ClassifierResultItem) -> Bool {
        return lhs.name == rhs.name
    }

}
