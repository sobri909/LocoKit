//
//  ActivityTypeScorable.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 8/01/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public protocol ActivityTypeClassifiable: class {
    
    var location: CLLocation? { get }
    var movingState: MovingState { get }
    var coreMotionActivityType: CoreMotionActivityTypeName? { get }
    var stepHz: Double? { get }
    var courseVariance: Double? { get }
    var xyAcceleration: Double? { get }
    var zAcceleration: Double? { get }
    var timeOfDay: TimeInterval { get }
    var previousSampleConfirmedType: ActivityTypeName? { get }

    var classifierResults: ClassifierResults? { get set }
    
}
