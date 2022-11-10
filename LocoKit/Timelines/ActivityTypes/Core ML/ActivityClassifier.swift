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

    private var discreteClassifiers: [Int: any DiscreteClassifier] = [:] // index = priority

    private let mutex = PThreadMutex(type: .recursive)

    // MARK: - MLCompositeClassifier

    public func canClassify(_ coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        if let coordinate { mutex.sync { updateDiscreteClassifiers(for: coordinate) } }
        return !discreteClassifiers.isEmpty
    }

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults? {

        // make sure have suitable classifiers
        if let coordinate = classifiable.location?.coordinate { mutex.sync { updateDiscreteClassifiers(for: coordinate) } }

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

        // make sure have suitable classifiers
        // TODO: this sucks for itms briding D2 regions
        let center = samples.compactMap { $0.location }.center
        if let coordinate = center?.coordinate { mutex.sync { updateDiscreteClassifiers(for: coordinate) } }

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

        // all existing classfiiers are good?
        if updated.count == 4 { return }

        let cache = ActivityTypesCache.highlander

        // get a CD2
        if updated.first(where: { ($0.1.id as? String)?.hasPrefix("CD2") == true }) == nil {
            if let classifier = cache.coreMLModelFor(coordinate: coordinate, depth: 2) {
                print("FETCHED: \(classifier.id)")
                updated[3] = classifier // priority 3 (top)
            }
        }

        // get a GD2
        if updated.first(where: { ($0.1.id as? String)?.hasPrefix("GD2") == true }) == nil {
            if let classifier = ActivityTypeClassifier(coordinate: coordinate, depth: 2)  {
                print("FETCHED: \(classifier.id)")
                updated[2] = classifier
            }
        }

        // get a GD1
        if updated.first(where: { ($0.1.id as? String)?.hasPrefix("GD1") == true }) == nil {
            if let classifier = ActivityTypeClassifier(coordinate: coordinate, depth: 1)  {
                print("FETCHED: \(classifier.id)")
                updated[1] = classifier
            }
        }

        // get a GD0
        if updated.first(where: { ($0.1.id as? String)?.hasPrefix("GD0") == true }) == nil {
            if let classifier = ActivityTypeClassifier(coordinate: coordinate, depth: 0)  {
                print("FETCHED: \(classifier.id)")
                updated[0] = classifier
            }
        }

        discreteClassifiers = updated
    }

}
