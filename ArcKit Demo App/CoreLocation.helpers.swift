//
//  CLLocation.helpers.swift
//  ArcKit
//
//  Created by Matt Greenfield on 11/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation
import Upsurge

public typealias Radians = Double

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
            
            x.append(Upsurge.cos(lat) * Upsurge.cos(lng))
            y.append(Upsurge.cos(lat) * Upsurge.sin(lng))
            z.append(Upsurge.sin(lat))
        }
        
        let meanx = Upsurge.mean(x)
        let meany = Upsurge.mean(y)
        let meanz = Upsurge.mean(z)
        
        let finalLng: Radians = atan2(meany, meanx)
        let hyp = Upsurge.sqrt(meanx * meanx + meany * meany)
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
        
        return (mean(distances), std(distances))
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
