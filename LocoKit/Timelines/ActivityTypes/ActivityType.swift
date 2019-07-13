//
// Created by Matt Greenfield on 23/05/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

import os.log
import CoreMotion
import CoreLocation
import GRDB

open class ActivityType: MLModel, PersistableRecord {

    public static let currentVersion = 700000

    static let numberOfLatBucketsDepth0 = 18
    static let numberOfLongBucketsDepth0 = 36
    static let numberOfLatBucketsDepth1 = 100
    static let numberOfLongBucketsDepth1 = 100
    static let numberOfLatBucketsDepth2 = 200
    static let numberOfLongBucketsDepth2 = 200

    static let latLongBucketMaxDepth0 = 7200 // cutoff of roughly 12 hours of data for each depth 0 bucket
    static let latLongBucketMaxDepth1 = 1800 // cutoff of roughly 3 hours of data for each depth 1 bucket
    static let latLongBucketMaxDepth2 = 80 // cutoff of roughly 8 mins of data for each depth 2 bucket

    var store: TimelineStore?
   
    public internal(set) var name: ActivityTypeName
    public internal(set) var geoKey: String = ""
    public internal(set) var isShared: Bool
    public internal(set) var version: Int = 0
    internal var geoKeyPrefix = "G"

    public internal(set) var depth: Int
    public internal(set) var accuracyScore: Double?
    public internal(set) var totalSamples: Int = 0

    public internal(set) var lastFetched: Date
    public internal(set) var lastUpdated: Date?
    public internal(set) var transactionDate: Date?
   
    /** movement factors **/
    
    var movingPct: Double = -1
    var coreMotionTypeScores: [CoreMotionActivityTypeName: Double] = [:]
    var speedHistogram: Histogram?
    var stepHzHistogram: Histogram?
    var courseVarianceHistogram: Histogram?
    var xyAccelerationHistogram: Histogram?
    var zAccelerationHistogram: Histogram?
    var horizontalAccuracyHistogram: Histogram?
    var previousSampleActivityTypeScores: [ActivityTypeName: Double] = [:]
    
    /** context factors **/
   
    var courseHistogram: Histogram?
    var altitudeHistogram: Histogram?
    var timeOfDayHistogram: Histogram?
    var serialisedCoordinatesMatrix: String?
    
    lazy var coordinatesMatrix: CoordinatesMatrix? = {
        if let string = self.serialisedCoordinatesMatrix {
            return CoordinatesMatrix(string: string)
        }
        return nil
    }()
    
    var cachedHashValue: Int?
   
    public var latitudeRange: (min: Double, max: Double) = (0, 0)
    public var longitudeRange: (min: Double, max: Double) = (0, 0)

    public var coreMotionTypeScoresArray: [Double] {
        var result: [Double] = []
        for typeName in CoreMotionActivityTypeName.allTypes {
            if let score = coreMotionTypeScores[typeName] {
                result.append(score)
            } else {
                result.append(0)
            }
        }
        return result
    }

    public var previousSampleActivityTypeScoresSerialised: String {
        var result = ""
        for (activityType, score) in previousSampleActivityTypeScores {
            result += "\(activityType.rawValue):\(score);"
        }
        return result
    }

    // MARK: Init

    public init?(dict: [String: Any?], geoKeyPrefix: String? = nil, in store: TimelineStore) {
        self.store = store

        guard let string = dict["name"] as? String, let name = ActivityTypeName(rawValue: string) else {
            return nil
        }
        self.name = name

        self.lastSaved = dict["lastSaved"] as? Date
        self.lastUpdated = dict["lastUpdated"] as? Date
        self.lastFetched = Date()

        if let geoKeyPrefix = geoKeyPrefix {
            self.geoKeyPrefix = geoKeyPrefix
        }

        if let latitudeMin = dict["latitudeMin"] as? Double, let latitudeMax = dict["latitudeMax"] as? Double {
            self.latitudeRange.min = latitudeMin
            self.latitudeRange.max = latitudeMax
        }

        if let longitudeMin = dict["longitudeMin"] as? Double, let longitudeMax = dict["longitudeMax"] as? Double {
            self.longitudeRange.min = longitudeMin
            self.longitudeRange.max = longitudeMax
        }

        isShared = dict["isShared"] as? Bool ?? true

        if let depth = dict["depth"] as? Int { self.depth = depth }
        else if let depth = dict["depth"] as? Int64 { self.depth = Int(depth) }
        else { fatalError("nil model depth") }

        geoKey = dict["geoKey"] as? String ?? inferredGeoKey

        if let version = dict["version"] as? Int { self.version = version }
        else if let version = dict["version"] as? Int64 { self.version = Int(version) }
        
        if let total = dict["totalSamples"] as? Int { totalSamples = total }
        else if let total = dict["totalSamples"] as? Int64 { totalSamples = Int(total) }
        else if let total = dict["totalEvents"] as? Int { totalSamples = total }
        else if let total = dict["totalEvents"] as? Int64 { totalSamples = Int(total) }

        accuracyScore = dict["accuracyScore"] as? Double

        if let updated = dict["lastUpdated"] as? Date {
            lastUpdated = updated
        } else if let updated = dict["lastUpdated"] as? Double { // expecting JS style bullshit milliseconds
            lastUpdated = Date(timeIntervalSince1970: updated / 1000)
        }

        movingPct = dict["movingPct"] as? Double ?? -1

        if let serialised = dict["speedHistogram"] as? String {
            speedHistogram = Histogram(string: serialised)
            speedHistogram?.printModifier = 3.6
            speedHistogram?.printFormat = "%6.1f kmh"
            speedHistogram?.name = "SPEED"
        }

        if let serialised = dict["stepHzHistogram"] as? String {
            stepHzHistogram = Histogram(string: serialised)
            stepHzHistogram?.printFormat = "%7.2f Hz"
            stepHzHistogram?.name = "STEPHZ"
        }

        if let serialised = dict["courseVarianceHistogram"] as? String {
            courseVarianceHistogram = Histogram(string: serialised)
            courseVarianceHistogram?.printFormat = "%10.2f"
            courseVarianceHistogram?.name = "COURSE VARIANCE"
        }

        if let serialised = dict["courseHistogram"] as? String {
            courseHistogram = Histogram(string: serialised)
            courseHistogram?.name = "COURSE"
        }

        if let serialised = dict["altitudeHistogram"] as? String {
            altitudeHistogram = Histogram(string: serialised)
            altitudeHistogram?.name = "ALTITUDE"
        }

        if let serialised = dict["timeOfDayHistogram"] as? String {
            timeOfDayHistogram = Histogram(string: serialised)
            timeOfDayHistogram?.printModifier = 60 / 60 / 60 / 60
            timeOfDayHistogram?.printFormat = "%8.2f h"
            timeOfDayHistogram?.name = "TIME OF DAY"
        }

        if let serialised = dict["xyAccelerationHistogram"] as? String {
            xyAccelerationHistogram = Histogram(string: serialised)
            xyAccelerationHistogram?.name = "WIGGLES XY"
        }

        if let serialised = dict["zAccelerationHistogram"] as? String {
            zAccelerationHistogram = Histogram(string: serialised)
            zAccelerationHistogram?.name = "WIGGLES Z"
        }

        if let serialised = dict["horizontalAccuracyHistogram"] as? String {
            horizontalAccuracyHistogram = Histogram(string: serialised)
            horizontalAccuracyHistogram?.name = "HORIZ ACCURACY"
        }

        serialisedCoordinatesMatrix = dict["coordinatesMatrix"] as? String

        var cmTypeScoreDoubles: [Double]?
        if let cmTypeScores = dict["coreMotionTypeScores"] as? String {
            cmTypeScoreDoubles = cmTypeScores.split(separator: ",", omittingEmptySubsequences: false).map { Double($0) ?? 0 }
        } else if let doubles = dict["coreMotionTypeScores"] as? [Double], !doubles.isEmpty {
            cmTypeScoreDoubles = doubles
        }
        if let doubles = cmTypeScoreDoubles {
            for (index, score) in doubles.enumerated() {
                let name = CoreMotionActivityTypeName.allTypes[index]
                coreMotionTypeScores[name] = score
            }
        }

        if let markovScores = dict["previousSampleActivityTypeScores"] as? String {
            var typeScores: [ActivityTypeName: Double] = [:]
            let typeScoreRows = markovScores.split(separator: ";")
            for row in typeScoreRows {
                let bits = row.split(separator: ":")
                guard let name = ActivityTypeName(rawValue: String(bits[0])) else { continue }
                guard let score = Double(String(bits[1])) else { continue }
                typeScores[name] = score
            }
            previousSampleActivityTypeScores = typeScores
        }

        store.add(self)
    }

    var inferredGeoKey: String {
        return String(format: "\(geoKeyPrefix)D\(depth) \(name) %.2f,%.2f", centerCoordinate.latitude, centerCoordinate.longitude)
    }

    // MARK: - Misc computed properties

    public var completenessScore: Double {
        let parentDepth = depth - 1

        guard parentDepth >= 0 else { return 1.0 }

        var maxEvents: Int
        switch parentDepth {
        case 2: maxEvents = ActivityType.latLongBucketMaxDepth2
        case 1: maxEvents = ActivityType.latLongBucketMaxDepth1
        default: maxEvents = ActivityType.latLongBucketMaxDepth0
        }

        return min(1.0, Double(totalSamples) / Double(maxEvents))
    }

    public var coverageScore: Double {
        if let accuracyScore = accuracyScore {
            return accuracyScore * completenessScore
        }
        return completenessScore
    }
    
    var numberOfLatBuckets: Int {
        switch depth {
        case 2: return ActivityType.numberOfLatBucketsDepth2
        case 1: return ActivityType.numberOfLatBucketsDepth1
        default: return ActivityType.numberOfLatBucketsDepth0
        }
    }
    
    var numberOfLongBuckets: Int {
        switch depth {
        case 2: return ActivityType.numberOfLongBucketsDepth2
        case 1: return ActivityType.numberOfLongBucketsDepth1
        default: return ActivityType.numberOfLongBucketsDepth0
        }
    }
    
    var latitudeWidth: Double { return latitudeRange.max - latitudeRange.min }

    var longitudeWidth: Double { return longitudeRange.max - longitudeRange.min }

    public var centerCoordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitudeRange.min + latitudeWidth * 0.5,
                                      longitude: longitudeRange.min + longitudeWidth * 0.5)
    }
   
    public static func latitudeBinSizeFor(depth: Int) -> Double {
        let depth0 = 180.0 / Double(ActivityType.numberOfLatBucketsDepth0)
        let depth1 = depth0 / Double(ActivityType.numberOfLatBucketsDepth1)
        let depth2 = depth1 / Double(ActivityType.numberOfLatBucketsDepth2)
        
        switch depth {
        case 2: return depth2
        case 1: return depth1
        default: return depth0
        }
    }
    
    public static func longitudeBinSizeFor(depth: Int) -> Double {
        let depth0 = 360.0 / Double(ActivityType.numberOfLongBucketsDepth0)
        let depth1 = depth0 / Double(ActivityType.numberOfLongBucketsDepth1)
        let depth2 = depth1 / Double(ActivityType.numberOfLongBucketsDepth2)
        
        switch depth {
        case 2: return depth2
        case 1: return depth1
        default: return depth0
        }
    }
    
    public static func latitudeRangeFor(depth: Int, coordinate: CLLocationCoordinate2D) -> (min: Double, max: Double) {
        let depth0Range = (min: -90.0, max: 90.0)
        
        switch depth {
        case 2:
            let bucketSize = ActivityType.latitudeBinSizeFor(depth: 1)
            let parentRange = latitudeRangeFor(depth: 1, coordinate: coordinate)
            let bucket = Int((coordinate.latitude - parentRange.min) / bucketSize)
            return (min: parentRange.min + (bucketSize * Double(bucket)),
                    max: parentRange.min + (bucketSize * Double(bucket + 1)))
            
        case 1:
            let bucketSize = ActivityType.latitudeBinSizeFor(depth: 0)
            let parentRange = latitudeRangeFor(depth: 0, coordinate: coordinate)
            let bucket = Int((coordinate.latitude - parentRange.min) / bucketSize)
            return (min: parentRange.min + (bucketSize * Double(bucket)),
                    max: parentRange.min + (bucketSize * Double(bucket + 1)))
            
        default:
            return depth0Range
        }
    }
    
    public static func longitudeRangeFor(depth: Int, coordinate: CLLocationCoordinate2D) -> (min: Double, max: Double) {
        let depth0Range = (min: -180.0, max: 180.0)
        
        switch depth {
        case 2:
            let bucketSize = ActivityType.longitudeBinSizeFor(depth: 1)
            let parentRange = longitudeRangeFor(depth: 1, coordinate: coordinate)
            let bucket = Int((coordinate.longitude - parentRange.min) / bucketSize)
            return (min: parentRange.min + (bucketSize * Double(bucket)),
                    max: parentRange.min + (bucketSize * Double(bucket + 1)))
            
        case 1:
            let bucketSize = ActivityType.longitudeBinSizeFor(depth: 0)
            let parentRange = longitudeRangeFor(depth: 0, coordinate: coordinate)
            let bucket = Int((coordinate.longitude - parentRange.min) / bucketSize)
            return (min: parentRange.min + (bucketSize * Double(bucket)),
                    max: parentRange.min + (bucketSize * Double(bucket + 1)))
            
        default:
            return depth0Range
        }
    }
    
    public func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        return contains(coordinate: coordinate, acceptZeroZero: false)
    }

    func contains(coordinate: CLLocationCoordinate2D, acceptZeroZero: Bool = false) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }

        guard acceptZeroZero || coordinate.latitude != 0 || coordinate.longitude != 0 else { return false }
    
        let latRange = latitudeRange
        let longRange = longitudeRange

        if latRange.min > coordinate.latitude || latRange.max < coordinate.latitude { return false }
        if longRange.min > coordinate.longitude || longRange.max < coordinate.longitude { return false }

        return true
    }
    
    // MARK: - Debug output

    public func printStats() {
        print(statsString)
    }
    
    var statsString: String {
        var output = ""
        
        output += "geoKey:                \(geoKey)\n"
        output += "totalSamples:          \(totalSamples)\n"
        
        if let accuracy = accuracyScore {
            output += String(format: "accuracyScore:         %.2f\n\n", accuracy)
        }
        
        output += "movingPct:             \(String(format: "%.2f", movingPct))\n"
        output += "coreMotionTypeScores:  \(coreMotionTypeScoresString)\n"
        
        if let matrix = coordinatesMatrix {
            output += matrix.description
        } else {
            output += "NO COORDS MATRIX\n"
        }

        if let histogram = speedHistogram { output += String(describing: histogram) + "\n" }
        if let histogram = stepHzHistogram { output += String(describing: histogram) + "\n" }
        if let histogram = xyAccelerationHistogram { output += String(describing: histogram) + "\n" }
        if let histogram = zAccelerationHistogram { output += String(describing: histogram) + "\n" }
        if let histogram = courseVarianceHistogram { output += String(describing: histogram) + "\n" }

        if let histogram = timeOfDayHistogram { output += String(describing: histogram) + "\n" }
        if let histogram = altitudeHistogram { output += String(describing: histogram) + "\n" }
        if let histogram = courseHistogram { output += String(describing: histogram) + "\n" }

        return output
    }

    // MARK: - Saving

    var lastSaved: Date? // TODO: need to decode this at init time

    public func save() {
        do {
            try store?.auxiliaryPool.write { db in
                self.transactionDate = Date()
                try self.save(in: db)
                self.lastSaved = self.transactionDate
            }
        } catch {
            os_log("%@", type: .error, error.localizedDescription)
        }
    }

    public var unsaved: Bool { return lastSaved == nil }
    public func save(in db: Database) throws {
        if unsaved { try insert(db) } else { try update(db) }
    }

    // MARK: - PersistableRecord

    public static let databaseTableName = "ActivityTypeModel"

    public static var persistenceConflictPolicy: PersistenceConflictPolicy {
        return PersistenceConflictPolicy(insert: .replace, update: .abort)
    }

    open func encode(to container: inout PersistenceContainer) {
        container["geoKey"] = geoKey
        container["lastSaved"] = transactionDate ?? lastSaved ?? Date()
        container["version"] = version

        container["name"] = name.rawValue
        container["depth"] = depth
        container["isShared"] = isShared
        container["lastUpdated"] = lastUpdated
        container["totalSamples"] = totalSamples
        container["accuracyScore"] = accuracyScore

        container["latitudeMin"] = latitudeRange.min
        container["latitudeMax"] = latitudeRange.max
        container["longitudeMin"] = longitudeRange.min
        container["longitudeMax"] = longitudeRange.max

        container["movingPct"] = movingPct
        container["coreMotionTypeScores"] = coreMotionTypeScoresArray.map { String($0) }.joined(separator: ",")
        container["previousSampleActivityTypeScores"] = previousSampleActivityTypeScoresSerialised

        container["altitudeHistogram"] = altitudeHistogram?.serialised
        container["courseHistogram"] = courseHistogram?.serialised
        container["courseVarianceHistogram"] = courseVarianceHistogram?.serialised
        container["speedHistogram"] = speedHistogram?.serialised
        container["stepHzHistogram"] = stepHzHistogram?.serialised
        container["timeOfDayHistogram"] = timeOfDayHistogram?.serialised
        container["xyAccelerationHistogram"] = xyAccelerationHistogram?.serialised
        container["zAccelerationHistogram"] = zAccelerationHistogram?.serialised
        container["horizontalAccuracyHistogram"] = horizontalAccuracyHistogram?.serialised
        container["coordinatesMatrix"] = coordinatesMatrix?.serialised
    }
    
    // MARK: - Equatable

    open func hash(into hasher: inout Hasher) {
        hasher.combine(geoKey)
    }

    public static func ==(lhs: ActivityType, rhs: ActivityType) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
    
}
