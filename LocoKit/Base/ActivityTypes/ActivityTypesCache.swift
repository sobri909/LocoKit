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

public final class ActivityTypesCache: MLModelSource {
  
    public typealias Model = ActivityType
    public typealias ParentClassifier = ActivityTypeClassifier

    public static var highlander = ActivityTypesCache()

    internal static let minimumRefetchWait: TimeInterval = 60 * 30
    internal static let staleLastUpdatedAge: TimeInterval = 60 * 60 * 24 * 30
    internal static let staleLastFetchedAge: TimeInterval = 60 * 60 * 24 * 7

    var cache: [ActivityType] = []
    let mutex = UnfairLock()

    public init() {}
    
    public var providesDepths = [0, 1, 2]
    
    public func modelFor(name: ActivityTypeName, coordinate: CLLocationCoordinate2D, depth: Int) -> ActivityType? {
        guard providesDepths.contains(depth) else {
            return nil
        }
        
        var match: ActivityType?
        mutex.sync {
            if depth == 0 {
                match = cache.filter { $0.name == name && $0.depth == 0 }.first
            } else {
                match = cache.filter { $0.name == name && $0.contains(coordinate: coordinate) && $0.depth == depth }.first
            }
        }
        
        return match
    }
    
    public func modelsFor(names: [ActivityTypeName], coordinate: CLLocationCoordinate2D, depth: Int) -> [ActivityType] {
        var matches: [ActivityType] = []
        for name in names {
            if let match = modelFor(name: name, coordinate: coordinate, depth: depth) {
                matches.append(match)
            }
        }

        // start a new fetch if needed
        if matches.isEmpty || matches.isStale {
            fetchTypesFor(coordinate: coordinate, depth: depth)
        }

        return matches
    }
    
    public func add(_ model: ActivityType) {
        mutex.sync {
            // already in the cache? replace it
            let ditchees = cache.filter { $0 == model }
            cache.removeObjects(ditchees)
            
            // add it
            cache.append(model)
        }
    }
   
    // MARK: - Model fetching

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
        guard let typeDicts = json["activityTypes"] as? [[String: Any]] else { return }
        
        for typeDict in typeDicts {
            if let type = ActivityType(dict: typeDict) {
                add(type)
            }
        }
    }
}
