//
// Created by Matt Greenfield on 13/11/15.
// Copyright (c) 2015 Big Paua. All rights reserved.
//

import CoreMotion

internal struct CMActivityTypeEvent: Equatable {

    static let decayRate: TimeInterval = 30 // the time it takes for 1.0 confidence to reach 0.0

    var name: CoreMotionActivityTypeName
    var date = Date()
    var initialConfidence: CMMotionActivityConfidence

    init(name: CoreMotionActivityTypeName, confidence: CMMotionActivityConfidence, date: Date) {
        self.name = name
        self.date = date
        self.initialConfidence = confidence
    }

    var age: TimeInterval {
        return -date.timeIntervalSinceNow
    }

    var currentConfidence: Double {
        let decay = age / CMActivityTypeEvent.decayRate
        let currentConfidence = initialConfidenceDoubleValue - decay
        
        if currentConfidence > 0 {
            return currentConfidence
            
        } else {
            return 0
        }
    }
    
    var initialConfidenceDoubleValue: Double {
        var result: Double
        
        switch initialConfidence {
        case .low:
            result = 0.33
        case .medium:
            result = 0.66
        case .high:
            result = 1.00
        }
        
        if name == .stationary {
            result -= 0.01
        }
        
        return result
    }

}

func ==(lhs: CMActivityTypeEvent, rhs: CMActivityTypeEvent) -> Bool {
    return lhs.name == rhs.name && lhs.date == rhs.date
}
