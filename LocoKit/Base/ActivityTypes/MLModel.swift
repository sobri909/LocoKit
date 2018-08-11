//
//  MLModel.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 12/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public protocol MLModel: Equatable {
    var name: ActivityTypeName { get }
    var depth: Int { get }
    var totalEvents: Int { get }
    var lastFetched: Date { get }
    var lastUpdated: Date? { get }
    var coverageScore: Double { get }
    var accuracyScore: Double? { get }
    var completenessScore: Double { get }
    var centerCoordinate: CLLocationCoordinate2D { get }
    
    func contains(coordinate: CLLocationCoordinate2D) -> Bool
    func scoreFor(classifiable scorable: ActivityTypeClassifiable) -> Double
}
