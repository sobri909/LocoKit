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

public class CoreMLClassifier: MLCompositeClassifier {

    private var modelURL: URL
    private var model: CoreML.MLModel

    public init() throws {
        self.model = try CoreML.MLModel(contentsOf: CoreMLClassifier.customModelURL)
        self.modelURL = CoreMLClassifier.customModelURL
    }

    public init(modelURL: URL) throws {
        self.modelURL = modelURL
        self.model = try CoreML.MLModel(contentsOf: modelURL)
    }

    // MARK: -

    class var customModelURL: URL {
        return try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CoreMLModel.mlmodelc")
    }

    public func reloadModel(modelURL: URL? = nil) throws {
        if let modelURL {
            self.model = try CoreML.MLModel(contentsOf: modelURL)
            self.modelURL = modelURL
        } else {
            self.model = try CoreML.MLModel(contentsOf: CoreMLClassifier.customModelURL)
            self.modelURL = CoreMLClassifier.customModelURL
        }
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

    // MARK: - Model building

    @available(iOS 15, *)
    public static func buildModel(in store: TimelineStore) async {
        let dateRange = DateInterval(
            start: Date(timeIntervalSinceNow: -.oneYear * 1),
            end: Date()
        )
        
        print("buildModel() START")

        let manager = FileManager.default
        let tempModelFile = manager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mlmodel")

        store.connectToDatabase()
        let samples = store.samples(
            where: "date BETWEEN ? AND ? AND confirmedType IS NOT NULL AND source = ?",
            arguments: [dateRange.start, dateRange.end, "LocoKit"]
        )
        print("buildModel() FETCHED SAMPLES: \(samples.count)")

        do {
            let csvFile = try exportCSV(samples: samples)
            print("buildModel() SAVED CSV")

            let dataFrame = try DataFrame(contentsOfCSVFile: csvFile)
            print("buildModel() LOADED CSV")

            let classifier = try MLBoostedTreeClassifier(trainingData: dataFrame, targetColumn: "confirmedType")
            print("buildModel() TRAINED CLASSIFIER")

            try classifier.write(to: tempModelFile)
            print("buildModel() WROTE TEMP FILE")

            let compiledModelFile = try CoreML.MLModel.compileModel(at: tempModelFile)
            print("buildModel() COMPILED MODEL")

            _ = try manager.replaceItemAt(CoreMLClassifier.customModelURL, withItemAt: compiledModelFile)
            print("buildModel() SAVED MODEL TO FINAL URL")

        } catch {
            print("buildModel() ERROR: \(error)")
        }
    }

    private static func exportCSV(samples: [PersistentSample]) throws -> URL {
        print("exportCSV() samples: \(samples.count)")

        let modelFeatures = [
            "stepHz", "xyAcceleration", "zAcceleration", "movingState",
            "verticalAccuracy", "horizontalAccuracy",
            "speed", "course", "latitude", "longitude", "altitude",
            "timeOfDay", "confirmedType"
        ]

        let csvFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // header the csv file
        try modelFeatures.joined(separator: ",").appendLineToURL(fileURL: csvFile)

        // write the samples to file
        for sample in samples where sample.confirmedType != nil {
            guard let location = sample.location, location.hasUsableCoordinate else { continue }
            guard location.speed >= 0, location.course >= 0 else { continue }
            guard let stepHz = sample.stepHz else { continue }
            guard let xyAcceleration = sample.xyAcceleration else { continue }
            guard let zAcceleration = sample.zAcceleration else { continue }
            guard location.speed >= 0 else { continue }
            guard location.course >= 0 else { continue }
            guard location.horizontalAccuracy > 0 else { continue }
            guard location.verticalAccuracy > 0 else { continue }

            var line = ""
            line += "\(stepHz),\(xyAcceleration),\(zAcceleration),\"\(sample.movingState.rawValue)\","
            line += "\(location.horizontalAccuracy),\(location.verticalAccuracy),"
            line += "\(location.speed),\(location.course),\(location.coordinate.latitude),\(location.coordinate.longitude),\(location.altitude),"
            line += "\(sample.timeOfDay),\"\(sample.confirmedType!)\""

            try line.appendLineToURL(fileURL: csvFile)
        }

        print("exportCSV() FINI")

        return csvFile
    }

}
