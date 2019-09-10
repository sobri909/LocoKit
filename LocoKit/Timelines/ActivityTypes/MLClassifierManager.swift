//
//  MLClassifierManager.swift
//  Pods
//
//  Created by Matt Greenfield on 3/04/18.
//

import os.log
import Upsurge
import LocoKitCore
import CoreLocation

#if canImport(Reachability)
import Reachability
#endif

public protocol MLClassifierManager: MLCompositeClassifier {
    
    associatedtype Classifier: MLClassifier

    var sampleClassifier: Classifier? { get set }

    #if canImport(Reachability)
    var reachability: Reachability { get }
    #endif

    var mutex: PThreadMutex { get }

}

extension MLClassifierManager {

    public func canClassify(_ coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        if let coordinate = coordinate { mutex.sync { updateTheSampleClassifier(for: coordinate) } }
        return mutex.sync { sampleClassifier } != nil
    }

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults? = nil) -> ClassifierResults? {
        return mutex.sync {
            // make sure we're capable of returning sensible results
            guard canClassify(classifiable.location?.coordinate) else { return nil }

            // get the sample classifier
            guard let classifier = mutex.sync(execute: { return sampleClassifier }) else { return nil }

            // get the results
            return classifier.classify(classifiable, previousResults: previousResults)
        }
    }

    public func classify(_ timelineItem: TimelineItem, timeout: TimeInterval? = nil) -> ClassifierResults? {
        guard let results = classify(timelineItem.samples, timeout: timeout) else { return nil }

        // radius is small enough to consider stationary a valid result
        if timelineItem.radius3sd < Visit.maximumRadius { return results }

        guard let stationary = results[.stationary] else { return results }

        // radius is too big for stationary. so let's zero out its score
        var resultsArray = results.array
        resultsArray.remove(stationary)
        resultsArray.append(ClassifierResultItem(name: .stationary, score: 0,
                                                 modelAccuracyScore: stationary.modelAccuracyScore))

        return ClassifierResults(results: resultsArray, moreComing: results.moreComing)
    }

    public func classify(_ segment: ItemSegment, timeout: TimeInterval? = nil) -> ClassifierResults? {
        guard let results = classify(segment.samples, timeout: timeout) else { return nil }

        // radius is small enough to consider stationary a valid result
        if segment.radius.with3sd < Visit.maximumRadius {
            return results
        }

        guard let stationary = results[.stationary] else {
            return results
        }

        // radius is too big for stationary. so let's zero out its score
        var resultsArray = results.array
        resultsArray.remove(stationary)
        resultsArray.append(ClassifierResultItem(name: .stationary, score: 0,
                                                 modelAccuracyScore: stationary.modelAccuracyScore))

        return ClassifierResults(results: resultsArray, moreComing: results.moreComing)
    }

    // Note: samples must be provided in date ascending order
    public func classify(_ samples: [ActivityTypeClassifiable], timeout: TimeInterval? = nil) -> ClassifierResults? {
        if samples.isEmpty { return nil }

        let start = Date()

        var allScores: [ActivityTypeName: ValueArray<Double>] = [:]
        var allAccuracies: [ActivityTypeName: ValueArray<Double>] = [:]
        for typeName in ActivityTypeName.allTypes {
            allScores[typeName] = ValueArray(capacity: samples.count)
            allAccuracies[typeName] = ValueArray(capacity: samples.count)
        }

        var moreComing = false
        var lastResults: ClassifierResults?

        for sample in samples {
            if let timeout = timeout, start.age >= timeout {
                os_log("Classifer reached timeout limit", type: .debug)
                moreComing = true
                break
            }

            var tmpResults = sample.classifierResults

            // nil or incomplete existing results? get fresh results
            if tmpResults == nil || tmpResults?.moreComing == true {
                sample.classifierResults = classify(sample, previousResults: lastResults)
                tmpResults = sample.classifierResults ?? tmpResults
            }

            guard let results = tmpResults else { continue }

            if results.moreComing { moreComing = true }

            for typeName in ActivityTypeName.allTypes {
                // if sample has confirmedType, give it a 1.0 score
                if let sample = sample as? ActivityTypeTrainable, typeName == sample.confirmedType {
                    allScores[typeName]!.append(1.0)
                    allAccuracies[typeName]!.append(1.0)

                } else if let resultRow = results[typeName] {
                    allScores[resultRow.name]!.append(resultRow.score)
                    allAccuracies[resultRow.name]!.append(resultRow.modelAccuracyScore ?? 0)

                } else {
                    allScores[typeName]!.append(0)
                    allAccuracies[typeName]!.append(0)
                }
            }

            lastResults = results
        }

        var finalResults: [ClassifierResultItem] = []

        for typeName in ActivityTypeName.allTypes {
            var finalScore = 0.0
            if let scores = allScores[typeName], !scores.isEmpty {
                finalScore = mean(scores)
            }

            var finalAccuracy: Double?
            if let accuracies = allAccuracies[typeName], !accuracies.isEmpty {
                finalAccuracy = mean(accuracies)
            }

            finalResults.append(ClassifierResultItem(name: typeName, score: finalScore,
                                                     modelAccuracyScore: finalAccuracy))
        }

        return ClassifierResults(results: finalResults, moreComing: moreComing)
    }

    // MARK: Region specific classifier management

    private func updateTheSampleClassifier(for coordinate: CLLocationCoordinate2D) {

        // have a classifier already, and it's still valid?
        if let classifier = sampleClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        #if canImport(Reachability)
        // don't try to fetch classifiers without a network connection
        guard reachability.connection != .none else { return }
        #endif

        // attempt to get an updated classifier
        if let replacement = Classifier(requestedTypes: ActivityTypeName.allTypes, coordinate: coordinate) {
            sampleClassifier = replacement
        }
    }

}
