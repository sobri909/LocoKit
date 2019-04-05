//
//  Visit.swift
//  LocoKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import GRDB
import CoreLocation

open class Visit: TimelineItem {

    public static var minimumKeeperDuration: TimeInterval = 60 * 2
    public static var minimumValidDuration: TimeInterval = 10

    public static var minimumRadius: CLLocationDistance = 10
    public static var maximumRadius: CLLocationDistance = 150

    // MARK: -

    public required init(from dict: [String: Any?], in store: TimelineStore) {
        super.init(from: dict, in: store)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let isVisit = try? container.decode(Bool.self, forKey: .isVisit), isVisit else {
            throw DecodeError.runtimeError("Trying to decode a Path as a Visit")
        }
        try super.init(from: decoder)
    }

    public required init(in store: TimelineStore) {
        super.init(in: store)
    }
    
    // MARK: - Item validity

    open override var isValid: Bool {
        if samples.isEmpty { return false }
        if isNolo { return false }
        if duration < Visit.minimumValidDuration { return false }
        return true
    }

    open override var isWorthKeeping: Bool {
        if isInvalid { return false }
        if duration < Visit.minimumKeeperDuration { return false }
        return true
    }

    // MARK: - Comparisons and Helpers

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

    internal override func cleanseEdge(with path: Path, excluding: Set<LocomotionSample>) -> LocomotionSample? {
        if self.isMergeLocked || path.isMergeLocked { return nil }
        if self.isDataGap || path.isDataGap { return nil }
        if self.deleted || path.deleted { return nil }

        // edge cleansing isn't allowed to push a path into invalid state
        guard path.samples.count > Path.minimumValidSamples else { return nil }

        // fail out if separation distance is too much
        guard withinMergeableDistance(from: path) else { return nil }

        // fail out if separation time is too much
        guard let timeGap = timeInterval(from: path), timeGap < 60 * 10 else { return nil }

        /** GET ALL THE REQUIRED VARS **/

        guard let visitEdge = self.edgeSample(with: path), visitEdge.hasUsableCoordinate else { return nil }
        guard let visitEdgeNext = self.secondToEdgeSample(with: path), visitEdgeNext.hasUsableCoordinate else { return nil }
        guard let pathEdge = path.edgeSample(with: self), pathEdge.hasUsableCoordinate else { return nil }
        guard let pathEdgeNext = path.secondToEdgeSample(with: self), pathEdgeNext.hasUsableCoordinate else { return nil }

        guard let pathEdgeLocation = pathEdge.location else { return nil }
        guard let pathEdgeNextLocation = pathEdgeNext.location else { return nil }

        let pathEdgeIsInside = self.contains(pathEdgeLocation, sd: 1)
        let pathEdgeNextIsInside = self.contains(pathEdgeNextLocation, sd: 1)

        /** ATTEMPT TO MOVE PATH EDGE TO THE VISIT **/

        // path edge is inside and path edge next is inside: move path edge to the visit
        if !excluding.contains(pathEdge), pathEdgeIsInside && pathEdgeNextIsInside {
            self.add(pathEdge)
            return pathEdge
        }

        /** ATTEMPT TO MOVE VISIT EDGE TO THE PATH **/

        // not allowed to move visit edge if too much duration between edge and edge next
        let edgeNextDuration = abs(visitEdge.date.timeIntervalSince(visitEdgeNext.date))
        if edgeNextDuration > .oneMinute * 2 {
            return nil
        }

        // path edge is outside: move visit edge to the path
        if !excluding.contains(visitEdge), !pathEdgeIsInside {
            path.add(visitEdge)
            return visitEdge
        }

        return nil
    }

    override open func samplesChanged() {
        super.samplesChanged()
    }

    // MARK: - PersistantRecord
    
    open override func encode(to container: inout PersistenceContainer) {
        super.encode(to: &container)
        container["isVisit"] = true
    }
}

extension Visit: CustomStringConvertible {

    public var description: String {
        return keepnessString + " visit"
    }
    
}
