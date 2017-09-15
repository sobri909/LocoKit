//
//  CLLocation.helpers.swift
//  ArcKit
//
//  Created by Matt Greenfield on 11/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

typealias Radians = Double

extension CLLocation {
    
    // find the centre of an array of locations
    convenience init?(locations: [CLLocation]) {
        guard !locations.isEmpty else {
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
        
        let finalLng: Radians = atan2(meany, meanx)
        let hyp = (meanx * meanx + meany * meany).squareRoot()
        let finalLat: Radians = atan2(meanz, hyp)
        
        self.init(latitude: finalLat.degreesValue, longitude: finalLng.degreesValue)
    }
    
}

extension Array where Element: CLLocation {
    
    func radiusFrom(center: CLLocation) -> (mean: CLLocationDistance, sd: CLLocationDistance) {
        guard count > 1 else {
            return (0, 0)
        }
        
        let distances = self.map { $0.distance(from: center) }
        
        return (distances.mean, distances.standardDeviation)
    }
    
}

extension CLLocationDegrees {
    var radiansValue: Radians {
        return self * Double.pi / 180.0
    }
}

extension Radians {
    var degreesValue: CLLocationDegrees {
        return self * 180.0 / Double.pi
    }
}
