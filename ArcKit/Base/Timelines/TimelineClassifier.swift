//
//  TimelineClassifier.swift
//  ArcKit
//
//  Created by Matt Greenfield on 30/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Upsurge
import CoreLocation
import Reachability

public class TimelineClassifier {

    // TODO: is this fucking up in subclasses, because typealiases can't be overridden? i bet it is
    typealias Classifier = ActivityTypeClassifier

    public var minimumTransportCoverage = 0.10

    public static var highlander = TimelineClassifier()

    private(set) public var baseClassifier: ActivityTypeClassifier?
    private(set) public var transportClassifier: ActivityTypeClassifier?

    private let reachability = Reachability()!

    public var canClassify: Bool { return baseClassifier != nil }

    public func classify(_ classifiable: ActivityTypeClassifiable, filtered: Bool) -> ClassifierResults? {

        // attempt to keep the classifiers relevant / fresh
        if let coordinate = classifiable.location?.coordinate {
            updateTheBaseClassifier(for: coordinate)
            updateTheTransportClassifier(for: coordinate)
        }

        // get the base type results
        guard let classifier = baseClassifier else {
            return nil
        }
        let results = classifier.classify(classifiable)

        // not asked to test every type every time?
        if filtered {

            // don't need to go further if transport didn't win the base round
            if results.first?.name != .transport {
                return results
            }

            // don't go further if transport classifier has less than required coverage
            guard let coverage = transportClassifier?.coverageScore, coverage > minimumTransportCoverage else {
                return results
            }
        }

        // get the transport type results
        guard let transportClassifier = transportClassifier else {
            return results
        }
        let transportResults = transportClassifier.classify(classifiable)

        // combine and return the results
        return (results - ActivityTypeName.transport) + transportResults
    }

    public func classify(_ timelineItem: TimelineItem, filtered: Bool) -> ClassifierResults? {
        guard let results = classify(timelineItem.samples, filtered: filtered) else {
            return nil
        }

        // radius is small enough to consider stationary a valid result
        if timelineItem.radius3sd < Visit.maximumRadius {
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

    public func classify(_ segment: ItemSegment, filtered: Bool) -> ClassifierResults? {
        guard let results = classify(segment.samples, filtered: filtered) else {
            return nil
        }

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
    
    public func classify(_ samples: [LocomotionSample], filtered: Bool) -> ClassifierResults? {
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

            // attempt to use existing results
            var tmpResults = filtered ? sample.classifierResults : sample.unfilteredClassifierResults

            // nil or incomplete existing results? get fresh results
            if tmpResults == nil || tmpResults?.moreComing == true {
                if filtered {
                    sample.classifierResults = classify(sample, filtered: filtered)
                    tmpResults = sample.classifierResults ?? tmpResults
                } else {
                    sample.unfilteredClassifierResults = classify(sample, filtered: filtered)
                    tmpResults = sample.unfilteredClassifierResults ?? tmpResults
                }
            }

            guard let results = tmpResults else {
                continue
            }

            if results.moreComing {
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

    // MARK: Region specific classifier management

    private func updateTheBaseClassifier(for coordinate: CLLocationCoordinate2D) {

        // don't try to fetch classifiers without a network connection
        guard reachability.connection != .none else {
            return
        }

        // have a classifier already, and it's still valid?
        if let classifier = baseClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        // attempt to get an updated classifier
        if let replacement = Classifier(requestedTypes: ActivityTypeName.baseTypes, coordinate: coordinate) {
            baseClassifier = replacement
        }
    }

    private func updateTheTransportClassifier(for coordinate: CLLocationCoordinate2D) {

        // don't try to fetch classifiers without a network connection
        guard reachability.connection != .none else {
            return
        }

        // have a classifier already, and it's still valid?
        if let classifier = transportClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        // attempt to get an updated classifier
        if let replacement = Classifier(requestedTypes: ActivityTypeName.transportTypes, coordinate: coordinate) {
            transportClassifier = replacement
        }
    }

}
