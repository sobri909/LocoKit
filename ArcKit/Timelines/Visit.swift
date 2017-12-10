//
//  Visit.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

@objc public class Visit: TimelineItem {

    @objc static var minimumKeeperDuration: TimeInterval = 60 * 2
    @objc static var minimumValidDuration: TimeInterval = 10

    @objc static var minimumRadius: CLLocationDistance = 10
    @objc static var maximumRadius: CLLocationDistance = 150

    @objc public override var isWorthKeeping: Bool {
        if !isValid {
            return false
        }

        if duration < Visit.minimumKeeperDuration {
            return false
        }

        return true
    }

    public override var isValid: Bool {
        if samples.isEmpty {
            return false
        }

        if duration < Visit.minimumValidDuration {
            return false
        }

        return true
    }

    /// Whether the given location falls within this visit's radius.
    func contains(_ location: CLLocation, sd: Double = 4) -> Bool {
        guard let center = center else {
            return false
        }
        return location.distance(from: center) <= _radius.mean + (_radius.sd * sd)
    }

    /// Whether the given visit overlaps this visit.
    public func overlaps(_ otherVisit: Visit) -> Bool {
        guard let separation = distance(from: otherVisit) else {
            return false
        }
        return separation < 0
    }

    /// The percentage of the given path's distance, duration, and sample count that is contained inside this visit.
    public func containedPercentOf(_ path: Path) -> Double {
        let insiders = Array(path.samplesInside(self)).sorted { $0.date < $1.date }

        let insidersDuration = insiders.duration
        let insidersDistance = insiders.distance

        let percentOfPathDuration = path.duration > 0 ? insidersDuration / path.duration : 0
        let percentOfPathDistance = path.distance > 0 ? insidersDistance / path.distance : 0
        let percentOfPathSamples = path.samples.count > 0 ? Double(insiders.count) / Double(path.samples.count) : 0

        return [percentOfPathSamples, percentOfPathDuration, percentOfPathDistance].mean
    }

    internal override func distance(from otherItem: TimelineItem) -> CLLocationDistance? {
        if let path = otherItem as? Path {
            return distance(from: path)
        }
        if let visit = otherItem as? Visit {
            return distance(from: visit)
        }
        return nil
    }
    
    internal func distance(from otherVisit: Visit) -> CLLocationDistance? {
        guard let center = center, let otherCenter = otherVisit.center else {
            return nil
        }
        return center.distance(from: otherCenter) - radius1sd - otherVisit.radius1sd
    }

    internal func distance(from path: Path) -> CLLocationDistance? {
        guard let center = center else {
            return nil
        }
        guard let pathEdge = path.edgeSample(with: self)?.location, pathEdge.hasUsableCoordinate else {
            return nil
        }
        return center.distance(from: pathEdge) - radius1sd
    }

    internal override func maximumMergeableDistance(from otherItem: TimelineItem) -> CLLocationDistance {
        if let path = otherItem as? Path {
            return maximumMergeableDistance(from: path)
        }
        if let visit = otherItem as? Visit {
            return maximumMergeableDistance(from: visit)
        }
        return 0
    }

    private func maximumMergeableDistance(from path: Path) -> CLLocationDistance {
        guard let timeSeparation = self.timeIntervalFrom(path) else {
            return 0
        }
        return CLLocationDistance(path.mps * timeSeparation * 4)
    }

    private func maximumMergeableDistance(from visit: Visit) -> CLLocationDistance {
        return CLLocationDistanceMax
    }

    public override func sanitiseEdges() {
        var lastPreviousChanged: LocomotionSample? = nil
        var lastNextChanged: LocomotionSample? = nil

        while true {
            var previousChanged: LocomotionSample? = nil
            var nextChanged: LocomotionSample? = nil

            if let previousPath = previousItem as? Path {
                previousChanged = self.cleanseVisitEdgeWith(previousPath)
            }

            if let nextPath = nextItem as? Path {
                nextChanged = self.cleanseVisitEdgeWith(nextPath)
            }

            // no changes, so we're done
            if previousChanged == nil && nextChanged == nil {
                break
            }

            // break from an infinite loop
            if previousChanged == lastPreviousChanged && nextChanged == lastNextChanged {
                break
            }

            lastPreviousChanged = previousChanged
            lastNextChanged = nextChanged
        }
    }

    func cleanseVisitEdgeWith(_ path: Path) -> LocomotionSample? {
        if path.samples.isEmpty {
            return nil
        }

        // fail out if separation distance is too much
        guard let separation = distance(from: path), separation <= maximumMergeableDistance(from: path) else {
            return nil
        }

        guard let pathEdge = path.edgeSample(with: self), pathEdge.hasUsableCoordinate else {
            return nil
        }
        guard let pathEdgeLocation = pathEdge.location else {
            return nil
        }
        let pathEdgeIsInside = self.contains(pathEdgeLocation, sd: 1)

        // path edge is inside: move it to the visit
        if pathEdgeIsInside {
            self.add(pathEdge)
            return pathEdge
        }

        guard let visitEdge = self.edgeSample(with: path), visitEdge.hasUsableCoordinate else {
            return nil
        }
        guard let visitEdgeLocation = visitEdge.location else {
            return nil
        }
        let visitEdgeIsInside = self.contains(visitEdgeLocation, sd: 1)

        // visit edge is outside: move it to the path
        if !visitEdgeIsInside {
            path.add(visitEdge)
            return visitEdge
        }

        return nil
    }

    override func samplesChanged() {
        super.samplesChanged()
    }

}

extension Visit {

    public override var description: String {
        return String(format: "%@ visit", isWorthKeeping ? "keeper" : isValid ? "valid" : "invalid")
    }
    
}
