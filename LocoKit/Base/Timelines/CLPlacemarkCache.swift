//
//  CLPlacemarkCache.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/7/18.
//

import CoreLocation

public class CLPlacemarkCache {

    private static let cache = NSCache<CLLocation, CLPlacemark>()

    private static var fetching: Set<Int> = []

    public static func fetchPlacemark(for location: CLLocation, completion: @escaping (CLPlacemark?) -> Void) {

        // have a cached value? use that
        if let cached = cache.object(forKey: location) {
            completion(cached)
            return
        }

        if fetching.contains(location.hashValue) {
            completion(nil)
            return
        }

        fetching.insert(location.hashValue)

        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            fetching.remove(location.hashValue)

            // nil result? nil completion
            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }

            // cache the result and return it
            cache.setObject(placemark, forKey: location)
            completion(placemark)
        }
    }

    private init() {}

}
