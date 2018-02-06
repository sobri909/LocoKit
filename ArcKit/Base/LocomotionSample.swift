//
// Created by Matt Greenfield on 5/07/17.
// Copyright (c) 2017 Big Paua. All rights reserved.
//

import CoreLocation
import ArcKitCore

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
open class LocomotionSample: ActivityTypeTrainable, TimelineObject, Codable {

    // MARK: TimelineObject

    public var objectId: UUID { return sampleId }
    public weak var store: TimelineStore?
    internal(set) public var inTheStore = false
    open var currentInstance: LocomotionSample? { return store?.sample(for: sampleId) }

    public let sampleId: UUID

    /// The timestamp for the weighted centre of the sample period. Equivalent to `location.timestamp`.
    public let date: Date
    
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

    // MARK: References

    public var timelineItemId: UUID?

    private weak var _timelineItem: TimelineItem?

    /// The sample's parent `TimelineItem`, if recording is being done via a `TimelineManager`.
    public var timelineItem: TimelineItem? {
        get {
            if let cached = self._timelineItem, cached.itemId == self.timelineItemId { return cached.currentInstance }
            if let itemId = self.timelineItemId, let item = store?.item(for: itemId) { self._timelineItem = item }
            return self._timelineItem
        }
        set(newValue) {
            let oldValue = self.timelineItem

            // no change? do nothing
            if newValue == oldValue { return }

            // store the new value
            self._timelineItem = newValue
            self.timelineItemId = newValue?.itemId

            // disconnect the old relationship
            oldValue?.remove(self)

            // complete the other side of the new relationship
            newValue?.add(self)
        }
    }

    internal(set) public var classifierResults: ClassifierResults?
    internal(set) public var unfilteredClassifierResults: ClassifierResults?

    public var activityType: ActivityTypeName? {
        if let confirmedType = confirmedType { return confirmedType }
        return classifierResults?.first?.name
    }

    public var confirmedType: ActivityTypeName?

    public var classifiedType: ActivityTypeName? { return classifierResults?.first?.name }

    // MARK: Convenience Getters
    
    public lazy var timeOfDay: TimeInterval = { return self.date.sinceStartOfDay }()

    public var hasUsableCoordinate: Bool { return location?.hasUsableCoordinate ?? false }

    public var isNolo: Bool { return location?.isNolo ?? true }

    public func distance(from otherSample: LocomotionSample) -> CLLocationDistance? {
        guard let myLocation = location, let theirLocation = otherSample.location else { return nil }
        return myLocation.distance(from: theirLocation)
    }

    // MARK: Convenience initialisers

    public convenience init(from dict: [String: Any?], in store: TimelineStore) {
        self.init(from: dict)
        store.add(self)
    }

    public convenience init(from sample: ActivityBrainSample, in store: TimelineStore) {
        self.init(from: sample)
        store.add(self)
    }

    public convenience init(date: Date, recordingState: RecordingState, in store: TimelineStore) {
        self.init(date: date, recordingState: recordingState)
        store.add(self)
    }

    // MARK: Required initialisers

    public required init(from sample: ActivityBrainSample) {
        self.sampleId = UUID()

        self.date = sample.date
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
        if let uuidString = dict["timelineItemId"] as? String { self.timelineItemId = UUID(uuidString: uuidString)! }
        self.date = dict["date"] as! Date
        self.movingState = MovingState(rawValue: dict["movingState"] as! String)!
        self.recordingState = RecordingState(rawValue: dict["recordingState"] as! String)!
        self.stepHz = dict["stepHz"] as? Double
        self.courseVariance = dict["courseVariance"] as? Double
        self.xyAcceleration = dict["xyAcceleration"] as? Double
        self.zAcceleration = dict["zAcceleration"] as? Double
        if let typeName = dict["coreMotionActivityType"] as? String {
            self.coreMotionActivityType = CoreMotionActivityTypeName(rawValue: typeName)
        } else {
            self.coreMotionActivityType = nil
        }
        if let typeName = dict["confirmedType"] as? String {
            self.confirmedType = ActivityTypeName(rawValue: typeName)
        }
        if let location = dict["location"] as? CLLocation {
            self.location = location
        } else {
            var locationDict = dict
            locationDict["timestamp"] = dict["date"]
            self.location = CLLocation(from: locationDict)
        }

        self.rawLocations = nil
        self.filteredLocations = nil
    }

    /// For recording samples to mark special events such as app termination.
    public required init(date: Date, recordingState: RecordingState) {
        self.sampleId = UUID()

        self.recordingState = recordingState
        self.movingState = .uncertain
        self.date = date

        self.filteredLocations = []
        self.rawLocations = []
        self.location = nil

        self.stepHz = nil
        self.courseVariance = nil
        self.xyAcceleration = nil
        self.zAcceleration = nil
        self.coreMotionActivityType = nil
    }

    // MARK: Codable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.sampleId = (try? container.decode(UUID.self, forKey: .sampleId)) ?? UUID()
        self.timelineItemId = try? container.decode(UUID.self, forKey: .timelineItemId)
        self.date = try container.decode(Date.self, forKey: .date)
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
        try container.encode(timelineItemId, forKey: .timelineItemId)
        try container.encode(date, forKey: .date)
        try container.encode(location?.codable, forKey: .location)
        try container.encode(movingState, forKey: .movingState)
        try container.encode(recordingState, forKey: .recordingState)
        try container.encode(stepHz, forKey: .stepHz)
        try container.encode(courseVariance, forKey: .courseVariance)
        try container.encode(xyAcceleration, forKey: .xyAcceleration)
        try container.encode(zAcceleration, forKey: .zAcceleration)
        try container.encode(coreMotionActivityType, forKey: .coreMotionActivityType)
        try container.encode(confirmedType, forKey: .confirmedType)
    }

    private enum CodingKeys: String, CodingKey {
        case sampleId
        case timelineItemId
        case date
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
    public var hashValue: Int { return sampleId.hashValue }
    public static func ==(lhs: LocomotionSample, rhs: LocomotionSample) -> Bool { return lhs.sampleId == rhs.sampleId }
}

public extension Array where Element: LocomotionSample {
    public var center: CLLocation? { return CLLocation(centerFor: self) }
    public var weightedCenter: CLLocation? { return CLLocation(weightedCenterFor: self) }
    public var duration: TimeInterval {
        guard let firstDate = first?.date, let lastDate = last?.date else { return 0 }
        return lastDate.timeIntervalSince(firstDate)
    }
    public var distance: CLLocationDistance { return flatMap { $0.location }.distance }
    public var weightedMeanAltitude: CLLocationDistance? { return flatMap { $0.location }.weightedMeanAltitude }
    public var horizontalAccuracyRange: AccuracyRange? { return flatMap { $0.location }.horizontalAccuracyRange }
    public var verticalAccuracyRange: AccuracyRange? { return flatMap { $0.location }.verticalAccuracyRange }
    public var haveAnyUsableLocations: Bool {
        for sample in self { if sample.hasUsableCoordinate { return false } }
        return true
    }
    func radius(from center: CLLocation) -> Radius { return flatMap { $0.location }.radius(from: center) }
}
