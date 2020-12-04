//
//  KalmanAltitude.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 14/06/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

internal class KalmanAltitude: KalmanFilter {
    
    var altitude: Double?
    var unfilteredLocation: CLLocation?
    
    init(qMetresPerSecond: Double) {
        super.init(q: qMetresPerSecond)
    }
    
    override func reset() {
        super.reset()
        altitude = nil
    }
    
    func add(location: CLLocation) {
        guard location.verticalAccuracy > 0 else {
            return
        }
        
        guard location.timestamp.timeIntervalSince1970 >= timestamp else {
            return
        }
        
        unfilteredLocation = location
        
        // update the kalman internals
        update(date: location.timestamp, accuracy: location.verticalAccuracy)
        
        // apply the k
        if let oldAltitude = altitude {
            self.altitude = oldAltitude + (k * (location.altitude - oldAltitude))
        } else {
            self.altitude = location.altitude
        }
    }
    
}
