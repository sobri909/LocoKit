//
//  MLModelCache.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 11/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public protocol MLModelSource {
    associatedtype Model: MLModel
    associatedtype ParentClassifier: MLClassifier

    static var highlander: Self { get }
    var providesDepths: [Int] { get }
    func modelFor(name: ActivityTypeName, coordinate: CLLocationCoordinate2D, depth: Int) -> Model?
    func modelsFor(names: [ActivityTypeName], coordinate: CLLocationCoordinate2D, depth: Int) -> [Model]
}

public extension Array where Element: MLModel {

    var completenessScore: Double {
        if isEmpty {
            return 0
        }
        var total = 0.0
        var modelCount = 0
        for model in self where model.name != .bogus {
            total += model.completenessScore
            modelCount += 1
        }
        return modelCount > 0 ? total / Double(modelCount) : 0
    }

    var accuracyScore: Double? {
        var totalScore = 0.0, totalWeight = 0.0
        for model in self {
            if let score = model.accuracyScore, score >= 0 {
                totalScore += score * Double(model.totalSamples)
                totalWeight += Double(model.totalSamples)
            }
        }
        return totalWeight > 0 ? totalScore / totalWeight : nil
    }

    var lastUpdated: Date? {
        var mostRecentUpdate: Date?
        for model in self {
            if let lastUpdated = model.lastUpdated, mostRecentUpdate == nil || lastUpdated > mostRecentUpdate! {
                mostRecentUpdate = lastUpdated
            }
        }
        return mostRecentUpdate
    }

    var lastFetched: Date {
        var mostRecentFetch = Date.distantPast
        for model in self {
            if model.lastFetched > mostRecentFetch {
                mostRecentFetch = model.lastFetched
            }
        }
        return mostRecentFetch
    }

    var missingBaseTypes: [ActivityTypeName] {
        let haveTypes = self.map { $0.name }
        return ActivityTypeName.baseTypes.filter { !haveTypes.contains($0) }
    }

    var isStale: Bool {
        if isEmpty { return true }

        // missing a base model?
        guard missingBaseTypes.isEmpty else { return true }

        // nil lastUpdated is presumably UD models pending first update
        guard let lastUpdated = lastUpdated else { return false }

        // last fetch was too recent?
        if lastFetched.age < ActivityTypesCache.minimumRefetchWait { return false }

        // last updated recently enough?
        if lastUpdated.age < ActivityTypesCache.staleLastUpdatedAge * completenessScore { return false }

        // last fetched recently enough?
        if lastFetched.age < ActivityTypesCache.staleLastFetchedAge * completenessScore { return false }

        return true
    }
}
