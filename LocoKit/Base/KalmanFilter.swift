//
//  KalmanFilter.swift
//  
//
//  Created by Matt Greenfield on 29/05/17.
//

import os.log
import CoreLocation

// source: https://stackoverflow.com/a/15657798/790036

internal class KalmanFilter {
    
    var q: Double // expected change per sample
    var k: Double = 1 // trust percentage to apply to new values
    var variance: Double = -1 // p matrix
    var timestamp: TimeInterval = 0
    
    init(q: Double) {
        self.q = q
    }
   
    // next input will be treated as first
    func reset() {
        k = 1
        variance = -1
    }
    
    func resetVarianceTo(accuracy: Double) {
        variance = accuracy * accuracy 
    }
    
    func update(date: Date, accuracy: Double) {
        
        // first input after init or reset
        if variance < 0 {
            variance = accuracy * accuracy
            timestamp = date.timeIntervalSince1970
            return
        }
        
        // uncertainty in the current value increases as time passes
        let timeDiff = date.timeIntervalSince1970 - timestamp
        if timeDiff > 0 {
            variance += timeDiff * q * q
            timestamp = date.timeIntervalSince1970
        }
        
        // gain matrix k = covariance * inverse(covariance + measurementVariance)
        k = variance / (variance + accuracy * accuracy)
        
        // new covariance matrix is (identityMatrix - k) * covariance
        variance = (1.0 - k) * variance
    }
    
}

extension KalmanFilter {
    
    var accuracy: Double {
        return variance.squareRoot()
    }
    
    var date: Date {
        return Date(timeIntervalSince1970: timestamp)
    }
    
    func predictedValueFor(oldValue: Double, newValue: Double) -> Double {
        return oldValue + (k * (newValue - oldValue))
    }
    
}
