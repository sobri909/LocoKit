//
// Created by Matt Greenfield on 28/10/15.
// Copyright (c) 2015 Big Paua. All rights reserved.
//

import os.log
import CoreMotion
import CoreLocation
import LocoKitCore

/**
 The central class for interacting with LocoKit location and motion recording. All actions should be performed on
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
 
 LocoKit provides three levels of location data: Raw CLLocations, filtered CLLocations, and high level
 location and activity state LocomotionSamples. See the documentation for `rawLocation`, `filteredLocation`,
 and `LocomotionSample` for details on each.

 #### Moving State
 
 When each raw location arrives LocomotionManager updates its determination of whether the user is moving or stationary, 
 based on changes between current and previous locations over time. The most up to date determination is available
 either from the `movingState` property on the LocomotionManager, or on the latest `locomotionSample`. See the
 `movingState` documentation for further details.
 */
@objc public class LocomotionManager: NSObject, CLLocationManagerDelegate {
   
    // internal settings
    internal static let fallbackUpdateCycle: TimeInterval = 30
    internal static let maximumDesiredAccuracyIncreaseFrequency: TimeInterval = 60
    internal static let maximumDesiredAccuracyDecreaseFrequency: TimeInterval = 60 * 2
    internal static let maximumDesiredLocationAccuracyInVisit = kCLLocationAccuracyHundredMeters
    internal static let wiggleHz: Double = 4

    public static let miminumDeepSleepDuration: TimeInterval = 60 * 15

    public let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()

    private lazy var wiggles: CMMotionManager = {
        let wiggles = CMMotionManager()
        wiggles.deviceMotionUpdateInterval = 1.0 / LocomotionManager.wiggleHz
        return wiggles
    }()

    /**
     The LocomotionManager's current `RecordingState`.
     */
    public private(set) var recordingState: RecordingState = .off {
        didSet(oldValue) {
            if recordingState != oldValue {
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
    internal var lastLocation: CLLocation?
    
    internal var fallbackUpdateTimer: Timer?
    internal var wakeupTimer: Timer?
    internal var lastLocationManagerCreated: Date?

    internal var backgroundTaskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid

    internal lazy var wigglesQueue: OperationQueue = {
        return OperationQueue()
    }()
    
    internal lazy var coreMotionQueue: OperationQueue = {
        return OperationQueue()
    }()

    public var coordinateAssessor: TrustAssessor?
    
    // MARK: The Singleton
    
    /// The LocomotionManager singleton instance, through which all actions should be performed.
    @objc public static let highlander = LocomotionManager()
    
    // MARK: - Settings

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
     The most recently received unmodified CLLocation.
     */
    public var rawLocation: CLLocation? {
        return locationManager.location
    }
    
    /**
     The most recent [Kalman filtered](https://en.wikipedia.org/wiki/Kalman_filter) CLLocation, based on the most 
     recently received `rawLocation`.
     
     If you require strictly real time locations, these filtered locations offer a reasonable intermediate
     state between the raw data and the fully smoothed LocomotionSamples, with coordinates as near as possible to now.
     
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

     - Note: This method will create a new sample instance on each call. As such, you should retain and reuse the
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

    // MARK: - Starting and Stopping Recording
    
    /**
     Start monitoring device location and motion.
     
     `NSNotification.Name.didUpdateLocations` notifications will be sent through the system `NotificationCenter` as 
     each location arrives.
     
     Amongst other internal tasks, this will call `startUpdatingLocation()` on the internal location manager.
     */
    public func startRecording() {
        if recordingState == .recording { return }

        guard haveLocationPermission else {
            os_log("Can't start recording without location permission.")
            return
        }

        // notify that we're about to start
        NotificationCenter.default.post(Notification(name: .willStartRecording, object: self))

        // start updating locations
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.desiredAccuracy = maximumDesiredLocationAccuracy
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()

        // start a background task, to keep iOS happy
        startBackgroundTask()

        // start the motion gimps
        startCoreMotion()
        
        // to avoid a desiredAccuracy update on first location arrival (which will have unacceptably bad accuracy)
        lastAccuracyUpdate = Date()
       
        // make sure we update even if not getting locations
        restartTheUpdateTimer()

        let previousState = recordingState
        recordingState = .recording

        // tell everyone that sleep mode has ended (ie we went from sleep/wakeup to recording)
        if RecordingState.sleepStates.contains(previousState) {
            let note = Notification(name: .wentFromSleepModeToRecording, object: self, userInfo: nil)
            NotificationCenter.default.post(note)
        }
    }
    
    /**
     Stop monitoring device location.
     
     Amongst other internal tasks, this will call `stopUpdatingLocation()` on the internal location manager.
     */
    public func stopRecording() {
        if recordingState == .off { return }

        // prep the brain for next startup
        ActivityBrain.highlander.freezeTheBrain()

        // stop the timers
        stopTheUpdateTimer()
        stopTheWakeupTimer()

        // stop the location manager
        locationManager.stopUpdatingLocation()

        // stop the motion gimps
        stopCoreMotion()

        // stop the safety nets
        locationManager.stopMonitoringVisits()
        locationManager.stopMonitoringSignificantLocationChanges()

        // allow the app to suspend and terminate cleanly
        endBackgroundTask()
        
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
        lastLocationManagerCreated = Date()

        let manager = CLLocationManager()
        manager.distanceFilter = kCLDistanceFilterNone
        manager.desiredAccuracy = self.maximumDesiredLocationAccuracy
        manager.pausesLocationUpdatesAutomatically = false
        
        manager.delegate = self

        return manager
    }()
    
    // because there can be only one highlander
    private override init() {}

    // MARK: - Sleep mode management

    private func startSleeping() {
        if recordingState == .sleeping { return }

        // make sure we're allowed to use sleep mode
        guard useLowPowerSleepModeWhileStationary else { return }

        // notify that we're going to sleep
        NotificationCenter.default.post(Notification(name: .willStartSleepMode, object: self, userInfo: nil))

        // kill the gimps
        stopCoreMotion()

        // set the location manager to ask for nothing and ignore everything
        locationManager.desiredAccuracy = Double.greatestFiniteMagnitude
        locationManager.distanceFilter = CLLocationDistanceMax

        // no fallback updates while sleeping
        stopTheUpdateTimer()

        // reset the wakeup timer
        restartTheWakeupTimer()

        let previousState = recordingState
        recordingState = .sleeping

        // notify that we've started sleep mode
        NotificationCenter.default.post(Notification(name: .didStartSleepMode, object: self, userInfo: nil))

        // tell everyone that sleep mode has started (ie we went from recording to sleep)
        if previousState == .recording {
            let note = Notification(name: .wentFromRecordingToSleepMode, object: self, userInfo: nil)
            NotificationCenter.default.post(note)
        }
    }

    public func startDeepSleeping(until wakeupTime: Date) {

        // make sure the device settings allow deep sleep
        guard canDeepSleep else {
            os_log("Deep sleep mode is unavailable due to device settings.", type: .debug)
            return
        }

        let deepSleepDuration = wakeupTime.timeIntervalSinceNow

        guard deepSleepDuration >= LocomotionManager.miminumDeepSleepDuration else {
            os_log("Requested deep sleep duration is too short.", type: .debug)
            return
        }

        // notify that we're going to deep sleep
        let note = Notification(name: .willStartDeepSleepMode, object: self, userInfo: nil)
        NotificationCenter.default.post(note)

        // request a wakeup call silent push
        LocoKitService.requestWakeup(at: wakeupTime)

        // start the safety nets
        locationManager.startMonitoringVisits()
        locationManager.startMonitoringSignificantLocationChanges()

        // stop the location manager
        locationManager.stopUpdatingLocation()

        // stop the motion gimps
        stopCoreMotion()

        // stop the timers
        stopTheWakeupTimer()
        stopTheUpdateTimer()

        // allow the app to suspend and terminate cleanly
        endBackgroundTask()

        recordingState = .deepSleeping
    }

    public var canDeepSleep: Bool {
        guard haveBackgroundLocationPermission else { return false }
        guard UIApplication.shared.backgroundRefreshStatus == .available else { return false }
        return true
    }

    @objc public func startWakeup() {
        if recordingState == .wakeup { return }
        if recordingState == .recording { return }

        // make the location manager receptive again
        locationManager.desiredAccuracy = maximumDesiredLocationAccuracy
        locationManager.distanceFilter = kCLDistanceFilterNone

        // location recording needs to be turned on?
        if recordingState == .off || recordingState == .deepSleeping {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()

            // start a background task, to keep iOS happy
            startBackgroundTask()
        }

        // need to be able to detect nolos
        restartTheUpdateTimer()

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

        case .recording, .sleeping, .deepSleeping:
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

    // MARK: - Background management

    private func startBackgroundTask() {
        guard backgroundTaskId == UIBackgroundTaskIdentifier.invalid else { return }
        os_log("Starting LocoKit background task.", type: .debug)
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "LocoKitBackground") {
            os_log("LocoKit background task expired.", type: .error)

            // tell people that the task expired, thus the app will be suspended soon
            let note = Notification(name: .backgroundTaskExpired, object: self, userInfo: nil)
            NotificationCenter.default.post(note)
            
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskId != UIBackgroundTaskIdentifier.invalid else { return }
        os_log("Ending LocoKit background task.", type: .debug)
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = UIBackgroundTaskIdentifier.invalid
    }

    // MARK: - iOS bug workaround

    // to work around an iOS 13.3 bug that results in the location manager "dying", no longer receiving location updates
    public func recreateTheLocationManager() {

        // don't recreate location managers too often
        if let last = lastLocationManagerCreated, last.age < .oneMinute { return }

        lastLocationManagerCreated = Date()

        let freshManager = CLLocationManager()
        freshManager.distanceFilter = locationManager.distanceFilter
        freshManager.desiredAccuracy = locationManager.desiredAccuracy
        freshManager.pausesLocationUpdatesAutomatically = false
        freshManager.allowsBackgroundLocationUpdates = true
        freshManager.delegate = self

        // hand over to new manager
        freshManager.startUpdatingLocation()
        locationManager.stopUpdatingLocation()
        locationManager = freshManager

        os_log("Recreated the LocationManager", type: .fault)
    }

    // MARK: - Core Motion management

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

    // MARK: - Pedometer

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

    // MARK: - Accelerometer

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

    // MARK: - Timers
    
    private func restartTheUpdateTimer() {
        onMain {
            self.fallbackUpdateTimer?.invalidate()
            self.fallbackUpdateTimer = Timer.scheduledTimer(timeInterval: LocomotionManager.fallbackUpdateCycle,
                                                            target: self, selector: #selector(self.updateAndNotify),
                                                            userInfo: nil, repeats: false)
        }
    }
    
    private func stopTheUpdateTimer() {
        onMain {
            self.fallbackUpdateTimer?.invalidate()
            self.fallbackUpdateTimer = nil
        }
    }

    private func restartTheWakeupTimer() {
        onMain {
            self.wakeupTimer?.invalidate()
            self.wakeupTimer = Timer.scheduledTimer(timeInterval: self.sleepCycleDuration, target: self,
                                                    selector: #selector(self.startWakeup), userInfo: nil,
                                                    repeats: false)
        }
    }

    private func stopTheWakeupTimer() {
        onMain {
            self.wakeupTimer?.invalidate()
            self.wakeupTimer = nil
        }
    }

    // MARK: - Updating state and notifying listeners

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

        // too soon for an update?
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
    
    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {

        // broadcast a notification
        let note = Notification(name: .didRangeBeacons, object: self, userInfo: ["beacons": beacons])
        NotificationCenter.default.post(note)

        // forward the delegate event
        locationManagerDelegate?.locationManager?(manager, didRangeBeacons: beacons, in: region)
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {

        // broadcast a notification
        let note = Notification(name: .didEnterRegion, object: self, userInfo: ["region": region])
        NotificationCenter.default.post(note)

        // forward the delegate event
        locationManagerDelegate?.locationManager?(manager, didEnterRegion: region)
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {

        // broadcast a notification
        let note = Notification(name: .didExitRegion, object: self, userInfo: ["region": region])
        NotificationCenter.default.post(note)

        // forward the delegate event
        locationManagerDelegate?.locationManager?(manager, didExitRegion: region)
    }
    
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

        // see if the visit should trigger a recording start
        startWakeup()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

        // broadcast a notification
        let note = Notification(name: .didUpdateLocations, object: self, userInfo: ["locations": locations])
        NotificationCenter.default.post(note)

        // forward the delegate event
        locationManagerDelegate?.locationManager?(manager, didUpdateLocations: locations)

        // ignore incoming locations that arrive when we're not supposed to be listening
        if recordingState != .recording && recordingState != .wakeup {
            return
        }

        // feed the brain
        var addedLocations = false
        for location in locations {

            // new location is too soon, and not better than previous? skip it
            if let last = lastLocation, last.horizontalAccuracy <= location.horizontalAccuracy, last.timestamp.age < 1.1 {
                continue
            }

            lastLocation = location

            if let trustFactor = coordinateAssessor?.trustFactorFor(location.coordinate) {
                ActivityBrain.highlander.add(rawLocation: location, trustFactor: trustFactor)
            } else {
                ActivityBrain.highlander.add(rawLocation: location)
            }

            addedLocations = true
        }

        // the payoff
        if addedLocations { updateAndNotify() }
    }

}
