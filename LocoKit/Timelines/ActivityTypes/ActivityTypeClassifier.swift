//
//  ActivityTypeClassifier.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 3/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public class ActivityTypeClassifier: MLClassifier, DiscreteClassifier, Hashable {
    public typealias Cache = ActivityTypesCache

    let cache = Cache.highlander

    public let depth: Int
    public let models: [Cache.Model]
    
    public var totalSamples: Int {
        return models.map { $0.totalSamples }.sum
    }

    public var geoKey: String {
        return String(format: "GD\(depth) %.2f,%.2f", centerCoordinate.latitude, centerCoordinate.longitude)
    }

    public lazy var lastUpdated: Date? = {
        return self.models.lastUpdated
    }()

    public lazy var lastFetched: Date = {
        return models.lastFetched
    }()

    public lazy var accuracyScore: Double? = {
        return self.models.accuracyScore
    }()

    public lazy var completenessScore: Double = {
        return self.models.completenessScore
    }()

    // MARK: - Init
    
    required public convenience init?(coordinate: CLLocationCoordinate2D, depth: Int) {
        let models = Cache.highlander.modelsFor(names: ActivityTypeName.allTypes, coordinate: coordinate, depth: depth)
        if models.isEmpty { return nil }
        self.init(models: models, depth: depth)
    }
    
    init(models: [Cache.Model], depth: Int) {
        self.depth = depth
        self.models = models
    }

    // MARK: - Equatable

    open func hash(into hasher: inout Hasher) {
        hasher.combine(geoKey)
    }

    public static func ==(lhs: ActivityTypeClassifier, rhs: ActivityTypeClassifier) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }

    // MARK: - Identifiable

    public var id: String { return geoKey }
}

