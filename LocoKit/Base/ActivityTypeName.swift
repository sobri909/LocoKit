//
//  ActivityTypeName.swift
//  LocoKit
//
//  Created by Matt Greenfield on 12/10/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

/**
 The possible Activity Types for a Locomotion Sample. Use an `ActivityTypeClassifier` to determine the type of a
 `LocomotionSample`.

 - Note: The stationary type may indicate that the device is lying on a stationary surface such as a table, or that
   the device is in the user's hand or pocket but the user is otherwise stationary.
*/
public enum ActivityTypeName: String, Codable {

    // base types
    case stationary
    case walking
    case running
    case cycling

    // transport types
    case car
    case train
    case bus
    case motorcycle
    case airplane
    case boat
    case tram
    case tractor
    case tuktuk = "tuk-tuk"
    case songthaew

    // active types
    case skateboarding
    case inlineSkating = "inline skating"
    case snowboarding
    case skiing
    case scooter
    case horseback

    @available(*, deprecated: 7.0.0)
    case transport

    // MARK: - Convenience Arrays
    
    /// A convenience array containing the base activity types.
    public static let baseTypes = [stationary, walking, running, cycling]

    /// A convenience array containing the extended transport types.
    public static let extendedTypes = [
        car, train, bus, motorcycle, airplane, boat, tram, tractor, tuktuk, songthaew,
        skateboarding, inlineSkating, snowboarding, skiing, scooter, horseback
    ]

    /// A convenience array containing all activity types.
    public static let allTypes = baseTypes + extendedTypes

}
