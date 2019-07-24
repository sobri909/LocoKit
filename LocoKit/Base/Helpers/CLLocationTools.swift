//
//  CLLocationTools.swift
//  LocoKit
//
//  Created by Matt Greenfield on 3/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public typealias Radians = Double

public typealias AccuracyRange = (best: CLLocationAccuracy, worst: CLLocationAccuracy)

public struct Radius: Codable {

    public let mean: CLLocationDistance
    public let sd: CLLocationDistance

    public static var zero: Radius { return Radius(mean: 0, sd: 0) }

    public init(mean: CLLocationDistance, sd: CLLocationDistance) {
        self.mean = mean
        self.sd = sd
    }

    public var with0sd: CLLocationDistance { return mean }
    public var with1sd: CLLocationDistance { return mean + sd }
    public var with2sd: CLLocationDistance { return withSD(2) }
    public var with3sd: CLLocationDistance { return withSD(3) }

    public func withSD(_ modifier: Double) -> CLLocationDistance { return mean + (sd * modifier) }

}

public extension CLLocationDegrees {
    var radiansValue: Radians {
        return self * Double.pi / 180.0
    }
}

public extension Radians {
    var degreesValue: CLLocationDegrees {
        return self * 180.0 / Double.pi
    }
}

public extension CLLocationDistance {
    static let feetPerMetre = 3.2808399
    var measurement: Measurement<UnitLength> { return Measurement(value: self, unit: UnitLength.meters) }
}

public extension CLLocationSpeed {
    init(kmh: Double) { self.init(kmh / 3.6) }
    var kmh: Double { return self * 3.6 }
    var speedMeasurement: Measurement<UnitSpeed> { return Measurement(value: self, unit: UnitSpeed.metersPerSecond) }
}

public struct CodableLocation: Codable {
    
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let altitude: CLLocationDistance
    let horizontalAccuracy: CLLocationAccuracy
    let verticalAccuracy: CLLocationAccuracy
    let speed: CLLocationSpeed
    let course: CLLocationDirection
    let timestamp: Date

    init(location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.speed = location.speed
        self.course = location.course
        self.timestamp = location.timestamp
    }

}

public extension CLLocationCoordinate2D {
    var isUsable: Bool { return !isNull && isValid }
    var isNullIsland: Bool { return isNull }
    var isNull: Bool { return latitude == 0 && longitude == 0 }
    var isValid: Bool { return CLLocationCoordinate2DIsValid(self) }
}

extension CLLocationCoordinate2D: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        if lhs.latitude != rhs.latitude { return false }
        if lhs.longitude != rhs.longitude { return false }
        return true
    }
}

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

// MARK: - CLLocation

public extension CLLocation {

    convenience init?(weightedCenterFor samples: [LocomotionSample]) {
        self.init(weightedCenterFor: samples.compactMap { $0.hasUsableCoordinate ? $0.location : nil })
    }

    convenience init?(centerFor samples: [LocomotionSample]) {
        self.init(centerFor: samples.compactMap { $0.hasUsableCoordinate ? $0.location : nil })
    }

    /// The weighted centre for an array of locations
    convenience init?(weightedCenterFor locations: [CLLocation]) {
        if locations.isEmpty { return nil }

        guard let accuracyRange = locations.horizontalAccuracyRange else { return nil }

        if locations.count == 1, let location = locations.first {
            self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            return
        }

        var sumx: Double = 0, sumy: Double = 0, sumz: Double = 0, totalWeight: Double = 0

        for location in locations where location.hasUsableCoordinate {
            let lat = location.coordinate.latitude.radiansValue
            let lng = location.coordinate.longitude.radiansValue
            let weight = location.horizontalAccuracyWeight(inRange: accuracyRange)

            sumx += (cos(lat) * cos(lng)) * weight
            sumy += (cos(lat) * sin(lng)) * weight
            sumz += sin(lat) * weight
            totalWeight += weight
        }

        if totalWeight == 0 { return nil }

        let meanx = sumx / totalWeight
        let meany = sumy / totalWeight
        let meanz = sumz / totalWeight

        self.init(x: meanx, y: meany, z: meanz)
    }

    func horizontalAccuracyWeight(inRange range: AccuracyRange) -> Double {
        return 1.0 - (horizontalAccuracy / (range.worst + 1.0))
    }

    func verticalAccuracyWeight(inRange range: AccuracyRange) -> Double {
        return 1.0 - (verticalAccuracy / (range.worst + 1.0))
    }

    // The unweighted centre of an array of locations
    convenience init?(centerFor locations: [CLLocation]) {
        if locations.isEmpty {
            return nil
        }

        if locations.count == 1, let location = locations.first {
            self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            return
        }

        var x: [Double] = []
        var y: [Double] = []
        var z: [Double] = []

        for location in locations where location.hasUsableCoordinate {
            let lat = location.coordinate.latitude.radiansValue
            let lng = location.coordinate.longitude.radiansValue

            x.append(cos(lat) * cos(lng))
            y.append(cos(lat) * sin(lng))
            z.append(sin(lat))
        }

        let meanx = x.mean
        let meany = y.mean
        let meanz = z.mean

        self.init(x: meanx, y: meany, z: meanz)
    }

    convenience init(x: Radians, y: Radians, z: Radians) {
        let lng: Radians = atan2(y, x)
        let hyp = (x * x + y * y).squareRoot()
        let lat: Radians = atan2(z, hyp)
        self.init(latitude: lat.degreesValue, longitude: lng.degreesValue)
    }

    convenience init?(from dict: [String: Any?]) {
        guard let latitude = dict["latitude"] as? Double else { return nil }
        guard let longitude = dict["longitude"] as? Double else { return nil }

        // basic lat/long location
        guard let timestamp = dict["timestamp"] as? Date, let altitude = dict["altitude"] as? Double,
            let horizontalAccuracy = dict["horizontalAccuracy"] as? Double,
            let verticalAccuracy = dict["verticalAccuracy"] as? Double else
        {
            self.init(latitude: latitude, longitude: longitude)
            return
        }

        // complete location with all fields
        if let speed = dict["speed"] as? Double, let course = dict["course"] as? Double {
            self.init(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: altitude,
                      horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy, course: course,
                      speed: speed, timestamp: timestamp)
            return
        }

        // location with all fields except course and speed
        self.init(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: altitude,
                  horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy, timestamp: timestamp)
    }
}

public extension CLLocation {
    convenience init(from codable: CodableLocation) {
        self.init(coordinate: CLLocationCoordinate2D(latitude: codable.latitude, longitude: codable.longitude),
                  altitude: codable.altitude, horizontalAccuracy: codable.horizontalAccuracy,
                  verticalAccuracy: codable.verticalAccuracy, course: codable.course, speed: codable.speed,
                  timestamp: codable.timestamp)
    }
    var codable: CodableLocation {
        return CodableLocation(location: self)
    }
}

public extension CLLocation {
    var isNolo: Bool {
        return !hasUsableCoordinate
    }
    var hasUsableCoordinate: Bool {
        return horizontalAccuracy >= 0 && coordinate.isUsable
    }
}

public extension CLLocation {
    var localTimeZone: TimeZone? {
        return nil
    }
}

// MARK: - [CLLocation]

extension Array where Element: CLLocation {

    public var center: CLLocation? {
        return CLLocation(centerFor: self)
    }
    
    public var weightedCenter: CLLocation? {
        return CLLocation(weightedCenterFor: self)
    }

    public var duration: TimeInterval {
        guard let firstDate = first?.timestamp, let lastDate = last?.timestamp else {
            return 0
        }
        return lastDate.timeIntervalSince(firstDate)
    }

    public var distance: CLLocationDistance {
        var distance: CLLocationDistance = 0
        var previousLocation: CLLocation?
        for location in self {
            if let previous = previousLocation {
                distance += previous.distance(from: location)
            }
            previousLocation = location
        }
        return distance
    }

    func radius(from center: CLLocation) -> Radius {
        guard count > 1 else {
            if let accuracy = first?.horizontalAccuracy, accuracy >= 0 {
                return Radius(mean: accuracy, sd: 0)
            }
            return Radius.zero
        }
        let distances = self.compactMap { $0.hasUsableCoordinate ? $0.distance(from: center) : nil }
        return Radius(mean: distances.mean, sd: distances.standardDeviation)
    }

    public var horizontalAccuracy: CLLocationDistance {
        let accuracies = self.compactMap { $0.horizontalAccuracy >= 0 ? $0.horizontalAccuracy : nil }
        return accuracies.isEmpty ? -1 : accuracies.mean
    }

    public var verticalAccuracy: CLLocationDistance {
        let accuracies = self.compactMap { $0.verticalAccuracy >= 0 ? $0.verticalAccuracy : nil }
        return accuracies.isEmpty ? -1 : accuracies.mean
    }

    public var horizontalAccuracyRange: AccuracyRange? {
        let accuracies = self.compactMap { return $0.hasUsableCoordinate ? $0.horizontalAccuracy : nil }
        if let range = accuracies.range {
            return AccuracyRange(best: range.min, worst: range.max)
        } else {
            return nil
        }
    }

    public var verticalAccuracyRange: AccuracyRange? {
        let accuracies = self.compactMap { return $0.verticalAccuracy > 0 ? $0.verticalAccuracy : nil }
        if let range = accuracies.range {
            return AccuracyRange(best: range.min, worst: range.max)
        } else {
            return nil
        }
    }

    public var weightedMeanAltitude: CLLocationDistance? {
        guard let accuracyRange = verticalAccuracyRange else {
            return nil
        }

        var totalAltitude: Double = 0, totalWeight: Double = 0

        for location in self where location.verticalAccuracy > 0 {
            let weight = location.verticalAccuracyWeight(inRange: accuracyRange)
            totalAltitude += location.altitude * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            return nil
        }

        return totalAltitude / totalWeight
    }
}
