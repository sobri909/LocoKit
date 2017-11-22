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
public class LocomotionSample: NSObject, ActivityTypeClassifiable {
    
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
    public let rawLocations: [CLLocation]
    
    /**
     The Kalman filtered locations recorded over the sample duration.
     */
    public let filteredLocations: [CLLocation]
    
    /// The moving or stationary state for the sample. See `MovingState` for details on possible values.
    public let movingState: MovingState
    
    // MARK: Motion Properties
    
    /** 
     The user's walking/running/cycling cadence (steps per second) over the sample duration.
     
     This value is taken from [CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer). and will
     only contain a usable value if `startCoreMotion()` has been called on the LocomotionManager.
     
     - Note: If the user is travelling by vehicle, this value may report a false value due to bumpy motion being 
     misinterpreted as steps by CMPedometer.
     */
    public let stepHz: Double
    
    /** 
     The degree of variance in course direction over the sample duration.
     
     A value of 0.0 represents a perfectly straight path. A value of 1.0 represents complete inconsistency of 
     direction between each location.
     
     This value may indicate several different conditions, such as high or low location accuracy (ie clean or erratic
     paths due to noisy location data), or the user travelling in either a straight or curved path. However given that 
     the filtered locations already have the majority of path jitter removed, this value should not be considered in
     isolation from other factors - no firm conclusions can be drawn from it alone.
     */
    public let courseVariance: Double
    
    /**
     The average amount of accelerometer motion on the XY plane over the sample duration.
     
     This value can be taken to be `mean(abs(xyAccelerations)) + (std(abs(xyAccelerations) * 3.0)`, with 
     xyAccelerations being the recorded accelerometer X and Y values over the sample duration. Thus it represents the
     mean + 3SD of the unsigned acceleration values.
     */
    public let xyAcceleration: Double
    
    /**
     The average amount of accelerometer motion on the Z axis over the sample duration.
     
     This value can be taken to be `mean(abs(zAccelerations)) + (std(abs(zAccelerations) * 3.0)`, with
     zAccelerations being the recorded accelerometer Z values over the sample duration. Thus it represents the
     mean + 3SD of the unsigned acceleration values.
     */
    public let zAcceleration: Double
    
    // MARK: Activity Type Properties
    
    /**
     The highest scoring Core Motion activity type 
     ([CMMotionActivity](https://developer.apple.com/documentation/coremotion/cmmotionactivity)) at the time of the 
     sample's `date`.
     */
    public let coreMotionActivityType: CoreMotionActivityTypeName?
    
    // MARK: Convenience Getters
    
    /// A convenience getter for the sample's time interval since start of day.
    public lazy var timeOfDay: TimeInterval = {
        return self.date.sinceStartOfDay
    }()
    
    init(sample: ActivityBrainSample) {
        if let location = sample.location  {
            self.rawLocations = sample.rawLocations
            self.filteredLocations = sample.filteredLocations
            self.location = CLLocation(coordinate: location.coordinate, altitude: location.altitude,
                                       horizontalAccuracy: location.horizontalAccuracy,
                                       verticalAccuracy: location.verticalAccuracy, course: sample.course,
                                       speed: sample.speed, timestamp: location.timestamp)
            self.date = location.timestamp
            
        } else {
            self.filteredLocations = []
            self.rawLocations = []
            self.location = nil
            self.date = Date()
        }
        
        self.movingState = sample.movingState
        self.courseVariance = sample.courseVariance
        self.xyAcceleration = sample.xyAcceleration
        self.zAcceleration = sample.zAcceleration
        self.stepHz = sample.stepHz
        
        self.coreMotionActivityType = sample.coreMotionActivityType
    }

    // MARK: CustomStringConvertible

    public override var description: String {
        let seconds = filteredLocations.dateInterval?.duration ?? 0
        let locationsN = filteredLocations.count
        let locationsHz = locationsN > 0 && seconds > 0 ? Double(locationsN) / seconds : 0.0
        return String(format: "\(locationsN) locations (%.1f Hz), \(String(duration: seconds))", locationsHz)
    }
}
