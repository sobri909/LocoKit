//
//  ActivityTypeScorable.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 8/01/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Foundation
import CoreLocation

public protocol ActivityTypeClassifiable: AnyObject {
    var location: CLLocation? { get }
    var movingState: MovingState { get }
    var stepHz: Double? { get }
    var courseVariance: Double? { get }
    var xyAcceleration: Double? { get }
    var zAcceleration: Double? { get }
    var timeOfDay: TimeInterval { get }
    var sinceVisitStart: TimeInterval { get }
    var classifierResults: ClassifierResults? { get set }
}

extension ActivityTypeClassifiable {
    var coreMLFeatureProvider: CoreMLFeatureProvider {
        return CoreMLFeatureProvider(
            stepHz: stepHz,
            xyAcceleration: xyAcceleration,
            zAcceleration: zAcceleration,
            movingState: movingState.rawValue,
            verticalAccuracy: location?.verticalAccuracy,
            horizontalAccuracy: location?.horizontalAccuracy,
            courseVariance: courseVariance,
            speed: location?.speed,
            course: location?.course,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            altitude: location?.altitude,
            timeOfDay: timeOfDay,
            sinceVisitStart: sinceVisitStart
        )
    }
}
