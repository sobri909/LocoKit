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
     `didStartSleepMode` is sent after sleep mode has begun or resumed.

     - Note: This includes both transitions from `recording` state and `wakeup` state.
     */
    public static let didStartSleepMode = Notification.Name("didStartSleepMode")

    /**
     `willStartDeepSleepMode` is sent when deep sleep mode is about to begin or resume.

     - Note: This includes both transitions from `recording` state and `wakeup` state.
     */
    public static let willStartDeepSleepMode = Notification.Name("willStartDeepSleepMode")

    /**
     `wentFromRecordingToSleepMode` is sent after transitioning from `recording` state to `sleeping` state.
     */
    public static let wentFromRecordingToSleepMode = Notification.Name("wentFromRecordingToSleepMode")

    /**
     `wentFromSleepModeToRecording` is sent after transitioning from `sleeping` state to `recording` state.
     */
    public static let wentFromSleepModeToRecording = Notification.Name("wentFromSleepModeToRecording")

    public static let backgroundTaskExpired = Notification.Name("backgroundTaskExpired")

    // broadcasted CLLocationManagerDelegate events
    public static let didChangeAuthorizationStatus = Notification.Name("didChangeAuthorizationStatus")
    public static let didUpdateLocations = Notification.Name("didUpdateLocations")
    public static let didRangeBeacons = Notification.Name("didRangeBeacons")
    public static let didVisit = Notification.Name("didVisit")

    @available(*, unavailable, renamed: "wentFromRecordingToSleepMode")
    public static let startedSleepMode = Notification.Name("startedSleepMode")

    @available(*, unavailable, renamed: "wentFromSleepModeToRecording")
    public static let stoppedSleepMode = Notification.Name("stoppedSleepMode")
}
