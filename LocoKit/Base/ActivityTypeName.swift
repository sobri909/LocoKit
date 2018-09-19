//
//  ActivityTypeName.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 12/10/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

/**
 The possible Activity Types for a Locomotion Sample. Use an `ActivityTypeClassifier` to determine the type of a
 `LocomotionSample`.
 */
public enum ActivityTypeName: String, Codable {

    /**
     The device's locomotion properties best match a stationary state.

     This may indicate that the device is lying on a stationary surface such as a table, or that the device is in the
     user's hand or pocket, but the user is otherwise stationary.
     */
    case stationary

    /**
     The device's locomotion properties best match vehicle travel.

     - Note: A vehicle temporarily stationary at traffic lights or a train station may instead be classified as
     `stationary`.
     */
    @available(*, deprecated: 7.0.0)
    case transport

    /// The device's locomotion properties best match walking.
    case walking

    /// The device's locomotion properties best match running.
    case running

    /// The device's locomotion properties best match cycling.
    case cycling

    /// The device's locomotion properties best match travelling by a car.
    case car

    /// The device's locomotion properties best match travelling by a train.
    case train

    /// The device's locomotion properties best match travelling by a bus.
    case bus

    /// The device's locomotion properties best match travelling by motorcyle.
    case motorcycle

    /// The device's locomotion properties best match travelling by airplane.
    case airplane

    /// The device's locomotion properties best match travelling by a boat.
    case boat

    /// The device's locomotion properties best match travelling by tram.
    case tram

    // MARK: Convenience Arrays
    
    /// A convenience array containing the base activity types.
    public static let baseTypes = [stationary, walking, running, cycling]

    /// A convenience array containing the extended transport types.
    public static let transportTypes = [car, train, bus, motorcycle, airplane, boat, tram]

    /// Activity types that require a location coordinate match.
    public static let coordinateBoundTypes = [car, train, bus, motorcycle, airplane, boat, tram]

    /// A convenience array containing all activity types.
    public static let allTypes = baseTypes + transportTypes

}
