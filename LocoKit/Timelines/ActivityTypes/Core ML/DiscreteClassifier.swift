//
//  File.swift
//  
//
//  Created by Matt Greenfield on 27/10/22.
//

import Foundation
import CoreLocation

public protocol DiscreteClassifier: AnyObject, Identifiable {
    var depth: Int { get }
    var geoKey: String { get }
    var totalSamples: Int { get }
    func classify(_ classifiable: ActivityTypeClassifiable) -> ClassifierResults
    func contains(coordinate: CLLocationCoordinate2D) -> Bool
    var completenessScore: Double { get }
    var accuracyScore: Double? { get }
}
