//
//  RecordingState.swift
//  LocoKit
//
//  Created by Matt Greenfield on 26/11/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

/**
 The recording state of the LocomotionManager.
 */
public enum RecordingState: String, Codable {

    /**
     This state indicates that the LocomotionManager is turned on and recording location data. It may also be recording
     motion data, depending on the LocomotionManager's settings.
     */
    case recording

    /**
     This state indicates that the LocomotionManager is in low power sleep mode.
     */
    case sleeping

    /**
     This state indicates that the LocomotionManager is not recording, but is ready to be woken up by iOS and restart
     recording at an appropriate time.
     */
    case deepSleeping

    /**
     This state indicates that the LocomotionManager is performing a periodic wakeup from sleep mode, to determine
     whether it should resume recording or should continue sleeping.
     */
    case wakeup

    /**
     Recording is off, but the app is kept alive and the manager is ready to restart recording immediately if requested.
     */
    case standby

    /**
     This state indicates that the LocomotionManager is turned off and is not recording location or motion data.
     */
    case off

    public var isSleeping: Bool { return RecordingState.sleepStates.contains(self) }
    public var isCurrentRecorder: Bool { return RecordingState.activeRecorderStates.contains(self) }

    public static let sleepStates = [wakeup, sleeping, deepSleeping]
    public static let activeRecorderStates = [recording, wakeup, sleeping, deepSleeping]

}
