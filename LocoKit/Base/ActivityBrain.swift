//
// Created by Matt Greenfield on 22/12/15.
// Copyright (c) 2015 Big Paua. All rights reserved.
//

import os.log
import CoreLocation
#if canImport(CoreMotion)
import CoreMotion
#endif

public class ActivityBrain {

    // settings
    internal static let worstAllowedLocationAccuracy: CLLocationDistance = 300
    internal static let worstAllowedPastSampleRadius: CLLocationDistance = 65 // small enough for slow walking to be detected

    internal static let maximumSampleAge: TimeInterval = 60
    internal static let minimumWakeupConfidenceN = 8
    internal static let minimumConfidenceN = 6
    internal static let minimumRequiredN = 8
    internal static let maximumRequiredN = 60
    internal static let speedSampleN: Int = 4

    public var processHistoricalLocations = false

    public static let highlander = ActivityBrain()

    private let altitudeKalman = KalmanAltitude(qMetresPerSecond: 3)
    private let coordinatesKalman = KalmanCoordinates(qMetresPerSecond: 4)

    private var coreMotionActivityConfidences: [CMActivityTypeEvent] = []
    
    public lazy var presentSample: ActivityBrainSample = {
        return ActivityBrainSample(mutex: self.samplesMutex, wigglesMutex: self.wigglesMutex)
    }()
    
    private lazy var pastSample: ActivityBrainSample = {
        return ActivityBrainSample(mutex: self.samplesMutex, wigglesMutex: self.wigglesMutex)
    }()
    
    private var pastSampleFrozen = false

    public var stationaryPeriodStart: Date?

    var samplesMutex: UnfairLock = UnfairLock()
    var wigglesMutex: UnfairLock = UnfairLock()

    // MARK: -

    private init() {}

}

// MARK: - Public

public extension ActivityBrain {

    static var historicalLocationsBrain: ActivityBrain {
        let brain = ActivityBrain()
        brain.processHistoricalLocations = true
        return brain
    }

    func add(rawLocation location: CLLocation, trustFactor: Double? = nil) {
        presentSample.add(rawLocation: location)

        // feed the kalmans
        if let trustFactor = trustFactor, trustFactor < 1 {
            let accuracyFudge = kCLLocationAccuracyHundredMeters * (1.0 - trustFactor)
            let fudgedLocation = CLLocation(
                coordinate: location.coordinate, altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy + accuracyFudge,
                verticalAccuracy: location.verticalAccuracy + accuracyFudge,
                course: location.course, speed: location.speed,
                timestamp: location.timestamp)
            altitudeKalman.add(location: fudgedLocation)
            coordinatesKalman.add(location: fudgedLocation)

        } else { // nil or 1.0 trustFactor
            altitudeKalman.add(location: location)
            coordinatesKalman.add(location: location)
        }

        // feed the kalmans into the samples
        if let location = kalmanLocation {
            add(filteredLocation: location)
        }
    }

    // MARK: -

    func update() {
        trimThePresentSample()
        presentSample.update()

        if !pastSampleFrozen {
            trimThePastSample()
            pastSample.update()
        }

        // bounded radius should start by being the max of these two
        pastSample.radiusBounded = max(presentSample.nonNegativeHorizontalAccuracy, pastSample.radius)

        // don't let it get so big that normal walking speed can't escape it
        if !pastSampleFrozen {
            pastSample.radiusBounded = min(pastSample.radiusBounded, ActivityBrain.worstAllowedPastSampleRadius)
        }

        // the payoff
        updateMoving()

        // if present is big enough, unfreeze the past
        if pastSampleFrozen && presentSample.n >= dynamicMinimumConfidenceN {
            pastSampleFrozen = false
        }
    }

    // MARK: -

    func freezeTheBrain() {
        pastSampleFrozen = true

        stationaryPeriodStart = nil

        flushThePresentSample()

        // make the kalmans be super eager to accept the first location on wakeup
        altitudeKalman.resetVarianceTo(accuracy: ActivityBrain.worstAllowedLocationAccuracy)
        coordinatesKalman.resetVarianceTo(accuracy: ActivityBrain.worstAllowedLocationAccuracy)
    }

    var movingState: MovingState {
        return presentSample.movingState
    }

    var horizontalAccuracy: Double {
        return presentSample.nonNegativeHorizontalAccuracy
    }

    // MARK: -

    var kalmanLocation: CLLocation? {
        guard let kalCoord = coordinatesKalman.coordinate else {
            return nil
        }

        guard let rawLoc = coordinatesKalman.unfilteredLocation else {
            return nil
        }

        if let kalAlt = altitudeKalman.altitude, let rawAltLoc = altitudeKalman.unfilteredLocation {
            return CLLocation(coordinate: kalCoord, altitude: kalAlt, horizontalAccuracy: rawLoc.horizontalAccuracy,
                              verticalAccuracy: rawAltLoc.verticalAccuracy, course: rawLoc.course, speed: rawLoc.speed,
                              timestamp: coordinatesKalman.date)

        } else {
            return CLLocation(coordinate: kalCoord, altitude: 0, horizontalAccuracy: rawLoc.horizontalAccuracy,
                              verticalAccuracy: -1, course: rawLoc.course, speed: rawLoc.speed,
                              timestamp: coordinatesKalman.date)
        }
    }

    func resetKalmans() {
        coordinatesKalman.reset()
        altitudeKalman.reset()
    }

    // MARK: -

    var kalmanRequiredN: Double {
        let adjust: Double = 0.8
        let accuracy = coordinatesKalman.accuracy
        return accuracy > 0 ? accuracy * adjust : 30
    }

    // slower speed means higher required (zero speed == max required)
    var speedRequiredN: Double {
        let maxSpeedReq: Double = 8 // maximum required N for slow speeds
        let speedReqKmh: Double = 5 // faster than this requires no extra N

        let kmh = presentSample.speed * 3.6

        // negative speed is useless here, so fall back to max required
        guard kmh >= 0 else {
            return maxSpeedReq
        }

        return (maxSpeedReq - (kmh * (maxSpeedReq / speedReqKmh))).clamped(min: 0, max: maxSpeedReq)
    }

    var requiredN: Int {
        let required = Int(kalmanRequiredN + speedRequiredN)
        return required.clamped(min: ActivityBrain.minimumRequiredN, max: ActivityBrain.maximumRequiredN)
    }

    var dynamicMinimumConfidenceN: Int {
        return pastSampleFrozen ? ActivityBrain.minimumWakeupConfidenceN : ActivityBrain.minimumConfidenceN
    }

    // MARK: -

    func spread(_ locations: [CLLocation]) -> TimeInterval {
        if locations.count < 2 {
            return 0
        }
        let firstLocation = locations.first!
        let lastLocation = locations.last!
        return lastLocation.timestamp.timeIntervalSince(firstLocation.timestamp)
    }

    // MARK: -

    func add(pedoData: CMPedometerData) {
        presentSample.add(pedoData: pedoData)
    }

    func add(deviceMotion: CMDeviceMotion) {
        presentSample.addDeviceMotion(deviceMotion)
    }
    @available(macOS, unavailable)
    @available(iOS 13.0, watchOS 6.0, *)
    func add(cmMotionActivity activity: CMMotionActivity) {
        for name in CoreMotionActivityTypeName.allTypes {
            if let boolValue = activity.value(forKey: name.rawValue) as? Bool, boolValue == true {
                add(cmMotionActivityConfidence: activity.confidence, name: name, date: activity.startDate)
            }
        }
    }

}


// MARK: - Internal

internal extension ActivityBrain {

    func add(filteredLocation location: CLLocation) {

        // reject locations that are too old
        if !processHistoricalLocations && location.timestamp.age > ActivityBrain.maximumSampleAge {
            os_log("Rejecting out of date location (age: %@)", type: .info, String(format: "%.0f seconds", location.timestamp.age))
            return
        }
       
        if !location.hasUsableCoordinate {
            os_log("Rejecting location with unusable coordinate", type: .info)
            return
        }

        presentSample.add(filteredLocation: location)
    }

    // MARK: -

    func trimThePresentSample() {
        while true {
            var needsTrim = false

            // don't let the N go bigger than necessary
            if presentSample.n > requiredN {
                needsTrim = true
            }

            // don't let the sample drift into the past
            if !processHistoricalLocations && presentSample.age > ActivityBrain.maximumSampleAge {
                needsTrim = true
            }

            // past and present samples should have similar Ns
            if !pastSampleFrozen && presentSample.n > pastSample.n + 4 {
                needsTrim = true
            }

            guard needsTrim else {
                return
            }

            guard let oldest = presentSample.firstLocation else {
                return
            }

            presentSample.removeLocation(oldest)

            if !pastSampleFrozen {
                pastSample.add(filteredLocation: oldest)
            }
        }
    }

    func trimThePastSample() {

        // past n should be <= present n
        while pastSample.n > 2 && pastSample.n > presentSample.n {
            guard let oldest = pastSample.firstLocation else {
                break
            }
            pastSample.removeLocation(oldest)
        }
    }

    func flushThePresentSample() {
        presentSample.flush()
        coreMotionActivityConfidences.removeAll()
    }

    // MARK: -

    func updateMoving() {
        defer {
            if presentSample.movingState != .stationary {
                stationaryPeriodStart = nil
            }
        }

        // empty present sample is insta-fail
        guard presentSample.n > 0 else {
            presentSample.movingState = .uncertain
            return
        }

        // horiz accuracy over threshold means no certains
        if presentSample.horizontalAccuracy > ActivityBrain.worstAllowedLocationAccuracy {
            presentSample.movingState = .uncertain
            return
        }

        // overlapping samples always mean stationary, regardless of N
        if presentIsInsidePast() {
            presentSample.movingState = .stationary

            // mark the start of a stationary period
            if stationaryPeriodStart == nil {
                stationaryPeriodStart = Date()
            }

            return
        }

        // not overlapping, and enough N, so we can confidently say moving
        if presentSample.n >= dynamicMinimumConfidenceN {
            presentSample.movingState = .moving
            return
        }

        // not enough N, so have to say uncertain
        presentSample.movingState = .uncertain
    }

    func presentIsInsidePast() -> Bool {
        guard let presentCentre = presentSample.location else {
            return false
        }

        guard let pastCentre = pastSample.location else {
            return false
        }

        return presentCentre.distance(from: pastCentre) <= pastSample.radiusBounded
    }

    // MARK: -

    func add(cmMotionActivityConfidence: CMMotionActivityConfidence, name: CoreMotionActivityTypeName, date: Date) {
        var best: CMActivityTypeEvent?
        samplesMutex.sync {
            if let existing = coreMotionActivityConfidences.filter({ $0.name == name }).first {
                coreMotionActivityConfidences.remove(existing)
            }

            coreMotionActivityConfidences.append(CMActivityTypeEvent(name: name, confidence: cmMotionActivityConfidence, date: date))

            coreMotionActivityConfidences = coreMotionActivityConfidences.sorted {
                $0.currentConfidence > $1.currentConfidence
            }

            best = coreMotionActivityConfidences.first
        }

        // add the current best to the present sample
        if best != nil {
            presentSample.add(cmActivityTypeEvent: best!)
        }
    }

    var currentCoreMotionActivityType: CMActivityTypeEvent? {
        return coreMotionActivityConfidences.first
    }

}
