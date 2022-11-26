//
//  File.swift
//  
//
//  Created by Matt Greenfield on 26/10/22.
//

import Foundation
import CoreML
import TabularData
import CoreLocation
import BackgroundTasks
import Upsurge
import GRDB
import os.log
#if canImport(CreateML)
import CreateML
#endif

public class CoreMLModelWrapper: DiscreteClassifier, PersistableRecord, Hashable {

    static let modelMaxTrainingSamples = 200_000
    static let modelMinTrainingSamples = 50_000 // for completenessScore
    static let modelSamplesBatchSize = 50_000

    // MARK: -

    public internal(set) var geoKey: String = ""
    public internal(set) var filename: String = ""
    public internal(set) var depth: Int
    public internal(set) var latitudeRange: ClosedRange<Double>
    public internal(set) var longitudeRange: ClosedRange<Double>
    public internal(set) var lastUpdated: Date?
    public internal(set) var accuracyScore: Double?
    public internal(set) var totalSamples: Int = 0

    public var needsUpdate = false
    public var lastSaved: Date?
    public internal(set) var transactionDate: Date?

    public var store: TimelineStore

    private let mutex = UnfairLock()

    // MARK: -

    convenience init(coordinate: CLLocationCoordinate2D, depth: Int, in store: TimelineStore) {
        let latitudeRange = ActivityType.latitudeRangeFor(depth: depth, coordinate: coordinate)
        let longitudeRange = ActivityType.longitudeRangeFor(depth: depth, coordinate: coordinate)

        let dict: [String: Any] = [
            "depth": depth,
            "latitudeMin": latitudeRange.min,
            "latitudeMax": latitudeRange.max,
            "longitudeMin": longitudeRange.min,
            "longitudeMax": longitudeRange.max
        ]

        self.init(dict: dict, in: store)
    }

    public init(dict: [String: Any?], in store: TimelineStore) {
        self.store = store

        self.lastSaved = dict["lastSaved"] as? Date
        self.lastUpdated = dict["lastUpdated"] as? Date
        self.accuracyScore = dict["accuracyScore"] as? Double
        self.needsUpdate = dict["needsUpdate"] as? Bool ?? true

        if let min = dict["latitudeMin"] as? Double, let max = dict["latitudeMax"] as? Double {
            self.latitudeRange = min...max
        } else {
            fatalError("MISSING model.latitudeRange")
        }

        if let min = dict["longitudeMin"] as? Double, let max = dict["longitudeMax"] as? Double {
            self.longitudeRange = min...max
        } else {
            fatalError("MISSING model.longitudeRange")
        }

        if let depth = dict["depth"] as? Int { self.depth = depth }
        else if let depth = dict["depth"] as? Int64 { self.depth = Int(depth) }
        else { fatalError("MISSING model.depth") }

        self.geoKey = dict["geoKey"] as? String ?? inferredGeoKey
        self.filename = dict["filename"] as? String ?? inferredFilename

        if let total = dict["totalSamples"] as? Int { totalSamples = total }
        else if let total = dict["totalSamples"] as? Int64 { totalSamples = Int(total) }

        store.add(self)
    }

    private var inferredGeoKey: String {
        return String(format: "CD\(depth) %.2f,%.2f", centerCoordinate.latitude, centerCoordinate.longitude)
    }

    private var inferredFilename: String {
        return String(format: "CD\(depth)_%.2f_%.2f", centerCoordinate.latitude, centerCoordinate.longitude) + ".mlmodelc"
    }

    var latitudeWidth: Double { return latitudeRange.upperBound - latitudeRange.lowerBound }
    var longitudeWidth: Double { return longitudeRange.upperBound - longitudeRange.lowerBound }

    var centerCoordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(
            latitude: latitudeRange.lowerBound + latitudeWidth * 0.5,
            longitude: longitudeRange.lowerBound + longitudeWidth * 0.5
        )
    }

    // MARK: - MLModel loading

    private lazy var model: CoreML.MLModel? = {
        do {
            return try CoreML.MLModel(contentsOf: modelURL)
        } catch {
            logger.error("ERROR: \(error)")
            if !needsUpdate {
                needsUpdate = true
                save()
                logger.info("[\(self.geoKey)] Queued update, because missing model file")
            }
            return nil
        }
    }()

    public var modelURL: URL {
        return store.modelsDir.appendingPathComponent(filename)
    }

    public func reloadModel() throws {
        self.model = try CoreML.MLModel(contentsOf: modelURL)
    }
    
    // MARK: - DiscreteClassifier

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults {
        guard let model else { print("[\(geoKey)] classify(classifiable:) NO MODEL!"); return ClassifierResults(results: [], moreComing: false) }
        let input = classifiable.coreMLFeatureProvider
        guard let output = mutex.sync(execute: { try? model.prediction(from: input, options: MLPredictionOptions()) }) else {
            return ClassifierResults(results: [], moreComing: false)
        }
        return results(for: output)
    }

    public func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return false }

        if !latitudeRange.contains(coordinate.latitude) { return false }
        if !longitudeRange.contains(coordinate.longitude) { return false }

        return true
    }

    public var completenessScore: Double {
        return min(1.0, Double(totalSamples) / Double(Self.modelMinTrainingSamples))
    }

    // MARK: - Core ML classifying

    private func results(for classifierOutput: MLFeatureProvider) -> ClassifierResults {
        let scores = classifierOutput.featureValue(for: "confirmedTypeProbability")!.dictionaryValue as! [String: Double]
        var items: [ClassifierResultItem] = []
        for (name, score) in scores {
            items.append(ClassifierResultItem(name: ActivityTypeName(rawValue: name)!, score: score))
        }
        return ClassifierResults(results: items, moreComing: false)
    }

    // MARK: - Saving

    public func save() {
        do {
            try store.auxiliaryPool.write { db in
                self.transactionDate = Date()
                try self.save(in: db)
                self.lastSaved = self.transactionDate
            }
        } catch {
            logger.error("ERROR: \(error)")
        }
    }

    public var unsaved: Bool { return lastSaved == nil }
    public func save(in db: Database) throws {
        if unsaved { try insert(db) } else { try update(db) }
    }

    // MARK: - PersistableRecord

    public static let databaseTableName = "CoreMLModel"

    public static var persistenceConflictPolicy: PersistenceConflictPolicy {
        return PersistenceConflictPolicy(insert: .replace, update: .abort)
    }

    open func encode(to container: inout PersistenceContainer) {
        container["geoKey"] = geoKey
        container["lastSaved"] = transactionDate ?? lastSaved ?? Date()

        container["depth"] = depth
        container["lastUpdated"] = lastUpdated
        container["needsUpdate"] = needsUpdate
        container["totalSamples"] = totalSamples
        container["accuracyScore"] = accuracyScore
        container["filename"] = filename

        container["latitudeMin"] = latitudeRange.lowerBound
        container["latitudeMax"] = latitudeRange.upperBound
        container["longitudeMin"] = longitudeRange.lowerBound
        container["longitudeMax"] = longitudeRange.upperBound
    }

    // MARK: - Model building

    @available(iOS 15, *)
    public func updatedModel(task: BGProcessingTask? = nil, in store: TimelineStore) {
        #if canImport(CreateML)
        CoreMLModelUpdater.highlander.updatesQueue.addOperation {
            defer {
                if let task {
                    CoreMLModelUpdater.highlander.updateQueuedModels(task: task, store: store)
                }
            }

            logger.info("UPDATING: \(self.geoKey)")

            let manager = FileManager.default
            let tempModelFile = manager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mlmodel")

            do {
                var csvFile: URL?
                var lastDate: Date?
                var samplesCount = 0
                var includedTypes: Set<ActivityTypeName> = []
                repeat {
                    let start = Date()
                    let samples = self.fetchTrainingSamples(in: store, from: lastDate)
                    print("buildModel() SAMPLES BATCH: \(samples.count), duration: \(start.age)")
                    let (url, samplesAdded, typesAdded) = try self.exportCSV(samples: samples, appendingTo: csvFile)
                    csvFile = url
                    samplesCount += samplesAdded
                    includedTypes.formUnion(typesAdded)
                    if samplesCount >= Self.modelMaxTrainingSamples { break }
                    lastDate = samples.last?.lastSaved
                } while lastDate != nil

                guard samplesCount > 0, includedTypes.count > 1 else {
                    logger.info("SKIPPED: \(self.geoKey) (samples: \(samplesCount), includedTypes: \(includedTypes.count))")
                    self.totalSamples = samplesCount
                    self.accuracyScore = nil
                    self.lastUpdated = Date()
                    self.needsUpdate = false
                    self.save()
                    return
                }

                print("buildModel() FINISHED WRITING CSV FILE")

                guard let csvFile else {
                    logger.error("Missing CSV file for model build.")
                    return
                }

                // load the csv file
                let dataFrame = try DataFrame(contentsOfCSVFile: csvFile)

                // train the model
                let classifier = try MLBoostedTreeClassifier(trainingData: dataFrame, targetColumn: "confirmedType")

                do {
                    try FileManager.default.createDirectory(at: store.modelsDir, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    logger.error("Couldn't create MLModels directory.")
                }

                // write model to temp file
                try classifier.write(to: tempModelFile)

                // compile the model
                let compiledModelFile = try CoreML.MLModel.compileModel(at: tempModelFile)

                // save model to final dest
                _ = try manager.replaceItemAt(self.modelURL, withItemAt: compiledModelFile)

                // update metadata
                self.totalSamples = samplesCount
                self.accuracyScore = (1.0 - classifier.validationMetrics.classificationError)
                self.lastUpdated = Date()
                self.needsUpdate = false
                self.save()

                logger.info("UPDATED: \(self.geoKey) (samples: \(self.totalSamples), accuracy: \(String(format: "%.2f", self.accuracyScore!)), includedTypes: \(includedTypes.count))")

                try self.reloadModel()

            } catch {
                logger.error("buildModel() ERROR: \(error)")
            }
        }
        #endif
    }

    private func fetchTrainingSamples(in store: TimelineStore, from: Date? = nil) -> [PersistentSample] {
        store.connectToDatabase()

        let rect = CoordinateRect(latitudeRange: latitudeRange, longitudeRange: longitudeRange)

        if let from {
            return store.samples(
                inside: rect,
                where: """
                    lastSaved < ?
                    AND confirmedType IS NOT NULL
                    AND lastSaved IS NOT NULL
                    AND xyAcceleration IS NOT NULL
                    AND zAcceleration IS NOT NULL
                    AND stepHz IS NOT NULL
                        ORDER BY lastSaved DESC
                        LIMIT ?
                """,
                arguments: [from, Self.modelSamplesBatchSize]
            )

        } else {
            return store.samples(
                inside: rect,
                where: """
                    confirmedType IS NOT NULL
                    AND lastSaved IS NOT NULL
                    AND xyAcceleration IS NOT NULL
                    AND zAcceleration IS NOT NULL
                    AND stepHz IS NOT NULL
                        ORDER BY lastSaved DESC
                        LIMIT ?
                """,
                arguments: [Self.modelSamplesBatchSize]
            )
        }
    }

    private func exportCSV(samples: [PersistentSample], appendingTo: URL? = nil) throws -> (URL, Int, Set<ActivityTypeName>) {
        let modelFeatures = [
            "stepHz", "xyAcceleration", "zAcceleration", "movingState",
            "verticalAccuracy", "horizontalAccuracy",
            "speed", "course", "latitude", "longitude", "altitude",
            "timeOfDay", "confirmedType"
        ]

        let csvFile = appendingTo ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // header the csv file
        if appendingTo == nil {
            try modelFeatures.joined(separator: ",").appendLineToURL(fileURL: csvFile)
        }

        var samplesAdded = 0
        var includedTypes: Set<ActivityTypeName> = []

        // write the samples to file
        for sample in samples where sample.confirmedType != nil {
            guard sample.source == "LocoKit" else { continue }
            guard let location = sample.location, location.hasUsableCoordinate else { continue }
            guard location.speed >= 0, location.course >= 0 else { continue }
            guard let stepHz = sample.stepHz else { continue }
            guard let xyAcceleration = sample.xyAcceleration else { continue }
            guard let zAcceleration = sample.zAcceleration else { continue }
            guard location.speed >= 0 else { continue }
            guard location.course >= 0 else { continue }
            guard location.horizontalAccuracy > 0 else { continue }
            guard location.verticalAccuracy > 0 else { continue }

            includedTypes.insert(sample.confirmedType!)

            var line = ""
            line += "\(stepHz),\(xyAcceleration),\(zAcceleration),\"\(sample.movingState.rawValue)\","
            line += "\(location.horizontalAccuracy),\(location.verticalAccuracy),"
            line += "\(location.speed),\(location.course),\(location.coordinate.latitude),\(location.coordinate.longitude),\(location.altitude),"
            line += "\(sample.timeOfDay),\"\(sample.confirmedType!)\""

            try line.appendLineToURL(fileURL: csvFile)
            samplesAdded += 1
        }

        print("exportCSV() WROTE SAMPLES: \(samplesAdded)")

        return (csvFile, samplesAdded, includedTypes)
    }

    // MARK: - Equatable

    open func hash(into hasher: inout Hasher) {
        hasher.combine(geoKey)
    }

    public static func ==(lhs: CoreMLModelWrapper, rhs: CoreMLModelWrapper) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }

    // MARK: - Identifiable

    public var id: String { return geoKey }

}
