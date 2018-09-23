//
//  MutableActivityType.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 14/12/16.
//  Copyright © 2016 Big Paua. All rights reserved.
//

import os.log
import CoreLocation
import GRDB

public struct LocomotionMagicValue {
    @available(*, deprecated: 5.1.0)
    public static let nilCourse: Double = -360
    public static let nilAltitude: CLLocationDistance = -1000
}

open class MutableActivityType: ActivityType {

    static let statsDebug = false

    public var needsUpdate = false

    public func updateFrom<S: Sequence>(samples: S) where S.Iterator.Element: ActivityTypeTrainable {
        if isShared { return }
        
        var totalSamples = 0, totalMoving = 0, accuracyScorables = 0, correctScorables = 0
        
        var allAltitudes: [Double] = [], allSpeeds: [Double] = [], allStepHz: [Double] = []
        var allCourses: [Double] = [], allCourseVariances: [Double] = [], allTimesOfDay: [Double] = []
        var allXYAccelerations: [Double] = [], allZAccelerations: [Double] = []
        var allCoordinates: [CLLocationCoordinate2D] = []
        var allCoreMotionTypes: [CoreMotionActivityTypeName] = []
        var allAccuracies: [CLLocationAccuracy] = []
        
        for sample in samples {
            
            // only accept confirmed samples that match the model
            guard let confirmedType = sample.confirmedType, confirmedType == self.name else {
                continue
            }
            
            // only accept samples that have a coordinate inside the model
            guard let location = sample.location, location.coordinate.isUsable else { continue }
            guard self.contains(coordinate: location.coordinate) else { continue }
            
            totalSamples += 1
            
            // collect accuracy counts
            if let classifiedType = sample.classifiedType {
                accuracyScorables += 1
                if classifiedType == confirmedType {
                    correctScorables += 1
                }
            }
            
            if sample.movingState == .moving {
                totalMoving += 1
            }

            // ignore zero stepHz for walking, because it's a far too common gap in the raw data
            if let stepHz = sample.stepHz, (self.name != .walking || stepHz > 0) {
                allStepHz.append(stepHz)
            }
            
            if let courseVariance = sample.courseVariance {
                allCourseVariances.append(courseVariance)
            }
            
            allTimesOfDay.append(sample.timeOfDay)
            
            if let xyAcceleration = sample.xyAcceleration {
                allXYAccelerations.append(xyAcceleration)
            }
            if let zAcceleration = sample.zAcceleration {
                allZAccelerations.append(zAcceleration)
            }
            
            if let coreMotionType = sample.coreMotionActivityType {
                allCoreMotionTypes.append(coreMotionType)
            }
            
            allCoordinates.append(location.coordinate)
            
            if !location.altitude.isNaN && location.verticalAccuracy >= 0 && location.altitude != LocomotionMagicValue.nilAltitude {
                allAltitudes.append(location.altitude)
            }

            if location.horizontalAccuracy >= 0 {
                allAccuracies.append(location.horizontalAccuracy)
            }
            
            // exclude impossible speeds
            if location.speed >= 0 && location.speed.kmh < 1000 {
                allSpeeds.append(location.speed)
            }
            
            if location.course >= 0 {
                allCourses.append(location.course)
            }
        }
        
        self.totalSamples = totalSamples

        if accuracyScorables > 0 {
            self.accuracyScore = Double(correctScorables) / Double(accuracyScorables)
        } else {
            self.accuracyScore = nil
        }

        // no events? we done here
        guard totalSamples > 0 else { return }
        
        // motion factors
        self.movingPct = Double(totalMoving) / Double(totalSamples)
        self.speedHistogram = Histogram(values: allSpeeds, minBoundary: 0, trimOutliers: true, name: "SPEED",
                                        printFormat: "%6.1f kmh", printModifier: 3.6)
        self.stepHzHistogram = Histogram(values: allStepHz, minBoundary: 0, trimOutliers: true, name: "STEPHZ",
                                         printFormat: "%7.2f Hz")
        self.xyAccelerationHistogram = Histogram(values: allXYAccelerations, minBoundary: 0, trimOutliers: true,
                                                 name: "WIGGLES XY")
        self.zAccelerationHistogram = Histogram(values: allZAccelerations, minBoundary: 0, trimOutliers: true,
                                                name: "WIGGLES Z")
        self.courseVarianceHistogram = Histogram(values: allCourseVariances, minBoundary: 0, maxBoundary: 1,
                                                 name: "COURSE VARIANCE", printFormat: "%10.2f")
        self.coreMotionTypeScores = self.coreMotionTypeScoresDict(for: allCoreMotionTypes)
        
        // context factors
        self.altitudeHistogram = Histogram(values: allAltitudes, trimOutliers: true, name: "ALTITUDE",
                                           printFormat: "%8.0f m")
        self.courseHistogram = Histogram(values: allCourses, minBoundary: 0, maxBoundary: 360, name: "COURSE",
                                         printFormat: "%8.0f °")
        self.timeOfDayHistogram = Histogram(values: allTimesOfDay, minBoundary: 0, maxBoundary: 60 * 60 * 24,
                                            pseudoCount: 100, name: "TIME OF DAY", printFormat: "%8.2f h",
                                            printModifier: 60 / 60 / 60 / 60)
        self.horizontalAccuracyHistogram = Histogram(values: allAccuracies, minBoundary: 0, trimOutliers: true,
                                                     name: "HORIZ ACCURACY")

        // type requires a coordinate match to be non zero? 
        let pseudoCount = ActivityTypeName.extendedTypes.contains(name) ? 0 : 1
        
        self.coordinatesMatrix = CoordinatesMatrix(coordinates: allCoordinates, latBinCount: self.numberOfLatBuckets,
                                                   lngBinCount: self.numberOfLongBuckets, latRange: self.latitudeRange,
                                                   lngRange: self.longitudeRange, pseudoCount: UInt16(pseudoCount))

        self.version = ActivityType.currentVersion
        self.lastUpdated = Date()
        self.needsUpdate = false
        
        if MutableActivityType.statsDebug {
            self.printStats()
        }
    }

    private func coreMotionTypeScoresDict(for values: [CoreMotionActivityTypeName]) -> [CoreMotionActivityTypeName: Double] {
        var totals: [CoreMotionActivityTypeName: Double] = [:]
        var scores: [CoreMotionActivityTypeName: Double] = [:]
        
        for coreMotionType in CoreMotionActivityTypeName.allTypes {
            totals[coreMotionType] = 0
            scores[coreMotionType] = 0
        }
        
        guard values.count > 0 else {
            return scores
        }
        
        for coreMotionType in values {
            if totals[coreMotionType] != nil {
                totals[coreMotionType]! += 1
            }
        }
        
        for coreMotionType in CoreMotionActivityTypeName.allTypes {
            if let total = totals[coreMotionType], total > 0 {
                scores[coreMotionType] = total / Double(values.count)
            }
        }
        
        return scores
    }

    public var statsDict: [String: Any] {        
        var dict: [String: Any] = [:]
        
        dict["latitudeMin"] = latitudeRange.min
        dict["latitudeMax"] = latitudeRange.max
        dict["longitudeMin"] = longitudeRange.min
        dict["longitudeMax"] = longitudeRange.max
        
        dict["movingPct"] = movingPct
        dict["coreMotionTypeScores"] = coreMotionTypeScoresArray
        dict["speedHistogram"] = speedHistogram?.serialised
        dict["stepHzHistogram"] = stepHzHistogram?.serialised
        dict["courseVarianceHistogram"] = courseVarianceHistogram?.serialised
        dict["altitudeHistogram"] = altitudeHistogram?.serialised
        dict["courseHistogram"] = courseHistogram?.serialised
        dict["timeOfDayHistogram"] = timeOfDayHistogram?.serialised
        dict["xyAccelerationHistogram"] = xyAccelerationHistogram?.serialised
        dict["zAccelerationHistogram"] = zAccelerationHistogram?.serialised
        dict["horizontalAccuracyHistogram"] = horizontalAccuracyHistogram?.serialised
        dict["coordinatesMatrix"] = coordinatesMatrix?.serialised
        
        return dict
    }

    open override func encode(to container: inout PersistenceContainer) {
        super.encode(to: &container)
        container["needsUpdate"] = needsUpdate
    }
    
}
