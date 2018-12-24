//
//  ActivityType.scores.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 14/12/16.
//  Copyright © 2016 Big Paua. All rights reserved.
//

import CoreLocation

extension ActivityType {

    var bucketMax: Int {
        switch depth {
        case 2: return ActivityType.latLongBucketMaxDepth2
        case 1: return ActivityType.latLongBucketMaxDepth1
        default: return ActivityType.latLongBucketMaxDepth0
        }
    }
    
    public func scoreFor(classifiable scorable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> Double {
        let depth = self.depth
        
        // motion weights
        let movingWeight = 1.0
        var speedWeight = 1.0
        var stepHzWeight = 1.0
        var varianceWeight = 1.0
        var xyWeight = 1.0
        var zWeight = 1.0
        
        // context weights
        let timeOfDayWeight = 1.0
        let courseWeight = 1.0
        let altitudeWeight = 1.0
        var latLongWeight = 1.0
        let horizAccuracyWeight = 1.0
        let markovWeight = 1.0
        
        if depth == 2 {
            speedWeight = 2.0 // cars, trains, etc go different speeds in different locales
            stepHzWeight = 1.2 // local roads equal different fake step jiggles
            varianceWeight = 1.2 // local location accuracy plays a big part in variance
            xyWeight = 1.2 // local roads equal different jiggles
            zWeight = 1.2 // local roads equal different jiggles
            latLongWeight = 10.0 // local usage locations per type are massive important
        }
        
        var scores: [Double] = []
        
        /** motion scores **/
        
        if let movingScore = self.movingScore(for: scorable.movingState) {
            scores.append(movingScore * movingWeight)
        }
        
        if let speed = scorable.location?.speed, speed >= 0 {
            scores.append(speedScore(for: speed) * speedWeight)
        }
        
        if let stepHz = scorable.stepHz {
            scores.append(stepHzScore(for: stepHz) * stepHzWeight)
        }
       
        if let courseVariance = scorable.courseVariance {
            scores.append(courseVarianceScore(for: courseVariance) * varianceWeight)
        }
        
        if name != .stationary && name != .bogus { // stationary and bogus are allowed any kinds of wiggles
            if let xyAcceleration = scorable.xyAcceleration {
                scores.append(xyScore(for: xyAcceleration) * xyWeight)
            }
            
            if let zAcceleration = scorable.zAcceleration {
                scores.append(zScore(for: zAcceleration) * zWeight)
            }
        }
        
        /** context scores **/

        if name != .bogus, let previous = previousResults?.first?.name, !previousSampleActivityTypeScores.isEmpty {
            scores.append(previousTypeScore(for: previous) * markovWeight)
        }

        if let altitude = scorable.location?.altitude, altitude != LocomotionMagicValue.nilAltitude {
            scores.append(altitudeScore(for: altitude) * altitudeWeight)
        }
        
        if depth > 0 && name != .stationary { // D0 and stationary should ignore these context factors
            if let course = scorable.location?.course, course >= 0 {
                scores.append(courseScore(for: course) * courseWeight)
            }

            // walking and running are golden childs. don't bother with time of day checks
            if name != .walking && name != .running {
                scores.append(timeOfDayScore(for: scorable.timeOfDay) * timeOfDayWeight)
            }
        }
        
        if depth > 0 { // coords are irrelevant at D0
            if let coordinate = scorable.location?.coordinate {
                scores.append(latLongScore(for: coordinate) * latLongWeight)
            }
        }

        if depth == 2 { // horizontalAccuracy is very neighbourhood specific
            if let accuracy = scorable.location?.horizontalAccuracy, accuracy >= 0 {
                scores.append(horizAccuracyScore(for: accuracy) * horizAccuracyWeight)
            }
        }
        
        let score = scores.reduce(1.0, *)
        
        return score.clamped(min: 0, max: 1)
    }

    // MARK: -

    func scoreFor(_ value: Double, in histogram: Histogram) -> Double {
        return histogram.probabilityFor(value)
    }

    // MARK: -

    func movingScore(for movingState: MovingState) -> Double? {
        if movingState == .uncertain {
            return nil
        }
        
        guard movingPct >= 0 else {
            return nil
        }
        
        let movingValue = movingPct
        let notMovingValue = 1.0 - movingPct
        let maxValue = max(movingValue, notMovingValue)
        
        return movingState == .moving
            ? movingValue / maxValue
            : notMovingValue / maxValue
    }

    func coreMotionScore(for coreMotionType: CoreMotionActivityTypeName) -> Double {
        guard let value = coreMotionTypeScores[coreMotionType] else { return 0 }
        guard let maxPercent = coreMotionTypeScores.values.max(), maxPercent > 0 else { return 0 }
        return value / maxPercent
    }

    func previousTypeScore(for previousType: ActivityTypeName) -> Double {
        guard let value = previousSampleActivityTypeScores[previousType] else { return 0 }
        guard let maxPercent = previousSampleActivityTypeScores.values.max(), maxPercent > 0 else { return 0 }
        return value / maxPercent
    }
    
    func speedScore(for speed: Double) -> Double {
        return speedHistogram?.probabilityFor(speed) ?? 0
    }
    
    func stepHzScore(for stepHz: Double) -> Double {
        return stepHzHistogram?.probabilityFor(stepHz) ?? 0
    }
    
    func xyScore(for value: Double) -> Double {
        return xyAccelerationHistogram?.probabilityFor(value) ?? 0
    }
    
    func zScore(for value: Double) -> Double {
        return zAccelerationHistogram?.probabilityFor(value) ?? 0
    }
    
    func courseScore(for value: Double) -> Double {
        return courseHistogram?.probabilityFor(value) ?? 0
    }
    
    func courseVarianceScore(for value: Double) -> Double {
        return courseVarianceHistogram?.probabilityFor(value) ?? 0
    }
    
    func altitudeScore(for value: Double) -> Double {
        return altitudeHistogram?.probabilityFor(value) ?? 0
    }
    
    func timeOfDayScore(for value: Double) -> Double {
        return timeOfDayHistogram?.probabilityFor(value) ?? 0
    }

    func horizAccuracyScore(for value: Double) -> Double {
        return horizontalAccuracyHistogram?.probabilityFor(value) ?? 0
    }
    
    func latLongScore(for coordinate: CLLocationCoordinate2D) -> Double {
        return coordinatesMatrix?.probabilityFor(coordinate, maxThreshold: bucketMax) ?? 0
    }

    // MARK: -

    var coreMotionTypeScoresString: String {
        var scores = coreMotionTypeScores.map { name, score in (name: name, score: score) }
        
        scores.sort { $0.score > $1.score }
        
        var result = ""
        for type in scores {
            if type.score > 0 {
                result += "\(type.name): " + String(format: "%.2f", type.score) + ", "
            }
        }
        
        return result.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
    }
    
}
