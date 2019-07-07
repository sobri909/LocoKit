//
// Created by Matt Greenfield on 5/07/17.
// Copyright (c) 2017 Big Paua. All rights reserved.
//

import CoreLocation
import LocoKitCore

/**
 A composite, high level representation of the device's location, motion, and activity states over a brief
 duration of time.
 
 The current sample can be retrieved from `LocomotionManager.highlander.locomotionSample()`.
 
 ## Dynamic Sample Sizes
 
 Each sample's duration is dynamically determined, depending on the quality and quantity of available ocation
 and motion data. Samples sizes typically range from 10 to 60 seconds, however varying conditions can sometimes
 produce sample durations outside those bounds.
 
 Higher quality and quantity of available data results in shorter sample durations, with more specific
 representations of single moments in time.
 
 Lesser quality or quantity of available data result in longer sample durations, thus representing the average or most
 common states and location over the sample period instead of a single specific moment.
 */
open class LocomotionSample: ActivityTypeTrainable, Codable {

    public let sampleId: UUID

    /// The timestamp for the weighted centre of the sample period. Equivalent to `location.timestamp`.
    public let date: Date

    public let secondsFromGMT: Int?
    
    // MARK: Location Properties

    /** 
     The sample's smoothed location, equivalent to the weighted centre of the sample's `filteredLocations`.
     
     This is the most high level location value, representing the final result of all available filtering and smoothing
     algorithms. This value is most useful for drawing smooth, coherent paths on a map for end user consumption.
     */
    public let location: CLLocation?
    
    /**
     The raw locations received over the sample duration.
     */
    public let rawLocations: [CLLocation]?
    
    /**
     The Kalman filtered locations recorded over the sample duration.
     */
    public let filteredLocations: [CLLocation]?
    
    /// The moving or stationary state for the sample. See `MovingState` for details on possible values.
    public let movingState: MovingState

    // The recording state of the LocomotionManager at the time the sample was taken.
    public let recordingState: RecordingState
    
    // MARK: Motion Properties
    
    /** 
     The user's walking/running/cycling cadence (steps per second) over the sample duration.
     
     This value is taken from [CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer). and will
     only contain a usable value if `startCoreMotion()` has been called on the LocomotionManager.
     
     - Note: If the user is travelling by vehicle, this value may report a false value due to bumpy motion being 
     misinterpreted as steps by CMPedometer.
     */
    public let stepHz: Double?
    
    /** 
     The degree of variance in course direction over the sample duration.
     
     A value of 0.0 represents a perfectly straight path. A value of 1.0 represents complete inconsistency of 
     direction between each location.
     
     This value may indicate several different conditions, such as high or low location accuracy (ie clean or erratic
     paths due to noisy location data), or the user travelling in either a straight or curved path. However given that 
     the filtered locations already have the majority of path jitter removed, this value should not be considered in
     isolation from other factors - no firm conclusions can be drawn from it alone.
     */
    public let courseVariance: Double?
    
    /**
     The average amount of accelerometer motion on the XY plane over the sample duration.
     
     This value can be taken to be `mean(abs(xyAccelerations)) + (std(abs(xyAccelerations) * 3.0)`, with 
     xyAccelerations being the recorded accelerometer X and Y values over the sample duration. Thus it represents the
     mean + 3SD of the unsigned acceleration values.
     */
    public let xyAcceleration: Double?
    
    /**
     The average amount of accelerometer motion on the Z axis over the sample duration.
     
     This value can be taken to be `mean(abs(zAccelerations)) + (std(abs(zAccelerations) * 3.0)`, with
     zAccelerations being the recorded accelerometer Z values over the sample duration. Thus it represents the
     mean + 3SD of the unsigned acceleration values.
     */
    public let zAcceleration: Double?
    
    // MARK: Activity Type Properties
    
    /**
     The highest scoring Core Motion activity type 
     ([CMMotionActivity](https://developer.apple.com/documentation/coremotion/cmmotionactivity)) at the time of the 
     sample's `date`.
     */
    public let coreMotionActivityType: CoreMotionActivityTypeName?

    public var classifierResults: ClassifierResults?

    public var activityType: ActivityTypeName? {
        return confirmedType ?? classifiedType
    }

    public var confirmedType: ActivityTypeName?

    public var previousSampleConfirmedType: ActivityTypeName?

    internal var _classifiedType: ActivityTypeName?
    public var classifiedType: ActivityTypeName? {
        if let cached = _classifiedType { return cached }
        guard let results = classifierResults else { return nil }
        guard results.best.score > 0 else { return nil }
        if !results.moreComing {
            _classifiedType = results.best.name
        }
        return results.best.name
    }

    // MARK: - Convenience Getters
    
    public lazy var timeOfDay: TimeInterval = { return self.date.sinceStartOfDay }()

    public var hasUsableCoordinate: Bool { return location?.hasUsableCoordinate ?? false }

    public var isNolo: Bool { return location?.isNolo ?? true }

    private var _localTimeZone: TimeZone?
    public var localTimeZone: TimeZone? {
        if let cached = _localTimeZone { return cached }

        // create one from utc offset
        if let secondsFromGMT = secondsFromGMT {
            _localTimeZone = TimeZone(secondsFromGMT: secondsFromGMT)
            return _localTimeZone
        }

        guard let location = location else { return nil }
        guard location.hasUsableCoordinate else { return nil }

        // try to fetch one from remote, hopefully available on next access
        CLPlacemarkCache.fetchPlacemark(for: location) { [weak self] placemark in
            self?._localTimeZone = placemark?.timeZone
        }

        return nil
    }

    public func distance(from otherSample: LocomotionSample) -> CLLocationDistance? {
        guard let myLocation = location, let theirLocation = otherSample.location else { return nil }
        return myLocation.distance(from: theirLocation)
    }

    // MARK: - Required initialisers

    public required init(from sample: ActivityBrainSample) {
        self.sampleId = UUID()

        self.date = sample.date
        self.secondsFromGMT = TimeZone.current.secondsFromGMT()
        self.recordingState = LocomotionManager.highlander.recordingState
        self.movingState = sample.movingState
        self.location = sample.location
        self.rawLocations = sample.rawLocations
        self.filteredLocations = sample.filteredLocations
        self.courseVariance = sample.courseVariance
        self.xyAcceleration = sample.xyAcceleration
        self.zAcceleration = sample.zAcceleration
        self.coreMotionActivityType = sample.coreMotionActivityType

        if let sampleStepHz = sample.stepHz {
            self.stepHz = sampleStepHz
        } else if LocomotionManager.highlander.recordPedometerEvents {
            self.stepHz = 0 // store nil as zero, because CMPedometer returns nil while stationary
        } else {
            self.stepHz = nil
        }
    }

    public required init(from dict: [String: Any?]) {
        if let uuidString = dict["sampleId"] as? String {
            self.sampleId = UUID(uuidString: uuidString)!
        } else {
            self.sampleId = UUID()
        }
        self.date = dict["date"] as! Date
        if let secondsFromGMT = dict["secondsFromGMT"] as? Int { self.secondsFromGMT = secondsFromGMT }
        else if let secondsFromGMT = dict["secondsFromGMT"] as? Int64 { self.secondsFromGMT = Int(secondsFromGMT) }
        else { self.secondsFromGMT = nil }
        self.movingState = MovingState(rawValue: dict["movingState"] as! String)!
        self.recordingState = RecordingState(rawValue: dict["recordingState"] as! String)!
        self.stepHz = dict["stepHz"] as? Double
        self.courseVariance = dict["courseVariance"] as? Double
        self.xyAcceleration = dict["xyAcceleration"] as? Double
        self.zAcceleration = dict["zAcceleration"] as? Double
        if let rawValue = dict["coreMotionActivityType"] as? String {
            self.coreMotionActivityType = CoreMotionActivityTypeName(rawValue: rawValue)
        } else {
            self.coreMotionActivityType = nil
        }
        if let location = dict["location"] as? CLLocation {
            self.location = location
        } else {
            var locationDict = dict
            locationDict["timestamp"] = dict["date"]
            self.location = CLLocation(from: locationDict)
        }
        if let rawValue = dict["confirmedType"] as? String {
            self.confirmedType = ActivityTypeName(rawValue: rawValue)
        } else {
            self.confirmedType = nil
        }
        if let rawValue = dict["classifiedType"] as? String {
            self._classifiedType = ActivityTypeName(rawValue: rawValue)
        } else {
            self._classifiedType = nil
        }
        if let rawValue = dict["previousSampleConfirmedType"] as? String {
            self.previousSampleConfirmedType = ActivityTypeName(rawValue: rawValue)
        } else {
            self.previousSampleConfirmedType = nil
        }

        self.rawLocations = nil
        self.filteredLocations = nil
    }

    /// For recording samples to mark special events such as app termination.
    public required init(date: Date, location: CLLocation? = nil, movingState: MovingState = .uncertain,
                         recordingState: RecordingState) {
        self.sampleId = UUID()

        self.recordingState = recordingState
        self.movingState = movingState
        self.date = date
        self.secondsFromGMT = TimeZone.current.secondsFromGMT()

        self.filteredLocations = []
        self.rawLocations = []
        self.location = location

        self.stepHz = nil
        self.courseVariance = nil
        self.xyAcceleration = nil
        self.zAcceleration = nil
        self.coreMotionActivityType = nil
    }

    // MARK: - Codable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.sampleId = (try? container.decode(UUID.self, forKey: .sampleId)) ?? UUID()
        self.date = try container.decode(Date.self, forKey: .date)
        self.secondsFromGMT = try? container.decode(Int.self, forKey: .secondsFromGMT)
        self.movingState = try container.decode(MovingState.self, forKey: .movingState)
        self.recordingState = try container.decode(RecordingState.self, forKey: .recordingState)
        self.stepHz = try? container.decode(Double.self, forKey: .stepHz)
        self.courseVariance = try? container.decode(Double.self, forKey: .courseVariance)
        self.xyAcceleration = try? container.decode(Double.self, forKey: .xyAcceleration)
        self.zAcceleration = try? container.decode(Double.self, forKey: .zAcceleration)
        self.coreMotionActivityType = try? container.decode(CoreMotionActivityTypeName.self, forKey: .coreMotionActivityType)
        self.confirmedType = try? container.decode(ActivityTypeName.self, forKey: .confirmedType)

        if let codableLocation = try? container.decode(CodableLocation.self, forKey: .location) {
            self.location = CLLocation(from: codableLocation)
        } else {
            self.location = nil
        }
        
        self.rawLocations = nil
        self.filteredLocations = nil
    }

    open func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sampleId, forKey: .sampleId)
        try container.encode(date, forKey: .date)
        if secondsFromGMT != nil { try container.encode(secondsFromGMT, forKey: .secondsFromGMT) }
        try container.encode(location?.codable, forKey: .location)
        try container.encode(movingState, forKey: .movingState)
        try container.encode(recordingState, forKey: .recordingState)
        if stepHz != nil { try container.encode(stepHz, forKey: .stepHz) }
        if courseVariance != nil { try container.encode(courseVariance, forKey: .courseVariance) }
        if xyAcceleration != nil { try container.encode(xyAcceleration, forKey: .xyAcceleration) }
        if zAcceleration != nil { try container.encode(zAcceleration, forKey: .zAcceleration) }
        if coreMotionActivityType != nil { try container.encode(coreMotionActivityType, forKey: .coreMotionActivityType) }
        if confirmedType != nil { try container.encode(confirmedType, forKey: .confirmedType) }
    }

    private enum CodingKeys: String, CodingKey {
        case sampleId
        case date
        case secondsFromGMT
        case location
        case movingState
        case recordingState
        case stepHz
        case courseVariance
        case xyAcceleration
        case zAcceleration
        case coreMotionActivityType
        case confirmedType
    }
}

extension LocomotionSample: CustomStringConvertible {
    public var description: String {
        guard let locations = filteredLocations else { return "LocomotionSample \(sampleId)" }
        let seconds = locations.dateInterval?.duration ?? 0
        let locationsN = locations.count
        let locationsHz = locationsN > 0 && seconds > 0 ? Double(locationsN) / seconds : 0.0
        return String(format: "\(locationsN) locations (%.1f Hz), \(String(duration: seconds))", locationsHz)
    }
}

extension LocomotionSample: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(sampleId) }
    public static func ==(lhs: LocomotionSample, rhs: LocomotionSample) -> Bool { return lhs.sampleId == rhs.sampleId }
}

public extension Array where Element: LocomotionSample {
    var duration: TimeInterval {
        guard let firstDate = first?.date, let lastDate = last?.date else { return 0 }
        return lastDate.timeIntervalSince(firstDate)
    }
    var distance: CLLocationDistance {
        return compactMap { $0.hasUsableCoordinate ? $0.location : nil }.distance
    }
    var weightedMeanAltitude: CLLocationDistance? {
        return compactMap { $0.hasUsableCoordinate ? $0.location : nil }.weightedMeanAltitude
    }
    var horizontalAccuracyRange: AccuracyRange? {
        return compactMap { $0.hasUsableCoordinate ? $0.location : nil }.horizontalAccuracyRange
    }
    var verticalAccuracyRange: AccuracyRange? {
        return compactMap { $0.hasUsableCoordinate ? $0.location : nil }.verticalAccuracyRange
    }
    var haveAnyUsableLocations: Bool {
        for sample in self { if sample.hasUsableCoordinate { return true } }
        return false
    }
    func radius(from center: CLLocation) -> Radius {
        return compactMap { $0.hasUsableCoordinate ? $0.location : nil }.radius(from: center)
    }

    // MARK: -

    var center: CLLocation? { return CLLocation(centerFor: self) }

    /**
     The weighted centre for an array of samples
     - Note: More weight will be given to samples classified with "stationary" type
     */
    var weightedCenter: CLLocation? {
        if self.isEmpty { return nil }

        guard let accuracyRange = self.horizontalAccuracyRange else { return nil }

        // only one sample? that's the centre then
        if self.count == 1, let first = self.first {
            return first.hasUsableCoordinate ? first.location : nil
        }

        var sumx: Double = 0, sumy: Double = 0, sumz: Double = 0, totalWeight: Double = 0

        for sample in self where sample.hasUsableCoordinate {
            guard let location = sample.location else { continue }

            let lat = location.coordinate.latitude.radiansValue
            let lng = location.coordinate.longitude.radiansValue

            var weight = location.horizontalAccuracyWeight(inRange: accuracyRange)

            // give extra weight to stationary samples
            if let activityType = sample.activityType, activityType == .stationary { weight *= 3 }

            sumx += (cos(lat) * cos(lng)) * weight
            sumy += (cos(lat) * sin(lng)) * weight
            sumz += sin(lat) * weight
            totalWeight += weight
        }

        if totalWeight == 0 { return nil }

        let meanx = sumx / totalWeight
        let meany = sumy / totalWeight
        let meanz = sumz / totalWeight

        return CLLocation(x: meanx, y: meany, z: meanz)
    }
}
