//
//  CLPlacemarkCache.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/7/18.
//

import LocoKitCore
import CoreLocation

public class CLPlacemarkCache {

    private static let cache = NSCache<CLLocation, CLPlacemark>()

    private static let mutex = UnfairLock()

    private static var fetching: Set<Int> = []

    public static func fetchPlacemark(for location: CLLocation, completion: @escaping (CLPlacemark?) -> Void) {

        // have a cached value? use that
        if let cached = cache.object(forKey: location) {
            completion(cached)
            return
        }

        let alreadyFetching = mutex.sync { fetching.contains(location.hashValue) }
        if alreadyFetching {
            completion(nil)
            return
        }

        mutex.sync { fetching.insert(location.hashValue) }

        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            mutex.sync { fetching.remove(location.hashValue) }

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
