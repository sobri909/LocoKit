//
//  CoordinateRect.swift
//  LocoKit
//
//  Created by Matt Greenfield on 16/11/22.
//

import Foundation
import CoreLocation

public struct CoordinateRect {
    public var latitudeRange: ClosedRange<CLLocationDegrees>
    public var longitudeRange: ClosedRange<CLLocationDegrees>
}
