//
// Created by Matt Greenfield on 28/10/15.
// Copyright (c) 2015 Big Paua. All rights reserved.
//

import os.log
import CoreMotion
import CoreLocation
import ArcKitCore

public extension NSNotification.Name {
    public static let locomotionSampleUpdated = Notification.Name("locomotionSampleUpdated")
    public static let didChangeAuthorizationStatus = Notification.Name("didChangeAuthorizationStatus")
    public static let didVisit = Notification.Name("didVisit")
}

/**
 The central class for interacting with ArcKit location and activity recording. All actions should be performed on
 the `LocomotionManager.highlander` singleton.
 
 ## Overview
 
 LocomotionManager monitors raw device location and motion data and applies filtering and smoothing algorithms to 
 produce a stream of high level `LocomotionSample` objects, a composite representation of the device and user's 
 location and activity state at each point in time.
 
 Locomotion samples include filtered and smoothed locations, the user's moving or stationary state, current
 activity type (eg walking, running, cycling, etc), step hertz (ie walking, running, or cycling cadence), and more.

 ### Energy Efficiency
 
 LocomotionManager dynamically adjusts various device monitoring parameters, balancing current conditions and desired
 results to achieve the desired accuracy in the most energy efficient manner.
 
 ## Core Location
 
 To start recording location data call `startCoreLocation()`, and call `stopCoreLocation()` to stop.
 
 ### Update Notifications

 LocomotionManager will send `locomotionSampleUpdated` notifications via the system default 
 [NotificationCenter](https://developer.apple.com/documentation/foundation/notificationcenter) when each new location 
 arrives.

 Notifications will also be periodically sent even when no new location data is arriving, to indicate other
 changes to the current state. The location in these samples may differ from previous even though new location data is 
 not available, due to older raw locations being discarded from the sample.
 
 ### Raw, Filtered, and Smoothed Data
 
 ArcKit provides three levels of location data: Raw CLLocations, filtered CLLocations, and high level
 location and activity state LocomotionSamples. See the documentation for `rawLocation`, `filteredLocation`,
 and `LocomotionSample` for details on each.

 ### Moving State
 
 When each raw location arrives LocomotionManager updates its determination of whether the user is moving or stationary, 
 based on changes between current and previous locations over time. The most up to date determination is available
 either from the `movingState` property on the LocomotionManager, or on the latest `locomotionSample`. See the
 `movingState` documentation for further details.
 
 ## Core Motion

 To start recording Core Motion data call `startCoreMotion()`, and call `stopCoreMotion()` to stop.

 Doing so will result in extra `LocomotionSample` properties being filled, and will greatly increase the accuracy of
 `ActivityTypeClassifier` results.

 See the `LocomotionSample` documentation for details on the available motion and activity properties, and
 `ActivityTypeClassifier` documentation for details on how to make use of ArcKit's machine learning classifiers.
 */
public class LocomotionManager: NSObject {
   
    // internal settings
    internal static let fallbackUpdateCycle: TimeInterval = 30
    internal static let maximumDesiredAccuracyIncreaseFrequency: TimeInterval = 10
    internal static let maximumDesiredAccuracyDecreaseFrequency: TimeInterval = 60
    internal static let maximumDesiredLocationAccuracyInVisit = kCLLocationAccuracyHundredMeters
    internal static let wiggleHz: Double = 4
    
    internal let pedo = CMPedometer()
    internal let activityManager = CMMotionActivityManager()

    internal lazy var wiggles: CMMotionManager = {
        let wiggles = CMMotionManager()
        wiggles.deviceMotionUpdateInterval = 1.0 / LocomotionManager.wiggleHz
        return wiggles
    }()
    
    // states
    public internal(set) var recordingCoreLocation = false
    public internal(set) var recordingCoreMotion = false
    internal var watchingTheM = false
    internal var watchingThePedo = false
    internal var watchingTheWiggles = false
    internal var coreMotionPermission = false
    internal var lastAccuracyUpdate: Date?
    
    internal var fallbackUpdateTimer: Timer?
    
    internal lazy var wigglesQueue: OperationQueue = {
        return OperationQueue()
    }()
    
    internal lazy var coreMotionQueue: OperationQueue = {
        return OperationQueue()
    }()
    
    // MARK: The Singleton
    
    /// The LocomotionManager singleton instance, through which all actions should be performed.
    public static let highlander = LocomotionManager()
    
    // MARK: Settings

    /**
     The maximum desired location accuracy in metres. Set this value to your highest required accuracy.
     
     ### Dynamic Accuracy Adjustments
     
     LocomotionManager dynamically adjusts the internal CLLocationManager's `desiredAccuracy` over time, within the
     range of `maximumDesiredLocationAccuracy` and the maximum accepted accuracy of 500 metres. Various heuristics are 
     used to determine the current best possible accuracy, to avoid requesting a value beyond what can be currently
     achieved, thus avoiding wasteful energy consumption.
     
     For most uses the default value will achieve best results. Lower values will encourage the device to more quickly 
     attain peak possible accuracy, at the expense of battery life. Lower values will extend battery life, at the cost 
     of slower attainment of peak accuracy, or in some cases settling on accuracy levels below the best attainable by 
     the hardware and sensors.
    
     ### Thresholds and Magic Numbers
     
     - iOS will usually attempt to exceed the requested accuracy, and may exceed it by a wide margin. For
     example if clear GPS line of sight is available, peak accuracy of 5 metres will be achieved even when only 
     requesting 50 metres or even 100 metres. However the higher the desired accuracy, the less effort
     iOS will put into achieving peak possible accuracy.
     
     - Under some conditions, setting a value of 65 metres may allow the device to use wifi triangulation alone, without
     engaging GPS, thus reducing energy consumption. Wifi triangulation is typically more energy efficient than GPS.
     
     - Setting a value above 100 metres will greatly reduce the `movingState` accuracy, and is thus not recommended.
     */
    public var maximumDesiredLocationAccuracy: CLLocationAccuracy = 30

    /**
     Assign a delegate to this property if you would like to have the internal location manager's
     `CLLocationManagerDelegate` events forwarded to you after they have been processed internally.
     */
    public var locationManagerDelegate: CLLocationManagerDelegate?

    // MARK: Raw, Filtered, and Smoothed Data
    
    /**
     The most recently received raw CLLocation.
     */
    public var rawLocation: CLLocation? {
        return locationManager.location
    }
    
    /**
     The most recent [Kalman filtered](https://en.wikipedia.org/wiki/Kalman_filter) CLLocation, based on the most 
     recently received raw CLLocation.
     
     If you require strictly real time locations, these filtered locations offer a reasonable intermediate
     state between the raw data and the fully smoothed locomotion samples, with coordinates as near as possible to now.
     
     - Note: Both the location coordinate and location altitude are Kalman filtered, however all other CLLocation 
     properties (course, speed, etc) are identical to the values in `rawLocation`. For fully smoothed and denoised 
     motion properties you should use `locomotionSample` instead.
     */
    public var filteredLocation: CLLocation? {
        return ActivityBrain.highlander.kalmanLocation
    }
    
    /**
     Returns a new `LocomotionSample` representing the most recent filtered and smoothed locomotion state, with
     combined location, motion, and activity properties.

     Note: This method will create a new sample instance on each call. As such, you should retain and reuse the
        resulting sample until a new sample is needed.
     */
    public func locomotionSample() -> LocomotionSample {
        return LocomotionSample(sample: ActivityBrain.highlander.presentSample)
    }
    
    // MARK: Current Moving State
    
    /**
     The `MovingState` of the current `LocomotionSample`.
     
     - Note: This value is as near to real time as possible, but typically represents the user's state between 6 and 60 
     seconds in the past, with the age depending on the quality of available location data over that period of time. 
     The higher the accuracy of current location data, the closer to now the reported moving state will be. If you need 
     to know an exact timestamp to match the moving state, you should instead take a `LocomotionSample` instance from 
     `locomotionSample` and use `movingState` and `date` on that sample.
     */
    public var movingState: MovingState {
        guard recordingCoreLocation else {
            return .uncertain
        }
        
        return ActivityBrain.highlander.movingState
    }

    // MARK: Starting and Stopping Location Recording
    
    /**
     Start monitoring device location.
     
     `NSNotification.Name.didUpdateLocations` notifications will be sent through the system `NotificationCenter` as 
     each location arrives.
     
     Amongst other internal tasks, this will call `startUpdatingLocation()` on the internal location manager.
     */
    public func startCoreLocation() {
        if recordingCoreLocation {
            return
        }
        
        guard haveLocationPermission else {
            os_log("NO LOCATION PERMISSION")
            return
        }
        
        // start updating locations
        locationManager.desiredAccuracy = maximumDesiredLocationAccuracy
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        
        // to avoid an immediate update on first location arrival (which will be way too high)
        lastAccuracyUpdate = Date()
       
        // make sure we update even if not getting locations
        restartTheUpdateTimer()
        
        recordingCoreLocation = true
    }
    
    /**
     Stop monitoring device location.
     
     Amongst other internal tasks, this will call `stopUpdatingLocation()` on the internal location manager.
     */
    public func stopCoreLocation() {
        if !recordingCoreLocation {
            return
        }
        
        // prep the brain for next wakeup
        ActivityBrain.highlander.freezeTheBrain()

        stopTheUpdateTimer()
        
        locationManager.stopUpdatingLocation()
        
        recordingCoreLocation = false
    }
    
    /**
     Reset the internal state of the location Kalman filters. When the next raw location arrives, `filteredLocation` 
     will be identical to the raw location.
     */
    public func resetLocationFilter() {
        ActivityBrain.highlander.resetKalmans()
    }

    // MARK: Starting and Stopping Motion and Activity Recording
    
    /**
     Start monitoring Core Motion activity types, pedometer data, and accelerometer data. 
     
     Starting this service will result in several extra properties being filled in the locomotion samples.
     
     - Note: Starting this service will not begin the delivery of `locomotionSampleUpdated` notifications. Update 
     notifications are currently only started and stopped by the Core Location recording methods.
     */
    public func startCoreMotion() {
        startTheM()
        startThePedo()
        startTheWiggles()
        
        recordingCoreMotion = true
    }
    
    /**
     Stop monitoring Core Motion activity types, pedometer data, and accelerometer data.
     */
    public func stopCoreMotion() {
        stopTheM()
        stopThePedo()
        stopTheWiggles()
        
        recordingCoreMotion = false
    }
    
    // MARK: Misc Helpers and Convenience Wrappers
    
    /// A convenience wrapper for `CLLocationManager.locationServicesEnabled()`
    public var locationServicesAreOn: Bool {
        return CLLocationManager.locationServicesEnabled()
    }
    
    /**
     A convenience wrapper for the `CLLocationManager` authorisation request methods.
     
     You can also interact directly with the internal `locationManager` to perform these tasks.
     
     - Parameters:
     - background: If `true`, will call `requestAlwaysAuthorization()`, otherwise `requestWhenInUseAuthorization()`
     will be called. Default value is `false`.
     */
    public func requestLocationPermission(background: Bool = false) {
        if background {
            locationManager.requestAlwaysAuthorization()
            
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    /**
     The device authorisation state for monitoring Core Motion data.
     */
    public var haveCoreMotionPermission: Bool {
        if coreMotionPermission {
            return true
        }
       
        if #available(iOS 11.0, *) {
            coreMotionPermission = CMMotionActivityManager.authorizationStatus() == .authorized
        } else {
            coreMotionPermission = CMSensorRecorder.isAuthorizedForRecording()
        }
        
        return coreMotionPermission
    }
    
    /**
     A convenience wrapper for `CLLocationManager.authorizationStatus()`.
     
     Returns true if status is either `authorizedWhenInUse` or `authorizedAlways`.
     */
    public var haveLocationPermission: Bool {
        let status = CLLocationManager.authorizationStatus()
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
    
    /**
     A convenience wrapper for `CLLocationManager.authorizationStatus()`.
     
     Returns true if status is `authorizedAlways`.
     */
    public var haveBackgroundLocationPermission: Bool {
        return CLLocationManager.authorizationStatus() == .authorizedAlways
    }
    
    // MARK: The Internal CLLocationManager
    
    /**
     The internal CLLocationManager manager.
     
     Direct interaction with this should be avoided. Starting and stopping location monitoring should instead be done
     through LocomotionManager's `startCoreLocation()` and `stopCoreLocation()` methods.
     
     - Warning: The CLLocationManager's `desiredAccuracy` and `distanceFilter` properties are managed internally.
     Changes to them will be overriden, and may interfere with LocomotionManager's `movingState` detection. The
     `delegate` should also not be changed, as this will disable LocomotionManager, and potentially result in the
     untimely deaths of small cute animals in Madagascar.
     */
    public private(set) lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.distanceFilter = kCLDistanceFilterNone
        manager.desiredAccuracy = self.maximumDesiredLocationAccuracy
        manager.pausesLocationUpdatesAutomatically = false
        
        manager.delegate = self
        return manager
    }()
    
    // because there can be only one highlander
    private override init() {}
}

internal extension LocomotionManager {

    func startTheM() {
        if watchingTheM {
            return
        }
        
        watchingTheM = true
        
        activityManager.startActivityUpdates(to: coreMotionQueue) { activity in
            if let activity = activity {
                self.coreMotionPermission = true
                ActivityBrain.highlander.add(cmMotionActivity: activity)
            }
        }
    }

    func stopTheM() {
        if !watchingTheM {
            return
        }
        
        activityManager.stopActivityUpdates()
        
        watchingTheM = false
    }

}

internal extension LocomotionManager {
   
    func startThePedo() {
        if watchingThePedo {
            return
        }
        
        watchingThePedo = true
        
        pedo.startUpdates(from: Date()) { pedoData, error in
            if let error = error {
                os_log("error: %@", String(describing: error))
                
            } else if let pedoData = pedoData {
                ActivityBrain.highlander.add(pedoData: pedoData)
            }
        }
    }
    
    func stopThePedo() {
        if !watchingThePedo {
            return
        }
        
        pedo.stopUpdates()
        
        watchingThePedo = false
    }
    
}

internal extension LocomotionManager {
   
    func startTheWiggles() {
        if watchingTheWiggles {
            return
        }
        
        watchingTheWiggles = true
        
        wiggles.startDeviceMotionUpdates(to: wigglesQueue) { motion, error in
            if let error = error {
                os_log("error: %@", String(describing: error))
                
            } else if let motion = motion {
                self.coreMotionPermission = true
                ActivityBrain.highlander.add(deviceMotion: motion)
            }
        }
    }
    
    func stopTheWiggles() {
        if !watchingTheWiggles {
            return
        }
        
        wiggles.stopDeviceMotionUpdates()
        
        watchingTheWiggles = false
    }
    
}

internal extension LocomotionManager {
    
    func restartTheUpdateTimer() {
        fallbackUpdateTimer?.invalidate()
        fallbackUpdateTimer = Timer.scheduledTimer(timeInterval: LocomotionManager.fallbackUpdateCycle, target: self,
                                                   selector: #selector(LocomotionManager.updateAndNotify),
                                                   userInfo: nil, repeats: false)
    }
    
    func stopTheUpdateTimer() {
        fallbackUpdateTimer?.invalidate()
        fallbackUpdateTimer = nil
    }
    
}

internal extension LocomotionManager {
    
    @objc func updateAndNotify(rawLocation: CLLocation? = nil) {
        guard recordingCoreLocation || recordingCoreMotion else {
            return
        }
        
        // make the state fresh
        ActivityBrain.highlander.update()
        
        var info: [AnyHashable: Any]?
        
        // only attach locations if we got here from an incoming location
        if let rawLocation = rawLocation {
            info = ["rawLocation": rawLocation]
            if let kalmanLocation = ActivityBrain.highlander.kalmanLocation {
                info?["filteredLocation"] = kalmanLocation
            }
        }
        
        // reset the fallback timer
        restartTheUpdateTimer()
        
        // tell everyone
        NotificationCenter.default.post(Notification(name: .locomotionSampleUpdated, object: self, userInfo: info))
    }
    
    func updateDesiredAccuracy() {
        if let last = lastAccuracyUpdate, last.age < LocomotionManager.maximumDesiredAccuracyIncreaseFrequency {
            return
        }
        
        let currentlyDesired = locationManager.desiredAccuracy
        let currentlyAchieved = ActivityBrain.highlander.horizontalAccuracy
        
        let steps = [
            kCLLocationAccuracyHundredMeters,
            kCLLocationAccuracyNearestTenMeters,
            kCLLocationAccuracyBest,
            kCLLocationAccuracyBestForNavigation
        ]
        
        var updatedDesire = steps.first { $0 < currentlyAchieved }!
        
        var minimum = maximumDesiredLocationAccuracy
        
        // if getting wifi triangulation or worse, and in a visit, fall back to 100 metres
        if currentlyAchieved >= 65 && ActivityBrain.highlander.movingState == .stationary {
            minimum = max(LocomotionManager.maximumDesiredLocationAccuracyInVisit, minimum)
        }
        
        updatedDesire.clamp(min: minimum, max: kCLLocationAccuracyThreeKilometers)

        // decrease desired accuracy less often than increase
        if updatedDesire > currentlyDesired, let last = lastAccuracyUpdate,
            last.age < LocomotionManager.maximumDesiredAccuracyDecreaseFrequency
        {
            return
        }
        
        if updatedDesire != currentlyDesired {
            locationManager.desiredAccuracy = updatedDesire
            lastAccuracyUpdate = Date()
        }
    }
    
}

extension LocomotionManager: CLLocationManagerDelegate {
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        let note = Notification(name: .didChangeAuthorizationStatus, object: self, userInfo: ["status": status])
        NotificationCenter.default.post(note)

        // forward the event
        locationManagerDelegate?.locationManager?(manager, didChangeAuthorization: status)
    }

    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let note = Notification(name: .didVisit, object: self, userInfo: ["visit": visit])
        NotificationCenter.default.post(note)

        // forward the event
        locationManagerDelegate?.locationManager?(manager, didVisit: visit)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard recordingCoreLocation else {
            return
        }
        
        for location in locations {

            // feed the brain
            ActivityBrain.highlander.add(rawLocation: location)
           
            // the payoff
            updateAndNotify(rawLocation: location)
        }
        
        // fiddle the GPS/wifi/cell triangulation accuracy
        updateDesiredAccuracy()

        // forward the event
        locationManagerDelegate?.locationManager?(manager, didUpdateLocations: locations)
    }

}

extension Comparable {
    mutating func clamp(min: Self, max: Self) {
        if self < min { self = min }
        if self > max { self = max }
    }
}
