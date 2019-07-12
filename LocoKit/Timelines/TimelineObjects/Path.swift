//
//  Path.swift
//  LocoKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import GRDB
import Upsurge
import CoreLocation

open class Path: TimelineItem, CustomStringConvertible {

    // valid path settings
    public static var minimumValidDuration: TimeInterval = 10
    public static var minimumValidDistance: Double = 10
    public static var minimumValidSamples = 2

    // keeper path settings
    public static var minimumKeeperDuration: TimeInterval = 60
    public static var minimumKeeperDistance: Double = 20

    // data gap settings
    public static var minimumValidDataGapDuration: TimeInterval = 60
    public static var minimumKeeperDataGapDuration: TimeInterval = 60 * 60 * 24

    public static var maximumModeShiftSpeed = CLLocationSpeed(kmh: 2)

    public private(set) var _distance: CLLocationDistance?

    // MARK: -
    
    public required init(from dict: [String: Any?], in store: TimelineStore) {
        self._distance = dict["distance"] as? CLLocationDistance
        super.init(from: dict, in: store)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let isVisit = try? container.decode(Bool.self, forKey: .isVisit), !isVisit else {
            throw DecodeError.runtimeError("Trying to decode a Visit as a Path")
        }
        try super.init(from: decoder)
    }

    public required init(in store: TimelineStore) {
        super.init(in: store)
    }

    // MARK: - Item validity

    open override var isValid: Bool {
        if isDataGap { return isValidDataGap }
        if isNolo { return isValidPathNolo }
        if samples.count < Path.minimumValidSamples { return false }
        if duration < Path.minimumValidDuration { return false }
        if distance < Path.minimumValidDistance { return false }
        return true
    }

    open override var isWorthKeeping: Bool {
        if isDataGap { return dataGapIsWorthKeeping }
        if !isValid { return false }
        if duration < Path.minimumKeeperDuration { return false }
        if distance < Path.minimumKeeperDistance { return false }
        return true
    }

    private var isValidDataGap: Bool {
        if duration < Path.minimumValidDataGapDuration { return false }
        return true
    }

    private var isValidPathNolo: Bool {
        if samples.count < Path.minimumValidSamples { return false }
        if duration < Path.minimumValidDuration { return false }
        return true
    }

    private var dataGapIsWorthKeeping: Bool {
        if !isValidDataGap { return false }
        if duration < Path.minimumKeeperDataGapDuration { return false }
        return true
    }

    // MARK: - Distance and speed

    /// The distance of the path, as the sum of the distances between each sample.
    public var distance: CLLocationDistance {
        if let distance = _distance { return distance }
        let distance = samples.distance
        _distance = distance
        return distance
    }

    public var metresPerSecond: CLLocationSpeed {
        if samples.count == 1, let sampleSpeed = samples.first?.location?.speed, sampleSpeed >= 0 { return sampleSpeed }
        if duration > 0 { return distance / duration }
        return 0
    }

    public var speed: CLLocationSpeed { return metresPerSecond }

    public var mps: CLLocationSpeed { return metresPerSecond }

    public var kph: Double { return kilometresPerHour }

    public var kmh: Double { return kilometresPerHour }

    public var kilometresPerHour: Double { return mps * 3.6 }

    public var mph: Double { return milesPerHour }

    public var milesPerHour: Double { return kilometresPerHour / 1.609344 }

    // MARK: - Comparisons and Helpers

    public override func distance(from otherItem: TimelineItem) -> CLLocationDistance? {
        if let path = otherItem as? Path { return distance(from: path) }
        if let visit = otherItem as? Visit { return distance(from: visit) }
        return nil
    }

    private func distance(from visit: Visit) -> CLLocationDistance? { return visit.distance(from: self) }
    
    private func distance(from otherPath: Path) -> CLLocationDistance? {
        guard let myStart = startDate, let theirStart = otherPath.startDate else { return nil }
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

    public override func contains(_ location: CLLocation, sd: Double?) -> Bool {
        var sampleLocation: CLLocation?
        var distanceToPrev: CLLocationDistance = 0
        var distanceToNext: CLLocationDistance = 0

        for nextSample in samples {
            guard let nextSampleLocation = nextSample.location else {
                continue
            }

            // TODO: this could use the sample's horizontalAccuracy
            let minimumRadius: CLLocationDistance = 10

            // get distance from current to next
            if let current = sampleLocation {
                distanceToNext = current.distance(from: nextSampleLocation)
            }

            // choose largest distance of toPrev, toNext, and minRadius
            let radius = max(max(distanceToPrev, distanceToNext), minimumRadius)

            // test location against current
            if let current = sampleLocation {
                if location.distance(from: current) <= radius {
                    return true
                }
            }

            // prep the next cycle
            distanceToPrev = distanceToNext
            sampleLocation = nextSampleLocation
        }

        return false
    }
    
    open func samplesInside(_ visit: Visit) -> Set<LocomotionSample> {
        guard let visitCenter = visit.center else {
            return []
        }
        var insiders: Set<LocomotionSample> = []
        for sample in samples where sample.hasUsableCoordinate {
            guard let sampleLocation = sample.location else { continue }
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

    public override func maximumMergeableDistance(from otherItem: TimelineItem) -> CLLocationDistance {
        if let path = otherItem as? Path {
            return maximumMergeableDistance(from: path)
        }
        if let visit = otherItem as? Visit {
            return maximumMergeableDistance(from: visit)
        }
        return 0
    }

    private func maximumMergeableDistance(from visit: Visit) -> CLLocationDistance {
        return visit.maximumMergeableDistance(from: self)
    }

    private func maximumMergeableDistance(from otherPath: Path) -> CLLocationDistance {
        guard let timeSeparation = self.timeInterval(from: otherPath) else {
            return 0
        }
        var speeds: [CLLocationSpeed] = []
        if self.mps > 0 {
            speeds.append(self.mps)
        }
        if otherPath.mps > 0 {
            speeds.append(otherPath.mps)
        }
        return CLLocationDistance(mean(speeds) * timeSeparation * 4)
    }

    internal override func cleanseEdge(with otherPath: Path, excluding: Set<LocomotionSample>) -> LocomotionSample? {
        if self.isMergeLocked || otherPath.isMergeLocked { return nil }
        if self.isDataGap || otherPath.isDataGap { return nil }
        if self.deleted || otherPath.deleted { return nil }
        if otherPath.samples.isEmpty { return nil }

        // fail out if separation distance is too much
        guard withinMergeableDistance(from: otherPath) else { return nil }

        // fail out if separation time is too much
        guard let timeGap = timeInterval(from: otherPath), timeGap < 60 * 10 else { return nil }

        // get the activity types
        guard let myActivityType = self.activityType else { return nil }
        guard let theirActivityType = otherPath.activityType else { return nil }

        // can't path-path cleanse two paths of same type
        if myActivityType == theirActivityType { return nil }

        // get the edges
        guard let myEdge = self.edgeSample(with: otherPath) else { return nil }
        guard let theirEdge = otherPath.edgeSample(with: self) else { return nil }
        guard myEdge.hasUsableCoordinate, theirEdge.hasUsableCoordinate else { return nil }
        guard let myEdgeLocation = myEdge.location, let theirEdgeLocation = theirEdge.location else { return nil }

        let mySpeedIsSlow = myEdgeLocation.speed < Path.maximumModeShiftSpeed
        let theirSpeedIsSlow = theirEdgeLocation.speed < Path.maximumModeShiftSpeed

        // are the edges on opposite sides of the mode change speed boundary?
        if mySpeedIsSlow != theirSpeedIsSlow { return nil }
        
        // is their edge my activity type?
        if !excluding.contains(theirEdge), theirEdge.activityType == myActivityType {
            print("stealing otherPath edge")
            self.add(theirEdge)
            return theirEdge
        }

        return nil
    }

    override open func samplesChanged() {
        super.samplesChanged()
        _distance = nil
    }

    // MARK: - PersistableRecord

    open override func encode(to container: inout PersistenceContainer) {
        super.encode(to: &container)
        container["isVisit"] = false
        container["distance"] = _distance
        container["activityType"] = _modeMovingActivityType?.rawValue
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        let itemType = isDataGap ? "datagap" : isNolo ? "nolo" : "path"
        return String(format: "%@ %@", keepnessString, itemType)
    }

}

