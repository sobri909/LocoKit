//
//  TimezoneFetcher.swift
//
//  Created by Matt Greenfield on 22/1/24.
//  Copyright © 2024 Big Paua. All rights reserved.
//

import Foundation
import CoreLocation

public actor TimezoneFetcher {

    public static let highlander = TimezoneFetcher()

    private let geocoder = CLGeocoder()
    private var cache = [String: TimeZone]()
    private var currentTask: Task<Void, Never>? = nil
    private var currentTaskStart: Date?

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let bucket = CoordinateTrustManager.roundedCoordinateFor(coordinate, roundingDistance: 10_000)
        return "\(bucket.latitude),\(bucket.longitude)"
    }

    private func setCache(value timezone: TimeZone, for cacheKey: String) {
        cache[cacheKey] = timezone
    }

    public func timezone(for location: CLLocation) async -> TimeZone? {
        let key = cacheKey(for: location.coordinate)

        if let cached = cache[key] { return cached }

        if let currentTask {
            if let currentTaskStart, currentTaskStart.age > 10 {
                print("TimezoneFetcher cancelling previous geocoder lookup")
                currentTask.cancel()
            } else {
                print("TimezoneFetcher awaiting previous geocoder lookup")
                await currentTask.value
            }
        }

        if let cached = cache[key] { return cached }

        let newTask = Task<Void, Never> {
            await withTaskCancellationHandler {
                do {
                    print("TimezoneFetcher doing geocoder lookup: \(key)")
                    let placemarks = try await geocoder.reverseGeocodeLocation(location)
                    let timezone = placemarks.first?.timeZone
                    if let timezone {
                        setCache(value: timezone, for: key)
                    }
                } catch {
                    // can't properly catch rate limit errors,
                    // so don't pollute the log file with them
                    print("ERROR: \(error)")
                }
            } onCancel: {
                geocoder.cancelGeocode()
            }
        }

        currentTaskStart = .now
        currentTask = newTask

        await newTask.value

        currentTaskStart = nil
        currentTask = nil

        return cache[key]
    }

}
