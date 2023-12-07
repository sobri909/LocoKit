//
//  ActivityTypesCache.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 30/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation
import GRDB

public final class ActivityTypesCache {
  
    public static var highlander = ActivityTypesCache()

    public var store: TimelineStore?

    public init() {}

    // MARK: - Core ML model fetching

    public func coreMLModelFor(coordinate: CLLocationCoordinate2D, depth: Int) -> CoreMLModelWrapper? {
        guard let store = store else { return nil }

        var query = "SELECT * FROM CoreMLModel WHERE depth = ?"
        var arguments: [DatabaseValueConvertible] = [depth]

        if depth > 0 {
            query += " AND latitudeMin <= ? AND latitudeMax >= ? AND longitudeMin <= ? AND longitudeMax >= ?"
            arguments.append(coordinate.latitude)
            arguments.append(coordinate.latitude)
            arguments.append(coordinate.longitude)
            arguments.append(coordinate.longitude)
        }

        if let model = store.coreMLModel(for: query, arguments: StatementArguments(arguments)) {
            return model
        }

        // create if missing
        let model = CoreMLModelWrapper(coordinate: coordinate, depth: depth, in: store)
        logger.info("NEW CORE ML MODEL: [\(model.geoKey)]")
        model.needsUpdate = true
        model.save()
        return model
    }

}
