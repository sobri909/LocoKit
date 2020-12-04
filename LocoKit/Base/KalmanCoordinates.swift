//
//  KalmanCoordinates.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 14/06/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import CoreLocation

internal class KalmanCoordinates: KalmanFilter {
    
    fileprivate var latitude: Double = 0
    fileprivate var longitude: Double = 0
    var unfilteredLocation: CLLocation?
    
    init(qMetresPerSecond: Double) {
        super.init(q: qMetresPerSecond)
    }
    
    override func reset() {
        super.reset()
        latitude = 0
        longitude = 0
    }
    
    func add(location: CLLocation) {
        guard location.hasUsableCoordinate else {
            return
        }
        
        guard location.timestamp.timeIntervalSince1970 > timestamp else {
            return
        }
       
        unfilteredLocation = location
        
        // update the kalman internals
        update(date: location.timestamp, accuracy: location.horizontalAccuracy)
        
        // apply the k
        latitude = predictedValueFor(oldValue: latitude, newValue: location.coordinate.latitude)
        longitude = predictedValueFor(oldValue: longitude, newValue: location.coordinate.longitude)
    }
    
}

extension KalmanCoordinates {
    
    var coordinate: CLLocationCoordinate2D? {
        guard variance >= 0 else {
            return nil
        }
       
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
}
