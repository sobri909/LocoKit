//
// Created by Matt Greenfield on 28/10/15.
// Copyright (c) 2015 Big Paua. All rights reserved.
//

import os.log
import CoreMotion
import CoreLocation
import ArcKitCore

/**
 Custom notification events that the LocomotionManager may send.
 */
public extension NSNotification.Name {

    /**
     `locomotionSampleUpdated` is sent whenever an updated LocomotionSample is available.

     Typically this indicates that a new CLLocation has arrived, however this notification will also be periodically
     sent even when no new location data is arriving, to indicate other changes to the current state. The location in
     these samples may differ from previous even though new location data is not available, due to older raw locations
     being discarded from the sample.
     */
    public static let locomotionSampleUpdated = Notification.Name("locomotionSampleUpdated")

    /**
     `willStartRecording` is sent when recording is about to begin or resume.
     */
    public static let willStartRecording = Notification.Name("willStartRecording")

    /**
     `recordingStateChanged` is sent after each `recordingState` change.
     */
    public static let recordingStateChanged = Notification.Name("recordingStateChanged")

    /**
     `movingStateChanged` is sent after each `movingState` change.
     */
    public static let movingStateChanged = Notification.Name("movingStateChanged")

    /**
     `willStartSleepMode` is sent when sleep mode is about to begin or resume.

     - Note: This includes both transitions from `recording` state and `wakeup` state.
     */
    public static let willStartSleepMode = Notification.Name("willStartSleepMode")

    /**
     `startedSleepMode` is sent after transitioning from `recording` state to `sleeping` state.
     */
    public static let startedSleepMode = Notification.Name("startedSleepMode")

    /**
     `stoppedSleepMode` is sent after transitioning from `sleeping` state to `recording` state.
     */
    public static let stoppedSleepMode = Notification.Name("stoppedSleepMode")

    // broadcasted CLLocationManagerDelegate events
    public static let didChangeAuthorizationStatus = Notification.Name("didChangeAuthorizationStatus")
    public static let didVisit = Notification.Name("didVisit")
}

/**
 The central class for interacting with ArcKit location and motion recording. All actions should be performed on
 the `LocomotionManager.highlander` singleton.
 
 ## Overview
 
 LocomotionManager monitors raw device location and motion data and applies filtering and smoothing algorithms to 
 produce a stream of high level `LocomotionSample` objects, a composite representation of the device and user's 
 location and activity state at each point in time.
 
 Locomotion samples include filtered and smoothed locations, the user's moving or stationary state, current
 activity type (eg walking, running, cycling, etc), step hertz (ie walking, running, or cycling cadence), and more.

 #### Energy Efficiency
 
 LocomotionManager dynamically adjusts various device monitoring parameters, balancing current conditions and desired
 results to achieve the desired accuracy in the most energy efficient manner.
 
 ## Starting and Stopping Recording
 
 To start recording location and motion data call `startRecording()`, and call `stopRecording()` to stop.
 
 #### Update Notifications

 LocomotionManager will send `locomotionSampleUpdated` notifications via the system default 
 [NotificationCenter](https://developer.apple.com/documentation/foundation/notificationcenter) when each new location 
 arrives.

 #### Raw, Filtered, and Smoothed Data
 
 ArcKit provides three levels of location data: Raw CLLocations, filtered CLLocations, and high level
 location and activity state LocomotionSamples. See the documentation for `rawLocation`, `filteredLocation`,
 and `LocomotionSample` for details on each.

 #### Moving State
 
 When each raw location arrives LocomotionManager updates its determination of whether the user is moving or stationary, 
 based on changes between current and previous locations over time. The most up to date determination is available
 either from the `movingState` property on the LocomotionManager, or on the latest `locomotionSample`. See the
 `movingState` documentation for further details.
 */
@objc public class LocomotionManager: NSObject {
   
    // internal settings
    internal static let fallbackUpdateCycle: TimeInterval = 30
    internal static let maximumDesiredAccuracyIncreaseFrequency: TimeInterval = 10
    internal static let maximumDesiredAccuracyDecreaseFrequency: TimeInterval = 60
    internal static let maximumDesiredLocationAccuracyInVisit = kCLLocationAccuracyHundredMeters
    internal static let wiggleHz: Double = 4
    
    public let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()

    private lazy var wiggles: CMMotionManager = {
        let wiggles = CMMotionManager()
        wiggles.deviceMotionUpdateInterval = 1.0 / LocomotionManager.wiggleHz
        return wiggles
    }()

    private var _recordingState: RecordingState = .off

    /**
     The LocomotionManager's current `RecordingState`.
     */
    public private(set) var recordingState: RecordingState {
        get {
            return _recordingState
        }
        set(newValue) {
            let oldValue = _recordingState
            _recordingState = newValue

            // notify on recording state changes
            if newValue != oldValue {
                NotificationCenter.default.post(Notification(name: .recordingStateChanged, object: self, userInfo: nil))
            }
        }
    }

    // internal states
    internal var watchingTheM = false
    internal var watchingThePedometer = false
    internal var watchingTheWiggles = false
    internal var coreMotionPermission = false
    internal var lastAccuracyUpdate: Date?
    
    internal var fallbackUpdateTimer: Timer?
    internal var wakeupTimer: Timer?

    internal lazy var wigglesQueue: OperationQueue = {
        return OperationQueue()
    }()
    
    internal lazy var coreMotionQueue: OperationQueue = {
        return OperationQueue()
    }()
    
    // MARK: The Singleton
    
    /// The LocomotionManager singleton instance, through which all actions should be performed.
    @objc public static let highlander = LocomotionManager()
    
    // MARK: Settings

    /**
     The maximum desired location accuracy in metres. Set this value to your highest required accuracy.
     
     For most uses the default value will achieve best results. Lower values will encourage the device to more quickly
     attain peak possible accuracy, at the expense of battery life. Higher values will extend battery life, at the cost
     of slower attainment of peak accuracy, or in some cases settling on accuracy levels below the best attainable by
     the hardware and sensors.

     - Note: If `dynamicallyAdjustDesiredAccuracy` is true, LocomotionManager will periodically adjust the
     internal CLLocationManager's `desiredAccuracy` to best match the current best possible accuracy based on local
     conditions, to avoid wasteful energy use and improve battery life.

     - Warning: Setting a value above 100 metres will greatly reduce the `movingState` accuracy, and is thus not
     recommended.

     #### GPS, Wifi, And Cell Tower Triangulation Thresholds
     
     - iOS will usually attempt to exceed the requested accuracy, and may exceed it by a wide margin. For
     example if clear GPS line of sight is available, peak accuracy of 5 metres will be achieved even when only 
     requesting 50 metres or even 100 metres. However the higher the desired accuracy, the less effort
     iOS will put into achieving peak possible accuracy.
     
     - Under some conditions, setting a value of 65 metres or above may allow the device to use wifi triangulation
     alone, without engaging GPS, thus reducing energy consumption. Wifi triangulation is typically more energy
     efficient than GPS.
     */
    @objc public var maximumDesiredLocationAccuracy: CLLocationAccuracy = 30

    /**
     Whether LocomotionManager should dynamically adjust the internal CLLocationManager's `desiredAccuracy` to best
     match local conditions. It is recommended to leave this enabled, to avoid wasteful GPS energy use inside
     buildings.

     If set to true, periodic adjustments are made within the range of `maximumDesiredLocationAccuracy` and
     `kCLLocationAccuracyHundredMeters`. Various heuristics are used to determine the current best possible accuracy,
     to avoid requesting a value beyond what can be currently achieved, thus avoiding wasteful energy consumption.

     If set to false, `desiredAccuracy` will be set to `maximumDesiredLocationAccuracy` and not modified.
     */
    @objc public var dynamicallyAdjustDesiredAccuracy: Bool = true

    /**
     Assign a delegate to this property if you would like to have the internal location manager's
     `CLLocationManagerDelegate` events forwarded to you after they have been processed internally.
     */
    @objc public var locationManagerDelegate: CLLocationManagerDelegate?

    // MARK: Core Motion Settings

    /**
     Whether or not to record pedometer events. If this option is enabled, `LocomotionSample.stepHz` will be set with
     the results.

     - Note: If you are making use of `ActivityTypeClassifier` it is recommended to leave this option enabled, in order
     to increase classifier results accuracy. This is particularly important for the accurate detection of walking,
     running, and cycling.
     */
    @objc public var recordPedometerEvents: Bool = true

    /**
     Whether or not to record accelerometer events. If this option is enabled, `LocomotionSample.xyAcceleration` and
     `LocomotionSample.zAcceleration` will be set with the results.

     - Note: If you are making use of `ActivityTypeClassifier`, enabling this option will increase classifier results
     accuracy.
     */
    @objc public var recordAccelerometerEvents: Bool = true

    /**
     Whether or not to record Core Motion activity type events. If this option is enabled,
     `LocomotionSample.coreMotionActivityType` will be set with the results.

     - Note: If you are making use of `ActivityTypeClassifier`, enabling this option will increase classifier results
     accuracy.
     */
    @objc public var recordCoreMotionActivityTypeEvents: Bool = true

    // MARK: Sleep Mode Settings

    /**
     Whether LocomotionManager should enter a low power "sleep mode" while stationary, in order to reduce energy
     consumption and extend battery life during long recording sessions.
     */
    @objc public var useLowPowerSleepModeWhileStationary: Bool = true

    /**
     Whether or not LocomotionManager should wake from sleep mode and resume recording when no location data is
     available.

     Under some conditions, a device might stop returning any recent or new CLLocations, for extended periods of time.
     This may be due to a lack of available triangulation sources, for example the user is inside a building (thus
     GPS is unavailable) and the building has no wifi (thus wifi triangulation is unavailable). The device may also
     decide to delay location updates for energy saving reasons.

     Whilst in sleep mode, it is typically best to ignore this lack of location data, and instead remain in sleep mode,
     in order to avoid unnecessary energy consumption.

     However there are cases where it may not be safe to assume that a lack of location data implies that the user is
     still stationary. The most common exception case being underground train trips. In these edge cases you may want
     to instead treat the lack of location data as significant, and resume recording.

     - Warning: This setting should be left unchanged unless you have confident reason to do otherwise. Changing this
     setting to true may unnecessarily increase energy consumption.
    */
    @objc public var ignoreNoLocationDataDuringWakeups: Bool = true

    /**
     How long the LocomotionManager should wait before entering sleep mode, once the user is stationary.

     Setting a shorter duration will reduce energy consumption and improve battery life, but also increase the risk
     of undesirable gaps in the recording data. For example a car travelling in heavy traffic may perform many brief
     stops, lasting less than a few minutes. If the LocomotionManager enters sleep mode during one of these stops, it
     will not notice the user has resumed moving until the next wakeup cycle (see `sleepCycleDuration`).
     */
    @objc public var sleepAfterStationaryDuration: TimeInterval = 180

    /**
     The duration to wait before performing brief "wakeup" checks whilst in sleep mode.

     Wakeups allow the LocomotionManager to periodically check whether the user is still stationary, or whether they
     have resumed moving. If the user has resumed moving, LocomotionManager will exit sleep mode and resume recording.

     - Note: During each wakeup, LocomotionManager will briefly make use of GPS level location accuracy, which has an
     unavoidable energy cost. Setting a longer sleep cycle duration will reduce the number and frequency of wakeups,
     thus reducing energy consumption and improving battery life.
     */
    @objc public var sleepCycleDuration: TimeInterval = 60

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
        return LocomotionSample(from: ActivityBrain.highlander.presentSample)
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
        if recordingState == .off {
            return .uncertain
        }
        
        return ActivityBrain.highlander.movingState
    }

    // MARK: Starting and Stopping Recording
    
    /**
     Start monitoring device location and motion.
     
     `NSNotification.Name.didUpdateLocations` notifications will be sent through the system `NotificationCenter` as 
     each location arrives.
     
     Amongst other internal tasks, this will call `startUpdatingLocation()` on the internal location manager.
     */
    public func startRecording() {
        if recordingState == .recording {
            return
        }

        guard haveLocationPermission else {
            os_log("NO LOCATION PERMISSION")
            return
        }

        // notify that we're about to start
        NotificationCenter.default.post(Notification(name: .willStartRecording, object: self))

        // start updating locations
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.desiredAccuracy = maximumDesiredLocationAccuracy
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()

        // start the motion gimps
        startCoreMotion()
        
        // to avoid a desiredAccuracy update on first location arrival (which will have unacceptably bad accuracy)
        lastAccuracyUpdate = Date()
       
        // make sure we update even if not getting locations
        restartTheUpdateTimer()

        let previousState = recordingState
        recordingState = .recording

        // tell everyone that sleep mode has ended (ie we went from sleep/wakeup to recording)
        if previousState == .wakeup || previousState == .sleeping {
            let note = Notification(name: .stoppedSleepMode, object: self, userInfo: nil)
            NotificationCenter.default.post(note)
        }
    }
    
    /**
     Stop monitoring device location.
     
     Amongst other internal tasks, this will call `stopUpdatingLocation()` on the internal location manager.
     */
    public func stopRecording() {
        if recordingState == .off {
            return
        }

        // prep the brain for next startup
        ActivityBrain.highlander.freezeTheBrain()

        // stop the timers
        stopTheUpdateTimer()
        wakeupTimer?.invalidate()
        wakeupTimer = nil

        // stop the location manager
        locationManager.stopUpdatingLocation()

        // stop the motion gimps
        stopCoreMotion()
        
        recordingState = .off
    }
    
    /**
     Reset the internal state of the location Kalman filters. When the next raw location arrives, `filteredLocation` 
     will be identical to the raw location.
     */
    public func resetLocationFilter() {
        ActivityBrain.highlander.resetKalmans()
    }

    /**
     This method is temporarily public because the only way to request Core Motion permission is to just go ahead and
     start using Core Motion. I will make this method private soon, and provide a more tidy way to trigger a Core
     Motion permission request modal.
     */
    public func startCoreMotion() {
        startTheM()
        startThePedometer()
        startTheWiggles()
    }

    private func stopCoreMotion() {
        stopTheM()
        stopThePedometer()
        stopTheWiggles()
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
    @objc public private(set) lazy var locationManager: CLLocationManager = {
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

private extension LocomotionManager {

    private func startSleeping() {
        if recordingState == .sleeping {
            return
        }

        // make sure we're supposed to be here
        guard useLowPowerSleepModeWhileStationary else {
            return
        }

        // notify that we're going to sleep
        let note = Notification(name: .willStartSleepMode, object: self, userInfo: nil)
        NotificationCenter.default.post(note)

        // kill the gimps
        stopCoreMotion()

        // set the location manager to ask for nothing and ignore everything
        locationManager.desiredAccuracy = Double.greatestFiniteMagnitude
        locationManager.distanceFilter = CLLocationDistanceMax

        // reset the wakeup timer
        wakeupTimer?.invalidate()
        wakeupTimer = Timer.scheduledTimer(timeInterval: sleepCycleDuration, target: self,
                                           selector: #selector(LocomotionManager.startWakeup), userInfo: nil,
                                           repeats: false)

        let previousState = recordingState
        recordingState = .sleeping

        // tell everyone that sleep mode has started (ie we went from recording to sleep)
        if previousState == .recording {
            let note = Notification(name: .startedSleepMode, object: self, userInfo: nil)
            NotificationCenter.default.post(note)
        }
    }

    @objc private func startWakeup() {

        // only allowed to start a wakeup from sleeping state
        if recordingState != .sleeping {
            return
        }

        // make the location manager receptive again
        locationManager.desiredAccuracy = maximumDesiredLocationAccuracy
        locationManager.distanceFilter = kCLDistanceFilterNone

        recordingState = .wakeup
    }

    private func touchTheRecordingState() {
        switch recordingState {
        case .off:
            return

        case .wakeup:
            switch movingState {
            case .stationary:

                // if confidently stationary, go back to sleep
                startSleeping()

            case .moving:

                // if confidently moving, should start recording
                startRecording()

            case .uncertain:

                // if settings say to ignore nolos during wakeups, go back to sleep (empty sample == nolo)
                if ActivityBrain.highlander.presentSample.filteredLocations.isEmpty && ignoreNoLocationDataDuringWakeups {
                    print("IGNORING NOLO DURING WAKEUP")
                    startSleeping()

                } else {

                    // could be moving, so let's fire up the gimps to get a head start on the data delay
                    startCoreMotion()
                }
            }

        case .recording, .sleeping:
            if needToBeRecording {
                startRecording()
            } else {
                startSleeping()
            }
        }
    }

    private var needToBeRecording: Bool {
        if movingState == .moving {
            return true
        }

        if recordingState == .recording && !readyForSleepMode {
            return true
        }

        return false
    }

    private var readyForSleepMode: Bool {
        guard let stationary = ActivityBrain.highlander.stationaryPeriodStart else {
            return false
        }

        // have been stationary for longer than the required duration?
        if stationary.age > sleepAfterStationaryDuration {
            return true
        }

        return false
    }
}

private extension LocomotionManager {

    private func startTheM() {
        if watchingTheM {
            return
        }

        guard recordCoreMotionActivityTypeEvents else {
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

    private func stopTheM() {
        if !watchingTheM {
            return
        }
        
        activityManager.stopActivityUpdates()
        
        watchingTheM = false
    }

}

private extension LocomotionManager {
   
    private func startThePedometer() {
        if watchingThePedometer {
            return
        }

        guard recordPedometerEvents else {
            return
        }
        
        watchingThePedometer = true
        
        pedometer.startUpdates(from: Date()) { pedoData, error in
            if let error = error {
                os_log("error: %@", String(describing: error))
                
            } else if let pedoData = pedoData {
                ActivityBrain.highlander.add(pedoData: pedoData)
            }
        }
    }
    
    private func stopThePedometer() {
        if !watchingThePedometer {
            return
        }
        
        pedometer.stopUpdates()
        
        watchingThePedometer = false
    }
    
}

private extension LocomotionManager {
   
    private func startTheWiggles() {
        if watchingTheWiggles {
            return
        }

        guard recordAccelerometerEvents else {
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
    
    private func stopTheWiggles() {
        if !watchingTheWiggles {
            return
        }
        
        wiggles.stopDeviceMotionUpdates()
        
        watchingTheWiggles = false
    }
    
}

private extension LocomotionManager {
    
    private func restartTheUpdateTimer() {
        fallbackUpdateTimer?.invalidate()
        fallbackUpdateTimer = Timer.scheduledTimer(timeInterval: LocomotionManager.fallbackUpdateCycle, target: self,
                                                   selector: #selector(LocomotionManager.updateAndNotify),
                                                   userInfo: nil, repeats: false)
    }
    
    private func stopTheUpdateTimer() {
        fallbackUpdateTimer?.invalidate()
        fallbackUpdateTimer = nil
    }
    
}

private extension LocomotionManager {

    @objc private func updateAndNotify() {

        // update the brain states
        update()

        // fiddle the GPS/wifi/cell triangulation accuracy
        updateDesiredAccuracy()

        // make sure we're in the correct state
        touchTheRecordingState()

        // tell people
        notify()
    }

    private func update() {
        if recordingState != .recording && recordingState != .wakeup {
            return
        }

        let previousState = movingState

        // make the state fresh
        ActivityBrain.highlander.update()

        // reset the fallback timer
        restartTheUpdateTimer()

        // notify on moving state changes
        if movingState != previousState {
            NotificationCenter.default.post(Notification(name: .movingStateChanged, object: self, userInfo: nil))
        }
    }

    private func notify() {
        if recordingState != .recording {
            return
        }

        // notify everyone about the updated sample
        NotificationCenter.default.post(Notification(name: .locomotionSampleUpdated, object: self, userInfo: nil))
    }
    
    private func updateDesiredAccuracy() {
        if recordingState != .recording && recordingState != .wakeup {
            return
        }

        guard dynamicallyAdjustDesiredAccuracy else {
            return
        }

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

        // broadcast a notification
        let note = Notification(name: .didChangeAuthorizationStatus, object: self, userInfo: ["status": status])
        NotificationCenter.default.post(note)

        // forward the delegate event
        locationManagerDelegate?.locationManager?(manager, didChangeAuthorization: status)
    }

    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {

        // broadcast a notification
        let note = Notification(name: .didVisit, object: self, userInfo: ["visit": visit])
        NotificationCenter.default.post(note)

        // forward the delegate event
        locationManagerDelegate?.locationManager?(manager, didVisit: visit)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

        // ignore incoming locations that arrive when we're not supposed to be listen
        if recordingState != .recording && recordingState != .wakeup {
            return
        }

        // feed the brain
        for location in locations {
            ActivityBrain.highlander.add(rawLocation: location)
        }

        // the payoff
        updateAndNotify()

        // forward the delegate event
        locationManagerDelegate?.locationManager?(manager, didUpdateLocations: locations)
    }

}
