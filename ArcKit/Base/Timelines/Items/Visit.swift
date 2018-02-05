//
//  Visit.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

open class Visit: TimelineItem {

    public static var minimumKeeperDuration: TimeInterval = 60 * 2
    public static var minimumValidDuration: TimeInterval = 10

    public static var minimumRadius: CLLocationDistance = 10
    public static var maximumRadius: CLLocationDistance = 150

    open override var isValid: Bool {
        if samples.isEmpty { return false }
        if duration < Visit.minimumValidDuration { return false }
        return true
    }

    open override var isWorthKeeping: Bool {
        if !isValid { return false }
        if duration < Visit.minimumKeeperDuration { return false }
        return true
    }

    /// Whether the given location falls within this visit's radius.
    public override func contains(_ location: CLLocation, sd: Double = 4) -> Bool {
        guard let center = center else { return false }
        let testRadius = radius.withSD(sd).clamped(min: Visit.minimumRadius, max: Visit.maximumRadius)
        return location.distance(from: center) <= testRadius
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

    public override func distance(from otherItem: TimelineItem) -> CLLocationDistance? {
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
        return center.distance(from: otherCenter) - radius2sd - otherVisit.radius2sd
    }

    internal func distance(from path: Path) -> CLLocationDistance? {
        guard let center = center else {
            return nil
        }
        guard let pathEdge = path.edgeSample(with: self)?.location, pathEdge.hasUsableCoordinate else {
            return nil
        }
        return center.distance(from: pathEdge) - radius2sd
    }

    public override func maximumMergeableDistance(from otherItem: TimelineItem) -> CLLocationDistance {
        if let path = otherItem as? Path {
            return maximumMergeableDistance(from: path)
        }
        if let visit = otherItem as? Visit {
            return maximumMergeableDistance(from: visit)
        }
        return 0
    }

    private func maximumMergeableDistance(from path: Path) -> CLLocationDistance {

        // visit-path gaps less than this should be forgiven
        let minimum: CLLocationDistance = 150

        guard let timeSeparation = self.timeInterval(from: path) else {
            return 0
        }
        let rawMax = CLLocationDistance(path.mps * timeSeparation * 4)

        return max(rawMax, minimum)
    }

    private func maximumMergeableDistance(from visit: Visit) -> CLLocationDistance {
        return CLLocationDistanceMax
    }

    public override func cleanseEdge(with path: Path) -> LocomotionSample? {
        if self.isMergeLocked || path.isMergeLocked { return nil }

        if path.samples.isEmpty { return nil }

        // fail out if separation distance is too much
        guard withinMergeableDistance(from: path) else {
            return nil
        }

        /** GET ALL THE REQUIRED VARS **/

        guard
            let visitEdge = self.edgeSample(with: path),
            let pathEdge = path.edgeSample(with: self),
            let pathEdgeNext = path.secondToEdgeSample(with: self) else
        { return nil }

        guard visitEdge.hasUsableCoordinate, pathEdge.hasUsableCoordinate, pathEdgeNext.hasUsableCoordinate else {
            return nil
        }
        guard
            let visitEdgeLocation = visitEdge.location,
            let pathEdgeLocation = pathEdge.location,
            let pathEdgeNextLocation = pathEdgeNext.location else
        { return nil }

        let visitEdgeIsInside = self.contains(visitEdgeLocation, sd: 2)
        let pathEdgeIsInside = self.contains(pathEdgeLocation, sd: 2)
        let pathEdgeNextIsInside = self.contains(pathEdgeNextLocation, sd: 2)

        /** ATTEMPT TO MOVE A PATH EDGE TO THE VISIT **/

        // path edge is inside and path edge next is inside: move path edge to the visit
        if pathEdgeIsInside && pathEdgeNextIsInside {
            self.add(pathEdge)
            NotificationCenter.default.post(Notification(name: .debugInfo, object: store?.manager,
                                                         userInfo: ["info": "moved path edge to visit"]))
            return pathEdge
        }

        /** ATTEMPT TO MOVE A VISIT EDGE TO THE PATH **/

        // path edge is outside and visit edge is outside: move visit edge to the path
        if !pathEdgeIsInside && !visitEdgeIsInside {
            path.add(visitEdge)
            NotificationCenter.default.post(Notification(name: .debugInfo, object: store?.manager,
                                                         userInfo: ["info": "moved visit edge to path"]))
            return visitEdge
        }

        // path edge is outside and visit edge type matches path edge type: move visit edge to the path
        if
            !pathEdgeIsInside, let visitEdgeType = visitEdge.activityType, visitEdgeType != .stationary,
            visitEdgeType == pathEdge.activityType
        {
            path.add(visitEdge)
            NotificationCenter.default.post(Notification(name: .debugInfo, object: store?.manager,
                                                         userInfo: ["info": "moved visit edge to path"]))
            return visitEdge
        }

        return nil
    }

    override open func samplesChanged() {
        super.samplesChanged()
    }
}

extension Visit: CustomStringConvertible {

    public var description: String {
        return String(format: "%@ visit", isWorthKeeping ? "keeper" : isValid ? "valid" : "invalid")
    }
    
}
