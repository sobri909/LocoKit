//
//  CLLocationTools.swift
//  ArcKit
//
//  Created by Matt Greenfield on 3/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public typealias Radians = Double

public typealias AccuracyRange = (best: CLLocationAccuracy, worst: CLLocationAccuracy)

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

extension CLLocationDistance {
    static let feetPerMetre = 3.2808399
}

extension CLLocationSpeed {
    init(kmh: Double) {
        self.init(kmh / 3.6)
    }
}

public extension CLLocation {

    public convenience init?(weightedCenterFor samples: [LocomotionSample]) {
        self.init(weightedCenterFor: samples.flatMap { $0.location })
    }

    public convenience init?(centerFor samples: [LocomotionSample]) {
        self.init(centerFor: samples.flatMap { $0.location })
    }

    /// The weighted centre for an array of locations
    public convenience init?(weightedCenterFor locations: [CLLocation]) {
        if locations.isEmpty {
            return nil
        }

        guard let accuracyRange = locations.horizontalAccuracyRange else {
            return nil
        }

        var sumx: Double = 0, sumy: Double = 0, sumz: Double = 0, totalWeight: Double = 0

        for location in locations {
            let lat = location.coordinate.latitude.radiansValue
            let lng = location.coordinate.longitude.radiansValue
            let weight = location.horizontalAccuracyWeight(inRange: accuracyRange)

            sumx += (cos(lat) * cos(lng)) * weight
            sumy += (cos(lat) * sin(lng)) * weight
            sumz += sin(lat) * weight
            totalWeight += weight
        }

        if totalWeight == 0 {
            return nil
        }

        let meanx = sumx / totalWeight
        let meany = sumy / totalWeight
        let meanz = sumz / totalWeight

        self.init(x: meanx, y: meany, z: meanz)
    }

    func horizontalAccuracyWeight(inRange range: AccuracyRange) -> Double {
        return 1.0 - (horizontalAccuracy / (range.worst + 1.0))
    }

    // The unweighted centre of an array of locations
    public convenience init?(centerFor locations: [CLLocation]) {
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

        for location in locations {
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

    public convenience init(x: Radians, y: Radians, z: Radians) {
        let lng: Radians = atan2(y, x)
        let hyp = (x * x + y * y).squareRoot()
        let lat: Radians = atan2(z, hyp)
        self.init(latitude: lat.degreesValue, longitude: lng.degreesValue)
    }
}

public extension CLLocation {

    public var hasUsableCoordinate: Bool {
        return horizontalAccuracy > 0 && coordinate.isUsable
    }

}

public extension CLLocationCoordinate2D {

    public var isUsable: Bool {
        return !isNull && isValid
    }

    public var isNullIsland: Bool {
        return isNull
    }

    public var isNull: Bool {
        return latitude == 0 && longitude == 0
    }

    public var isValid: Bool {
        return CLLocationCoordinate2DIsValid(self)
    }

}

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

    func radiusFrom(center: CLLocation) -> (mean: CLLocationDistance, sd: CLLocationDistance) {
        guard count > 1 else {
            return (0, 0)
        }
        let distances = self.map { $0.distance(from: center) }
        return (mean: distances.mean, sd: distances.standardDeviation)
    }

    public var horizontalAccuracyRange: AccuracyRange? {
        let accuracies = self.flatMap { return $0.hasUsableCoordinate ? $0.horizontalAccuracy : nil }
        if let range = accuracies.range {
            return AccuracyRange(best: range.min, worst: range.max)
        } else {
            return nil
        }
    }

    public var verticalAccuracyRange: AccuracyRange? {
        let accuracies = self.flatMap { return $0.verticalAccuracy > 0 ? $0.verticalAccuracy : nil }
        if let range = accuracies.range {
            return AccuracyRange(best: range.min, worst: range.max)
        } else {
            return nil
        }
    }

}
