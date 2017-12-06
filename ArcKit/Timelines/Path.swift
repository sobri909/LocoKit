//
//  Path.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

@objc public class Path: TimelineItem {

    // valid path settings
    @objc static var minimumValidDuration: TimeInterval = 10
    @objc static var minimumValidDistance: Double = 10
    @objc static var minimumValidSamples = 2

    // keeper path settings
    @objc static var minimumKeeperDuration: TimeInterval = 60
    @objc static var minimumKeeperDistance: Double = 20

    private var _distance: CLLocationDistance?

    public override var isValid: Bool {
        if samples.count < Path.minimumValidSamples {
            return false
        }

        if duration < Path.minimumValidDuration {
            return false
        }

        if distance < Path.minimumValidDistance {
            return false
        }

        return true
    }

    @objc public override var isWorthKeeping: Bool {
        if !isValid {
            return false
        }
        if duration < Path.minimumKeeperDuration {
            return false
        }
        if distance < Path.minimumKeeperDistance {
            return false
        }
        return true
    }

    /// The distance of the path, as the sum of the distances between each sample.
    @objc public var distance: CLLocationDistance {
        if let distance = _distance {
            return distance
        }
        let distance = samples.distance
        _distance = distance
        return distance
    }

    public var mps: Double {
        return metresPerSecond
    }

    public var metresPerSecond: Double {
        guard duration > 0 else {
            return 0
        }
        return distance / duration
    }

    public var kph: Double {
        return kilometresPerHour
    }

    public var kilometresPerHour: Double {
        guard duration > 0 else {
            return 0
        }
        let hours = duration / (60 * 60)
        return distance / 1000 / hours
    }

    public var milesPerHour: Double {
        return kilometresPerHour / 1.609344
    }

    internal func distance(from visit: Visit) -> CLLocationDistance? {
        return visit.distance(from: self)
    }
    
    internal func distance(from otherPath: Path) -> CLLocationDistance? {
        guard let myStart = start, let theirStart = otherPath.start else {
            return nil
        }
        if myStart < theirStart {
            if let myEdge = samples.last, let theirEdge = otherPath.samples.first {
                return myEdge.distance(from: theirEdge)
            }
        } else {
            if let myEdge = samples.first, let theirEdge = otherPath.samples.last {
                return myEdge.distance(from: theirEdge)
            }
        }
        return nil
    }
    
    public func samplesInside(_ visit: Visit) -> Set<LocomotionSample> {
        guard let visitCenter = visit.center else {
            return []
        }
        var insiders: Set<LocomotionSample> = []
        for sample in samples {
            guard let sampleLocation = sample.location else {
                continue
            }
            let metresFromCentre = visitCenter.distance(from: sampleLocation)
            if metresFromCentre <= visit.radius1sd {
                insiders.insert(sample)
            }
        }
        return insiders
    }

    public func samplesOutside(_ visit: Visit) -> Set<LocomotionSample> {
        return Set(samples).subtracting(samplesInside(visit))
    }

    /// The percentage of the path's distance, duration, and sample count that is contained inside the given visit.
    public func percentInside(_ visit: Visit) -> Double {
        return visit.containedPercentOf(self)
    }

    internal func maximumMergeableDistance(from visit: Visit) -> CLLocationDistance {
        return visit.maximumMergeableDistance(from: self)
    }

    internal func maximumMergeableDistance(from otherPath: Path) -> CLLocationDistance {
        guard let timeSeparation = self.timeIntervalFrom(otherPath) else {
            return 0
        }
        let mps = (self.mps + otherPath.mps) * 0.5
        return CLLocationDistance(mps * timeSeparation * 4)
    }

    // only sanitises path-path edges. path-visit sanitisation is done by Visit.sanitiseEdges()
    public override func sanitiseEdges() {
        // this hasn't been ported from Arc App yet
    }

    override func samplesChanged() {
        super.samplesChanged()
        _distance = nil
    }
}

extension Path {

    public override var description: String {
        return String(format: "%@ path", isWorthKeeping ? "keeper" : isValid ? "valid" : "invalid")
    }

}

