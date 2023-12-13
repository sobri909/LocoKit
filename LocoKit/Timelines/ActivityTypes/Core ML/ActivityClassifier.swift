//
//  CoreMLClassifier.swift
//  
//
//  Created by Matt Greenfield on 2/9/22.
//

import Foundation
import CoreLocation
import TabularData
import CoreML
import Upsurge
import BackgroundTasks

public class ActivityClassifier {

    private let store: TimelineStore
    public private(set) var discreteClassifiers: [Int: any DiscreteClassifier] = [:] // index = priority
    private let mutex = PThreadMutex(type: .recursive)

    public init(store: TimelineStore) {
        self.store = store
    }

    // MARK: - MLCompositeClassifier

    public func canClassify(_ coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        if let coordinate { mutex.sync { updateDiscreteClassifiers(for: coordinate) } }
        return !discreteClassifiers.isEmpty
    }

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults? {

        // make sure have suitable classifiers
        if let coordinate = classifiable.location?.coordinate { mutex.sync { updateDiscreteClassifiers(for: coordinate) } }

        // highest priorty first (ie CD2 first)
        let classifiers = mutex.sync { discreteClassifiers.sorted { $0.key > $1.key }.map { $0.value } }

        var combinedResults: ClassifierResults?
        var remainingWeight = 1.0
        var moreComing = true

        for classifier in classifiers {
            let results = classifier.classify(classifiable, previousResults: previousResults)

            // at least one classifier in the tree is complete?
            if classifier.completenessScore >= 1 { moreComing = false }

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

        combinedResults?.moreComing = moreComing

        // cache in the sample, and potentially update the stored value
        if let combinedResults, !combinedResults.moreComing {
            classifiable.classifierResults = combinedResults
            if let sample = classifiable as? PersistentSample {
                sample._classifiedType = combinedResults.best.name
            }
        }

        return combinedResults
    }

    // Note: samples should be provided in date ascending order
    public func classify(_ samples: [ActivityTypeClassifiable], timeout: TimeInterval? = nil) -> ClassifierResults? {
        if samples.isEmpty { return nil }

        let start = Date()

        var allScores: [ActivityTypeName: ValueArray<Double>] = [:]
        for typeName in ActivityTypeName.allTypes {
            allScores[typeName] = ValueArray(capacity: samples.count)
        }

        var moreComing = false
        var lastResults: ClassifierResults?

        for sample in samples {
            if let timeout = timeout, start.age >= timeout {
                logger.info("Classifer reached timeout limit.")
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
                if let resultRow = results[typeName] {
                    allScores[resultRow.name]!.append(resultRow.score)
                } else {
                    allScores[typeName]!.append(0)
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

            finalResults.append(ClassifierResultItem(name: typeName, score: finalScore))
        }

        return ClassifierResults(results: finalResults, moreComing: moreComing)
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

        let bundledModelURL = Bundle.main.url(forResource: "BD0", withExtension: "mlmodelc")
        let targetModelsCount = bundledModelURL != nil ? 4 : 3

        // all existing classifiers are good?
        if updated.count == targetModelsCount { return }

        // get a CD2
        if updated.first(where: { $0.value.geoKey.hasPrefix("CD2") == true }) == nil {
            if let classifier = store.coreMLModelFor(coordinate: coordinate, depth: 2) {
                updated[2] = classifier // priority 2 (top)
            }
        }

        // get a CD1
        if updated.first(where: { $0.value.geoKey.hasPrefix("CD1") == true }) == nil {
            if let classifier = store.coreMLModelFor(coordinate: coordinate, depth: 1) {
                updated[1] = classifier
            }
        }
        
        // get a CD0
        if updated.first(where: { $0.value.geoKey.hasPrefix("CD0") == true }) == nil {
            if let classifier = store.coreMLModelFor(coordinate: coordinate, depth: 0) {
                updated[0] = classifier
            }
        }

        // get bundled CD0 (BD0)
        if let bundledModelURL, updated.first(where: { $0.value.geoKey.hasPrefix("BD0") == true }) == nil {
            updated[-1] = CoreMLModelWrapper(bundledURL: bundledModelURL, in: store)
        }

        discreteClassifiers = updated
    }

}
