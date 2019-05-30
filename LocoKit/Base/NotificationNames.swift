//
//  NotificationNames.swift
//  LocoKit
//
//  Created by Matt Greenfield on 5/11/18.
//

/**
 Custom notification events that the `LocomotionManager`` may send.
 */
public extension NSNotification.Name {

    /**
     `locomotionSampleUpdated` is sent whenever an updated LocomotionSample is available.

     Typically this indicates that a new CLLocation has arrived, however this notification will also be periodically
     sent even when no new location data is arriving, to indicate other changes to the current state. The location in
     these samples may differ from previous even though new location data is not available, due to older raw locations
     being discarded from the sample.
     */
    static let locomotionSampleUpdated = Notification.Name("locomotionSampleUpdated")

    /**
     `willStartRecording` is sent when recording is about to begin or resume.
     */
    static let willStartRecording = Notification.Name("willStartRecording")

    /**
     `recordingStateChanged` is sent after each `recordingState` change.
     */
    static let recordingStateChanged = Notification.Name("recordingStateChanged")

    /**
     `movingStateChanged` is sent after each `movingState` change.
     */
    static let movingStateChanged = Notification.Name("movingStateChanged")

    /**
     `willStartSleepMode` is sent when sleep mode is about to begin or resume.

     - Note: This includes both transitions from `recording` state and `wakeup` state.
     */
    static let willStartSleepMode = Notification.Name("willStartSleepMode")

    /**
     `didStartSleepMode` is sent after sleep mode has begun or resumed.

     - Note: This includes both transitions from `recording` state and `wakeup` state.
     */
    static let didStartSleepMode = Notification.Name("didStartSleepMode")

    /**
     `willStartDeepSleepMode` is sent when deep sleep mode is about to begin or resume.

     - Note: This includes both transitions from `recording` state and `wakeup` state.
     */
    static let willStartDeepSleepMode = Notification.Name("willStartDeepSleepMode")

    /**
     `wentFromRecordingToSleepMode` is sent after transitioning from `recording` state to `sleeping` state.
     */
    static let wentFromRecordingToSleepMode = Notification.Name("wentFromRecordingToSleepMode")

    /**
     `wentFromSleepModeToRecording` is sent after transitioning from `sleeping` state to `recording` state.
     */
    static let wentFromSleepModeToRecording = Notification.Name("wentFromSleepModeToRecording")

    static let backgroundTaskExpired = Notification.Name("backgroundTaskExpired")

    // broadcasted CLLocationManagerDelegate events
    static let didChangeAuthorizationStatus = Notification.Name("didChangeAuthorizationStatus")
    static let didUpdateLocations = Notification.Name("didUpdateLocations")
    static let didRangeBeacons = Notification.Name("didRangeBeacons")
    static let didEnterRegion = Notification.Name("didEnterRegion")
    static let didExitRegion = Notification.Name("didExitRegion")
    static let didVisit = Notification.Name("didVisit")

    @available(*, unavailable, renamed: "wentFromRecordingToSleepMode")
    static let startedSleepMode = Notification.Name("startedSleepMode")

    @available(*, unavailable, renamed: "wentFromSleepModeToRecording")
    static let stoppedSleepMode = Notification.Name("stoppedSleepMode")
}
