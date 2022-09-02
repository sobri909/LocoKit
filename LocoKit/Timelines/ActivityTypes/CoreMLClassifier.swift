//
//  CoreMLClassifier.swift
//  
//
//  Created by Matt Greenfield on 2/9/22.
//

import Foundation
import CoreLocation
import CoreML
import Upsurge

public class CoreMLClassifier: MLCompositeClassifier {

    let model: CoreML.MLModel

    public init() {
        self.model = try! CoreML.MLModel(contentsOf: CoreMLClassifier.modelURL)
    }

    class var modelURL: URL {
        return Bundle(for: self).url(forResource: "ActivityTypeCoreMLClassifier2", withExtension:"mlmodelc")!
    }

    // MARK: - MLCompositeClassifier

    public func canClassify(_ coordinate: CLLocationCoordinate2D?) -> Bool {
        return true
    }

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults? {
        let input = classifiable.coreMLFeatureProvider
        guard let output = try? model.prediction(from: input, options: MLPredictionOptions()) else { return nil }
        return results(for: output)
    }

    public func classify(_ samples: [ActivityTypeClassifiable], timeout: TimeInterval?) -> ClassifierResults? {
        do {
            let inputs = samples.map { $0.coreMLFeatureProvider }
            let batchIn = MLArrayBatchProvider(array: inputs)
            let batchOut = try model.predictions(from: batchIn, options: MLPredictionOptions())

            var intermediateResults: [ClassifierResults] = []
            intermediateResults.reserveCapacity(inputs.count)
            for i in 0..<batchOut.count {
                let output = batchOut.features(at: i)
                let result = results(for: output)
                intermediateResults.append(result)
            }

            return results(for: intermediateResults)

        } catch {
            logger.error("ERROR: \(error)")
            return nil
        }
    }

    public func classify(_ timelineItem: TimelineItem, timeout: TimeInterval?) -> ClassifierResults? {
        return classify(timelineItem.samplesMatchingDisabled, timeout: timeout)
    }

    public func classify(_ segment: ItemSegment, timeout: TimeInterval?) -> ClassifierResults? {
        return classify(segment.samples, timeout: timeout)
    }

    // MARK: -

    private func results(for classifierOutput: MLFeatureProvider) -> ClassifierResults {
        let scores = classifierOutput.featureValue(for: "confirmedTypeProbability")!.dictionaryValue as! [String: Double]
        var items: [ClassifierResultItem] = []
        for (name, score) in scores {
            items.append(ClassifierResultItem(name: ActivityTypeName(rawValue: name)!, score: score))
        }
        return ClassifierResults(results: items, moreComing: false)
    }

    private func results(for resultsArray: [ClassifierResults]) -> ClassifierResults {
        var allScores: [ActivityTypeName: ValueArray<Double>] = [:]
        for typeName in ActivityTypeName.allTypes {
            allScores[typeName] = ValueArray(capacity: resultsArray.count)
        }

        for result in resultsArray {
            for typeName in ActivityTypeName.allTypes {
                if let resultRow = result[typeName] {
                    allScores[resultRow.name]!.append(resultRow.score)
                } else {
                    allScores[typeName]!.append(0)
                }
            }
        }

        var finalResults: [ClassifierResultItem] = []
        for typeName in ActivityTypeName.allTypes {
            var finalScore = 0.0
            if let scores = allScores[typeName], !scores.isEmpty {
                finalScore = mean(scores)
            }
            finalResults.append(ClassifierResultItem(name: typeName, score: finalScore))
        }

        return ClassifierResults(results: finalResults, moreComing: false)
    }
    
}
