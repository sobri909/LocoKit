//
//  MovingState.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 21/11/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

/**
 The device's location moving / stationary state at a point in time.

 ### Outdoor Accuracy

 The slowest detectable moving speed varies depending on the accuracy of available location data, however under typical
 conditions the slowest detected moving speed is a slow walk (~3 km/h) while outdoors.

 ### Indoor Accuracy

 Most normal indoor movement will be classified as stationary, due to lack of GPS line of sight resulting in available
 location accuracy of 65 metres or worse. This has the side benefit of allowing indoor events to be clustered into
 distinct "visits".

 ### iBeacons

 A building fitted with multiple iBeacons may increase the available indoor location accuracy to as high as 5
 metres. In such an environment, indoor movement may be detectable with similar accuracy to outdoor movement.
 */
public enum MovingState: String, Codable {

    /**
     The device has been determined to be moving between places, based on available location data.
     */
    case moving

    /**
     The device has been determined to be either stationary, or moving slower than the slowest currently detectable
     moving speed.
     */
    case stationary

    /**
     The device's moving / stationary state could not be confidently determined.

     This state can occur either due to no available location data, or the available location data falling below
     necessary quality or quantity thresholds.
     */
    case uncertain
}
