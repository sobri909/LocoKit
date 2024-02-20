//
//  ActivityBrainState.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 27/11/16.
//  Copyright © 2016 Big Paua. All rights reserved.
//

import CoreLocation
import CoreMotion

public class ActivityBrainSample {

    private var _rawLocations: [CLLocation] = []
    private var _filteredLocations: [CLLocation] = []
    private var _pedoDataSamples: [CMPedometerData] = []
    private var _deviceMotionSamples: [(date: Date, motion: DeviceMotion)] = []
    private var _centresHistory: [CLLocation] = []
    
    private var _location: CLLocation?
    private var _speed: CLLocationSpeed = 0
    private var _course: CLLocationDirection = -1
    private var _radius: CLLocationDistance = 0

    public var movingState: MovingState = .uncertain
    public var radiusBounded: CLLocationDistance = 5
    
    var mutex: UnfairLock
    var wigglesMutex: UnfairLock
    
    internal init(mutex: UnfairLock, wigglesMutex: UnfairLock) {
        self.mutex = mutex
        self.wigglesMutex = wigglesMutex
    }

    public var rawLocations: [CLLocation] { return mutex.sync { _rawLocations } }
    public var filteredLocations: [CLLocation] { return mutex.sync { _filteredLocations } }
    
    var n: Int { return mutex.sync { _filteredLocations.count } }
    var wigglesN: Int { return mutex.sync { _deviceMotionSamples.count } }
    
    private var _date: Date { return _location?.timestamp ?? Date() }
    public var date: Date { return mutex.sync { _date } }
    
    var age: TimeInterval {
        return mutex.sync {
            if let oldest = _filteredLocations.first { return -oldest.timestamp.timeIntervalSinceNow }
            return 0
        }
    }
    
    public var spread: TimeInterval { return range?.duration ?? 0 }
    
    private var _range: DateInterval? { return _filteredLocations.dateInterval }
    var range: DateInterval? { return mutex.sync { _range } }
    
    var timeOfDay: Double { return date.sinceStartOfDay() }

    var hasUsableLatLong: Bool { return location != nil }
    
    public var location: CLLocation? { return mutex.sync { _location } }

    var coordinate: CLLocationCoordinate2D? { return location?.coordinate }
    public var radius: CLLocationDistance { return mutex.sync { _radius } }
    var altitude: CLLocationDistance? { return mutex.sync { _location?.altitude } }

    public var stepHz: Double? {
        return mutex.sync {
            for sample in _pedoDataSamples.reversed() {
                if sample.startDate < self._date && sample.endDate > self._date {
                    if let cadence = sample.currentCadence { return cadence.doubleValue }

                    let steps = sample.numberOfSteps.doubleValue
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    return steps / duration
                }
            }
            return nil
        }
    }

    var kmh: Double { return speed * 3.6 }

    // TODO: plz make this optional
    public var speed: CLLocationSpeed { return mutex.sync { _speed } }
    
    public var course: CLLocationDirection { return mutex.sync { _course } }
    public var courseVariance: Double? { return mutex.sync { _filteredLocations.courseVariance } }
    
    public var xyAcceleration: Double? {
        return wigglesMutex.sync {
            if _deviceMotionSamples.isEmpty { return nil }
            let values: [Double] = _deviceMotionSamples.map {
                let acceleration = $0.motion.userAccelerationInReferenceFrame
                return abs(acceleration.x) + abs(acceleration.y)
            }
            return values.mean + (values.standardDeviation * 3.0)
        }
    }
    
    public var zAcceleration: Double? {
        return wigglesMutex.sync {
            if _deviceMotionSamples.isEmpty { return nil }
            let values: [Double] = _deviceMotionSamples.map { abs($0.motion.userAccelerationInReferenceFrame.z) }
            return values.mean + (values.standardDeviation * 3.0)
        }
    }
    
    var nonNegativeHorizontalAccuracy: Double {
        let accuracy = horizontalAccuracy
        return accuracy > 0 ? accuracy : ActivityBrain.worstAllowedLocationAccuracy
    }
    
    var horizontalAccuracy: Double { return mutex.sync { _location?.horizontalAccuracy ?? -1 } }
    var verticalAccuracy: Double { return mutex.sync { return _location?.verticalAccuracy ?? -1 } }
    var firstLocation: CLLocation? { return mutex.sync { _filteredLocations.first } }

    // MARK: -
  
    func flush() {
        mutex.sync {
            _rawLocations.removeAll()
            _filteredLocations.removeAll()
            _pedoDataSamples.removeAll()
            _speed = 0
        }
        
        wigglesMutex.sync {
            _deviceMotionSamples = []
        }
    }
    
    func update() {
        mutex.sync {
            updateRawLocations()
            updateCourse()

            // TODO: this will use an outdated speed because speed isn't updated until after. uh, oops.
            // should probably start doing speed from filteredLocations instead. that's the end goal anyway
            updateLocation()
            updateRadius()

            if let centre = _location {
                _centresHistory.append(centre)
            }
            while _centresHistory.count > ActivityBrain.speedSampleN {
                _centresHistory.remove(at: 0)
            }
            updateSpeed()
        }
    }
    
    private func updateRawLocations() {
        guard let sampleStart = _range?.start else {
            _rawLocations.removeAll()
            return
        }
        
        // need them time sorted, because raw locations don't necessarily arrive in order
        _rawLocations.sort { $0.timestamp < $1.timestamp }
        
        // ditch locations older than sample start
        while let oldest = _rawLocations.first, oldest.timestamp < sampleStart {
            _rawLocations.remove(oldest)
        }
    }

    private func updateLocation() {
        guard _filteredLocations.count > 1 else {
            if let first = _filteredLocations.first, first.hasUsableCoordinate {
                _location = _filteredLocations.first
            } else {
                _location = nil
            }
            return
        }

        guard let partial = _filteredLocations.weightedCenter else {
            _location = nil
            return
        }

        _location = CLLocation(coordinate: partial.coordinate, altitude: partial.altitude,
                               horizontalAccuracy: partial.horizontalAccuracy,
                               verticalAccuracy: partial.verticalAccuracy, course: _course, speed: _speed,
                               timestamp: partial.timestamp)
    }

    private func updateCourse() {
        var x = 0.0, y = 0.0, count = 0

        var previousLocation: CLLocation?
        for location in _filteredLocations {
            guard let previous = previousLocation else {
                previousLocation = location
                continue
            }

            guard let radians = previous.radiansCourse(to: location) else { continue }

            x += cos(radians)
            y += sin(radians)
            count += 1

            previousLocation = location
        }

        _course = count > 0 ? Radians(atan2(y, x)).degreesValue.nonNegativeValue : -1
    }

    private func updateRadius() {
        if _filteredLocations.count < 2 {
            _radius = 0
            return
        }
        
        guard let centre = _location else {
            _radius = 0
            return
        }
        
        guard let ends = _filteredLocations.horizontalAccuracyRange else {
            _radius = 0
            return
        }
        
        var distances: [Double] = [], totalDistance: Double = 0, totalWeight: Double = 0
        
        for location in _filteredLocations where location.hasUsableCoordinate {
            let distance = location.distance(from: centre)
            let weight = accuracyWeight(location.horizontalAccuracy, best: ends.best, worst: ends.worst)
            totalDistance += distance * weight
            totalWeight += weight
            distances.append(distance)
        }
        
        let mean = totalDistance / totalWeight
        let sd = distances.standardDeviation
        
        _radius = mean + sd
    }
   
    private func updateSpeed() {
        let rawSpeeds = _rawLocations.compactMap { return $0.speed >= 0 ? $0.speed : nil }

        // can use raw speeds?
        if !rawSpeeds.isEmpty { _speed = rawSpeeds.mean; return }

        // can fall back to distance / duration speed?
        let duration = _filteredLocations.duration
        let distance = _filteredLocations.distance
        if duration > 0 { _speed = distance / duration; return }

        // fails
        _speed = -1
    }
    
    private func accuracyWeight(_ accuracy: Double, best: Double, worst: Double) -> Double {
        guard best < worst else {
            return 1.0
        }
        return 1.0 - (accuracy / (worst + 5.0))
    }
}

extension ActivityBrainSample {
    
    func add(rawLocation location: CLLocation) {
        mutex.sync {
            _rawLocations.append(location)
        }
    }
   
    func add(filteredLocation location: CLLocation) {
        mutex.sync {
            
            // reject out of order locations
            if let last = _filteredLocations.last, last.timestamp > location.timestamp { return }
            
            // reject locations with invalid accuracy
            if location.horizontalAccuracy < 0 { return }
            
            _filteredLocations.append(location)
        }
    }
    
    func add(pedoData: CMPedometerData) {
        mutex.sync {
            
            // trim outdated samples
            if let range = _range {
                while let sample = _pedoDataSamples.first, sample.endDate < range.start {
                    _pedoDataSamples.remove(at: 0)
                }
            }
            
            _pedoDataSamples.append(pedoData)
        }
    }
    
    func addDeviceMotion(_ deviceMotion: CMDeviceMotion) {
        wigglesMutex.sync {
            var samples = _deviceMotionSamples
           
            let sampleAge = age
            let boundaryAge = sampleAge > 0 ? sampleAge : ActivityBrain.maximumSampleAge
            
            // trim outdated samples
            while let sample = samples.first, sample.date.age > boundaryAge {
                samples.remove(at: 0)
            }
            
            samples.append((date: Date(), motion: DeviceMotion(cmMotion: deviceMotion)))
            
            _deviceMotionSamples = samples
        }
    }
    
}

extension ActivityBrainSample {
    
    func removeLocation(_ location: CLLocation) {
        mutex.sync {
            _filteredLocations.remove(location)
            
            // can't have a speed or course variance on empty sample
            if _filteredLocations.isEmpty {
               _centresHistory.removeAll()
            }
        }
    }
    
}
