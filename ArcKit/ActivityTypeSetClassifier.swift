//
//  ActivityTypeSetClassifier.swift
//  ArcKit
//
//  Created by Matt Greenfield on 14/12/16.
//  Copyright © 2016 Big Paua. All rights reserved.
//

import Upsurge
import CoreLocation

public class ActivityTypeSetClassifier {

    static func classify(_ timelineItem: TimelineItem) -> ClassifierResults? {
        guard let results = classify(timelineItem.samples) else {
            return nil
        }

        if timelineItem.radius3sd < Visit.maximumRadius {
            return results
        }

        /** zero out the stationary score for items with radius larger than max visit radius **/

        guard let stationary = results[.stationary] else {
            return results
        }

        var resultsArray = results.array
        resultsArray.remove(stationary)
        resultsArray.append(ClassifierResultItem(name: .stationary, score: 0,
                                                 modelAccuracyScore: stationary.modelAccuracyScore))
        
        return ClassifierResults(results: resultsArray, moreComing: results.moreComing)
    }
    
    static func classify(_ samples: [LocomotionSample]) -> ClassifierResults? {
        if samples.isEmpty {
            return nil
        }

        var allScores: [ActivityTypeName: ValueArray<Double>] = [:]
        var allAccuracies: [ActivityTypeName: ValueArray<Double>] = [:]
        for typeName in ActivityTypeName.allTypes {
            allScores[typeName] = ValueArray(capacity: samples.count)
            allAccuracies[typeName] = ValueArray(capacity: samples.count)
        }
        
        var moreComing = false

        for sample in samples {
            guard let results = sample.classifierResults else {
                continue
            }
            
            if results.moreComing {
                // TODO: should attempt to get (and set) updated classifier results for the sample here
                moreComing = true
            }
            
            for typeName in ActivityTypeName.allTypes {
                if let resultRow = results[typeName] {
                    allScores[resultRow.name]!.append(resultRow.score)
                    allAccuracies[resultRow.name]!.append(resultRow.modelAccuracyScore ?? 0)
                    
                } else {
                    allScores[typeName]!.append(0)
                    allAccuracies[typeName]!.append(0)
                }
            }
        }
        
        var finalResults: [ClassifierResultItem] = []
        
        for typeName in ActivityTypeName.allTypes {
            var finalScore = 0.0
            if let scores = allScores[typeName], !scores.isEmpty {
                finalScore = mean(scores)
            }
            
            var finalAccuracy = 0.0
            if let accuracies = allAccuracies[typeName], !accuracies.isEmpty {
                finalAccuracy = mean(accuracies)
            }
            
            finalResults.append(ClassifierResultItem(name: typeName, score: finalScore,
                                                     modelAccuracyScore: finalAccuracy))
        }
        
        return ClassifierResults(results: finalResults, moreComing: moreComing)
    }
}
