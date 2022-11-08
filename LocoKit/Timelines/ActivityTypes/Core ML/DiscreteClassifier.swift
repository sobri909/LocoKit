//
//  File.swift
//  
//
//  Created by Matt Greenfield on 27/10/22.
//

import Foundation
import CoreLocation

protocol DiscreteClassifier: AnyObject, Identifiable {
    func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults
    func classify(_ classifiables: [ActivityTypeClassifiable]) -> [ClassifierResults]
    func contains(coordinate: CLLocationCoordinate2D) -> Bool
    var completenessScore: Double { get }
    var accuracyScore: Double? { get }
}
