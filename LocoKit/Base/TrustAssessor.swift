//
//  TrustAssessor.swift
//  LocoKit
//
//  Created by Matt Greenfield on 30/6/19.
//

import CoreLocation

public protocol TrustAssessor {
    func trustFactorFor(_ coordinate: CLLocationCoordinate2D) -> Double?
}
