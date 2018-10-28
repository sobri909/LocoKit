//
//  ActivityTypesCache.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 30/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import LocoKitCore
import CoreLocation
import GRDB

public final class ActivityTypesCache: MLModelSource {
  
    public typealias Model = ActivityType
    public typealias ParentClassifier = ActivityTypeClassifier

    public static var highlander = ActivityTypesCache()

    internal static let minimumRefetchWait: TimeInterval = .oneHour
    internal static let staleLastUpdatedAge: TimeInterval = .oneMonth * 2
    internal static let staleLastFetchedAge: TimeInterval = .oneWeek

    public var store: TimelineStore?
    let mutex = UnfairLock()

    public init() {}
    
    public var providesDepths = [0, 1, 2]

    public func modelFor(name: ActivityTypeName, coordinate: CLLocationCoordinate2D, depth: Int) -> ActivityType? {
        guard let store = store else { return nil }
        guard providesDepths.contains(depth) else { return nil }

        var query = "SELECT * FROM ActivityTypeModel WHERE isShared = 1 AND name = ? AND depth = ?"
        var arguments: [DatabaseValueConvertible] = [name.rawValue, depth]

        if depth > 0 {
            query += " AND latitudeMin <= ? AND latitudeMax >= ? AND longitudeMin <= ? AND longitudeMax >= ?"
            arguments.append(coordinate.latitude)
            arguments.append(coordinate.latitude)
            arguments.append(coordinate.longitude)
            arguments.append(coordinate.longitude)
        }

        return store.model(for: query, arguments: StatementArguments(arguments))
    }

    public func modelsFor(names: [ActivityTypeName], coordinate: CLLocationCoordinate2D, depth: Int) -> [ActivityType] {
        guard let store = store else { return [] }
        guard providesDepths.contains(depth) else { return [] }

        var query = "SELECT * FROM ActivityTypeModel WHERE isShared = 1 AND depth = ?"
        var arguments: [DatabaseValueConvertible] = [depth]

        let marks = repeatElement("?", count: names.count).joined(separator: ",")
        query += " AND name IN (\(marks))"
        arguments += names.map { $0.rawValue } as [DatabaseValueConvertible]

        if depth > 0 {
            query += " AND latitudeMin <= ? AND latitudeMax >= ? AND longitudeMin <= ? AND longitudeMax >= ?"
            arguments.append(coordinate.latitude)
            arguments.append(coordinate.latitude)
            arguments.append(coordinate.longitude)
            arguments.append(coordinate.longitude)
        }

        let models = store.models(for: query, arguments: StatementArguments(arguments))

        // start a new fetch if needed
        if models.isEmpty || models.isStale {
            fetchTypesFor(coordinate: coordinate, depth: depth)
        }

        // if not D2, only return base types (all extended types are coordinate bound)
        if depth < 2 { return models.filter { ActivityTypeName.baseTypes.contains($0.name) } }

        return models
    }
    
    // MARK: - Remote model fetching

    func fetchTypesFor(coordinate: CLLocationCoordinate2D, depth: Int) {
        let latRange = ActivityType.latitudeRangeFor(depth: depth, coordinate: coordinate)
        let lngRange = ActivityType.longitudeRangeFor(depth: depth, coordinate: coordinate)
        let latWidth = latRange.max - latRange.min
        let lngWidth = lngRange.max - lngRange.min
        let depthCenter =  CLLocationCoordinate2D(latitude: latRange.min + latWidth * 0.5,
                                                  longitude: lngRange.min + lngWidth * 0.5)

        LocoKitService.fetchModelsFor(coordinate: depthCenter, depth: depth) { json in
            if let json = json { self.parseTypes(json: json) }
        }
    }
    
    func parseTypes(json: [String: Any]) {
        guard let store = store else { return }
        guard let typeDicts = json["activityTypes"] as? [[String: Any]] else { return }

        for dict in typeDicts {
            let model = ActivityType(dict: dict, in: store)
            model?.save()
        }
    }
}
