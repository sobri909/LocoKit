//
//  MLClassifier.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 20/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public protocol MLClassifier {
    
    associatedtype Cache: MLModelSource

    var depth: Int { get }
    var models: [Cache.Model] { get }
    var centerCoordinate: CLLocationCoordinate2D { get }

    init?(coordinate: CLLocationCoordinate2D, depth: Int)

    func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults
    func contains(coordinate: CLLocationCoordinate2D) -> Bool

    var isStale: Bool { get }
    var lastUpdated: Date? { get }

    var coverageScore: Double { get }
    var accuracyScore: Double? { get }
    var completenessScore: Double { get }
    var coverageScoreString: String { get }
}

extension MLClassifier {

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults {
        var totalSamples = 1 // start with 1 to avoid potential div by zero
        for model in models {
            totalSamples += model.totalSamples
        }

        var scores: [ClassifierResultItem] = []
        for model in models {
            let typeScore = model.scoreFor(classifiable: classifiable, previousResults: previousResults)
            let pctOfAllEvents = Double(model.totalSamples) / Double(totalSamples)
            let finalScore = typeScore * pctOfAllEvents

            let result = ClassifierResultItem(name: model.name, score: finalScore,
                                              modelAccuracyScore: model.accuracyScore)
            scores.append(result)
        }

        return ClassifierResults(results: scores, moreComing: false)
    }

    public func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        if depth == 0 { return true }
        guard let firstType = models.first else { return false }
        return firstType.contains(coordinate: coordinate)
    }

    public var centerCoordinate: CLLocationCoordinate2D {
        if let model = models.first {
            return model.centerCoordinate
        } else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }

    public var isStale: Bool {
        return models.isStale
    }

    public var coverageScore: Double {
        guard let accuracyScore = self.accuracyScore else {
            return self.completenessScore
        }
        return self.completenessScore * accuracyScore
    }

    public var coverageScoreString: String {
        let score = coverageScore

        let intScore = Int(score * 10).clamped(min: 0, max: 10)

        var words: String
        switch intScore {
        case 8...10:
            words = "Excellent"
        case 5...7:
            words = "Very Good"
        case 3...4:
            words = "Good"
        case 1...2:
            words = "Low"
        default:
            words = "Very Low"
        }

        return String(format: "%@ (%.0f%%)", words, score * 100)
    }

}

