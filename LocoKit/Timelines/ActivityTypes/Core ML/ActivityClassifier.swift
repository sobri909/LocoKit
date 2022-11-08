//
//  CoreMLClassifier.swift
//  
//
//  Created by Matt Greenfield on 2/9/22.
//

import Foundation
import CoreLocation
import TabularData
import CreateML
import CoreML
import Upsurge
import BackgroundTasks

public class ActivityClassifier: MLCompositeClassifier {

    public static var highlander = ActivityClassifier()

    private var discreteClassifiers: [Int: any DiscreteClassifier] = [:] // index = depth

    private let mutex = PThreadMutex(type: .recursive)

    // MARK: - MLCompositeClassifier

    public func canClassify(_ coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        if let coordinate { mutex.sync { updateDiscreteClassifiers(for: coordinate) } }
        return !discreteClassifiers.isEmpty
    }

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults? {

        // highest priorty first (ie D2 first)
        let classifiers = discreteClassifiers.sorted { $0.key > $1.key }.map { $0.value }

        var combinedResults: ClassifierResults?
        var remainingWeight = 1.0

        for classifier in classifiers {
            let results = classifier.classify(classifiable, previousResults: previousResults)

            if combinedResults == nil {
                combinedResults = results
                remainingWeight -= classifier.completenessScore
                if remainingWeight <= 0 { break } else { continue }
            }

            // if it's the last classifier treat it as 1.0 completeness, to make the weights add up to 1
            var completeness = classifier.completenessScore
            if classifier.id == classifiers.last?.id {
                completeness = 1.0
            }

            // merge in the results
            let weight = remainingWeight * completeness
            combinedResults = combinedResults?.merging(results, withWeight: weight)

            remainingWeight -= weight

            if remainingWeight <= 0 { break }
        }

        return combinedResults
    }

    public func classify(_ samples: [ActivityTypeClassifiable], timeout: TimeInterval? = nil) -> ClassifierResults? {
        if samples.isEmpty { return nil }

        let start = Date()

        // highest priorty first (ie D2 first)
        let classifiers = discreteClassifiers.sorted { $0.key > $1.key }.map { $0.value }

        var combinedResults: ClassifierResults?
        var remainingWeight = 1.0

        for classifier in classifiers {
            if let timeout = timeout, start.age >= timeout {
                logger.debug("Classifier reached timeout limit")
                return combinedResults
            }

            let resultsArray = classifier.classify(samples)
            let mergedResults = ClassifierResults(merging: resultsArray)

            if combinedResults == nil {
                combinedResults = mergedResults
                remainingWeight -= classifier.completenessScore
                if remainingWeight <= 0 { break } else { continue }
            }

            // if it's the last classifier treat it as 1.0 completeness, to make the weights add up to 1
            var completeness = classifier.completenessScore
            if classifier.id == classifiers.last?.id {
                completeness = 1.0
            }

            // merge in the results
            let weight = remainingWeight * completeness
            combinedResults = combinedResults?.merging(mergedResults, withWeight: weight)

            remainingWeight -= weight

            if remainingWeight <= 0 { break }
        }

        return combinedResults
    }

    public func classify(_ timelineItem: TimelineItem, timeout: TimeInterval?) -> ClassifierResults? {
        return classify(timelineItem.samplesMatchingDisabled, timeout: timeout)
    }

    public func classify(_ segment: ItemSegment, timeout: TimeInterval?) -> ClassifierResults? {
        return classify(segment.samples, timeout: timeout)
    }

    // MARK: -

    private func updateDiscreteClassifiers(for coordinate: CLLocationCoordinate2D) {
        var updated = discreteClassifiers.filter { (key, classifier) in
            return classifier.contains(coordinate: coordinate)
        }

        let cache = ActivityTypesCache.highlander

        var changed = false

        // always need a D2
        if updated[2] == nil {
            if let cd2 = cache.coreMLModelFor(coordinate: coordinate, depth: 2) {
                updated[2] = cd2
                changed = true

            // } else if ud2 = ... { TODO: fetcd UD2

            } else if let gd2 = ActivityTypeClassifier(coordinate: coordinate, depth: 2) {
                updated[2] = gd2
                changed = true
            }
        }

        if updated[1] == nil {
            if let gd1 = ActivityTypeClassifier(coordinate: coordinate, depth: 1) {
                updated[1] = gd1
                changed = true
            }
        }

        if updated[0] == nil {
            if let gd0 = ActivityTypeClassifier(coordinate: coordinate, depth: 0) {
                updated[0] = gd0
                changed = true
            }
        }

        discreteClassifiers = updated

        if changed {
            print("updateDiscreteClassifiers() discreteClassifiers:")
            let classifiers = discreteClassifiers.sorted { $0.key > $1.key }.map { $0.value }
            for classifier in classifiers {
                print("\(classifier.id)")
            }
        }
    }

}
