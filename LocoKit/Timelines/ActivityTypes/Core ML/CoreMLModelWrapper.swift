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
import CreateML

public class CoreMLModelWrapper: DiscreteClassifier, PersistableRecord, Hashable {

    // [Depth: Samples]
    static let modelMaxTrainingSamples: [Int: Int] = [
        2: 200_000,
        1: 200_000,
        0: 250_000
    ]

    // for completenessScore
    // [Depth: Samples]
    static let modelMinTrainingSamples: [Int: Int] = [
        2: 50_000,
        1: 150_000,
        0: 200_000
    ]

    static let numberOfLatBucketsDepth0 = 18
    static let numberOfLongBucketsDepth0 = 36
    static let numberOfLatBucketsDepth1 = 100
    static let numberOfLongBucketsDepth1 = 100
    static let numberOfLatBucketsDepth2 = 200
    static let numberOfLongBucketsDepth2 = 200

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
        let latitudeRange = Self.latitudeRangeFor(depth: depth, coordinate: coordinate)
        let longitudeRange = Self.longitudeRangeFor(depth: depth, coordinate: coordinate)

        let dict: [String: Any] = [
            "depth": depth,
            "latitudeMin": latitudeRange.min,
            "latitudeMax": latitudeRange.max,
            "longitudeMin": longitudeRange.min,
            "longitudeMax": longitudeRange.max
        ]

        self.init(dict: dict, in: store)

        updateTheModel()
    }
    
    convenience init(bundledURL: URL, in store: TimelineStore) {
        let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let latitudeRange = Self.latitudeRangeFor(depth: 0, coordinate: coordinate)
        let longitudeRange = Self.longitudeRangeFor(depth: 0, coordinate: coordinate)

        let dict: [String: Any] = [
            "depth": 0,
            "geoKey": "BD0 0.00,0.00",
            "latitudeMin": latitudeRange.min,
            "latitudeMax": latitudeRange.max,
            "longitudeMin": longitudeRange.min,
            "longitudeMax": longitudeRange.max,
        ]

        self.init(dict: dict, in: store)

        self.filename = bundledURL.lastPathComponent
        self.needsUpdate = false
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

    private lazy var model: MLModel? = {
        do {
            return try mutex.sync { try MLModel(contentsOf: modelURL) }
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
        if filename.hasPrefix("B") {
            return Bundle.main.url(forResource: filename, withExtension: nil)!
        }
        return store.modelsDir.appendingPathComponent(filename)
    }

    public func reloadModel() throws {
        try mutex.sync { self.model = try MLModel(contentsOf: modelURL) }
    }

    static func latitudeRangeFor(depth: Int, coordinate: CLLocationCoordinate2D) -> (min: Double, max: Double) {
        let depth0Range = (min: -90.0, max: 90.0)

        switch depth {
        case 2:
            let bucketSize = latitudeBinSizeFor(depth: 1)
            let parentRange = latitudeRangeFor(depth: 1, coordinate: coordinate)
            let bucket = Int((coordinate.latitude - parentRange.min) / bucketSize)
            return (min: parentRange.min + (bucketSize * Double(bucket)),
                    max: parentRange.min + (bucketSize * Double(bucket + 1)))

        case 1:
            let bucketSize = latitudeBinSizeFor(depth: 0)
            let parentRange = latitudeRangeFor(depth: 0, coordinate: coordinate)
            let bucket = Int((coordinate.latitude - parentRange.min) / bucketSize)
            return (min: parentRange.min + (bucketSize * Double(bucket)),
                    max: parentRange.min + (bucketSize * Double(bucket + 1)))

        default:
            return depth0Range
        }
    }

    static func longitudeRangeFor(depth: Int, coordinate: CLLocationCoordinate2D) -> (min: Double, max: Double) {
        let depth0Range = (min: -180.0, max: 180.0)

        switch depth {
        case 2:
            let bucketSize = Self.longitudeBinSizeFor(depth: 1)
            let parentRange = Self.longitudeRangeFor(depth: 1, coordinate: coordinate)
            let bucket = Int((coordinate.longitude - parentRange.min) / bucketSize)
            return (min: parentRange.min + (bucketSize * Double(bucket)),
                    max: parentRange.min + (bucketSize * Double(bucket + 1)))

        case 1:
            let bucketSize = Self.longitudeBinSizeFor(depth: 0)
            let parentRange = Self.longitudeRangeFor(depth: 0, coordinate: coordinate)
            let bucket = Int((coordinate.longitude - parentRange.min) / bucketSize)
            return (min: parentRange.min + (bucketSize * Double(bucket)),
                    max: parentRange.min + (bucketSize * Double(bucket + 1)))

        default:
            return depth0Range
        }
    }

    static func latitudeBinSizeFor(depth: Int) -> Double {
        let depth0 = 180.0 / Double(Self.numberOfLatBucketsDepth0)
        let depth1 = depth0 / Double(Self.numberOfLatBucketsDepth1)
        let depth2 = depth1 / Double(Self.numberOfLatBucketsDepth2)

        switch depth {
        case 2: return depth2
        case 1: return depth1
        default: return depth0
        }
    }

    static func longitudeBinSizeFor(depth: Int) -> Double {
        let depth0 = 360.0 / Double(Self.numberOfLongBucketsDepth0)
        let depth1 = depth0 / Double(Self.numberOfLongBucketsDepth1)
        let depth2 = depth1 / Double(Self.numberOfLongBucketsDepth2)

        switch depth {
        case 2: return depth2
        case 1: return depth1
        default: return depth0
        }
    }

    // MARK: - DiscreteClassifier

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults {
        guard let model else {
            totalSamples = 0 // if file used to exist, sample count will be wrong and will cause incorrect weighting
            print("[\(geoKey)] classify(classifiable:) NO MODEL!")
            return ClassifierResults(results: [], moreComing: false)
        }
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
        return min(1.0, Double(totalSamples) / Double(Self.modelMinTrainingSamples[depth]!))
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
        if geoKey.hasPrefix("B") { return }

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

    public func updateTheModel(task: BGProcessingTask? = nil, currentClassifier classifier: ActivityClassifier? = nil) {
        if geoKey.hasPrefix("B") { return }

        CoreMLModelUpdater.highlander.updatesQueue.addOperation {
            defer {
                if let task {
                    CoreMLModelUpdater.highlander.updateQueuedModels(task: task, currentClassifier: classifier)
                }
            }

            logger.info("UPDATING: \(self.geoKey)")

            let manager = FileManager.default
            let tempModelFile = manager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mlmodel")

            do {
                var csvFile: URL?
                var samplesCount = 0
                var includedTypes: Set<ActivityTypeName> = []

                let start = Date()
                let samples = self.fetchTrainingSamples()
                logger.info("UPDATING: \(self.geoKey), SAMPLES BATCH: \(samples.count), duration: \(start.age)")

                let (url, samplesAdded, typesAdded) = try self.exportCSV(samples: samples, appendingTo: csvFile)
                csvFile = url
                samplesCount += samplesAdded
                includedTypes.formUnion(typesAdded)

                guard samplesCount > 0, includedTypes.count > 1 else {
                    logger.info("SKIPPED: \(self.geoKey) (samples: \(samplesCount), includedTypes: \(includedTypes.count))")
                    self.totalSamples = samplesCount
                    self.accuracyScore = nil
                    self.lastUpdated = Date()
                    self.needsUpdate = false
                    self.save()
                    return
                }

                logger.info("UPDATING: \(self.geoKey), FINISHED WRITING CSV FILE")

                guard let csvFile else {
                    logger.error("Missing CSV file for model build.")
                    return
                }

                // load the csv file
                let dataFrame = try DataFrame(contentsOfCSVFile: csvFile)

                // train the model
                let classifier = try MLBoostedTreeClassifier(trainingData: dataFrame, targetColumn: "confirmedType")

                do {
                    try FileManager.default.createDirectory(at: self.store.modelsDir, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    logger.error("Couldn't create MLModels directory.")
                }

                // write model to temp file
                try classifier.write(to: tempModelFile)

                // compile the model
                let compiledModelFile = try MLModel.compileModel(at: tempModelFile)

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
    }

    private func fetchTrainingSamples() -> [PersistentSample] {
        store.connectToDatabase()
        let rect = CoordinateRect(latitudeRange: latitudeRange, longitudeRange: longitudeRange)
        if depth == 0 {
            return store.samples(
                where: """
                    confirmedType IS NOT NULL
                    AND likely(xyAcceleration IS NOT NULL)
                    AND likely(zAcceleration IS NOT NULL)
                    AND likely(stepHz IS NOT NULL)
                    ORDER BY lastSaved DESC
                    LIMIT ?
                """,
                arguments: [Self.modelMaxTrainingSamples[depth]!],
                explain: true
            )
        }
        return store.samples(
            inside: rect,
            where: """
                    confirmedType IS NOT NULL
                    AND likely(xyAcceleration IS NOT NULL)
                    AND likely(zAcceleration IS NOT NULL)
                    AND likely(stepHz IS NOT NULL)
                    ORDER BY lastSaved DESC
                    LIMIT ?
                """,
            arguments: [Self.modelMaxTrainingSamples[depth]!],
            explain: true
        )
    }

    private func exportCSV(samples: [PersistentSample], appendingTo: URL? = nil) throws -> (URL, Int, Set<ActivityTypeName>) {
        let modelFeatures = [
            "stepHz", "xyAcceleration", "zAcceleration", "movingState",
            "verticalAccuracy", "horizontalAccuracy",
            "speed", "course", "latitude", "longitude", "altitude",
            "timeOfDay", "confirmedType", "sinceVisitStart"
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
            line += "\(sample.timeOfDay),\"\(sample.confirmedType!)\",\(sample.sinceVisitStart)"

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
