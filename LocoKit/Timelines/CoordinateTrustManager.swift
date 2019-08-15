//
//  CoordinateTrustManager.swift
//  LocoKit
//
//  Created by Matt Greenfield on 30/6/19.
//

import os.log
import CoreLocation

public class CoordinateTrustManager: TrustAssessor {

    private let cache = NSCache<Coordinate, CoordinateTrust>()
    public private(set) var lastUpdated: Date?
    public let store: TimelineStore

    // MARK: -

    public init(store: TimelineStore) {
        self.store = store
    }

    // MARK: - Fetching

    public func trustFactorFor(_ coordinate: CLLocationCoordinate2D) -> Double? {
        return modelFor(coordinate)?.trustFactor
    }

    func modelFor(_ coordinate: CLLocationCoordinate2D) -> CoordinateTrust? {
        let rounded = CoordinateTrustManager.roundedCoordinateFor(coordinate)

        // cached?
        if let model = cache.object(forKey: rounded) { return model }

        if let model = try? store.auxiliaryPool.read({
            try CoordinateTrust.fetchOne($0, sql: "SELECT * FROM CoordinateTrust WHERE latitude = ? AND longitude = ?",
                                         arguments: [rounded.latitude, rounded.longitude])
        }) {
            if let model = model {
                cache.setObject(model, forKey: rounded)
            }
            return model
        }

        return nil
    }

    // MARK: -

    static func roundedCoordinateFor(_ coordinate: CLLocationCoordinate2D) -> Coordinate {
        let rounded = CLLocationCoordinate2D(latitude: round(coordinate.latitude * 10000) / 10000,
                                             longitude: round(coordinate.longitude * 10000) / 10000)
        return Coordinate(coordinate: rounded)
    }

    // MARK: - Updating

    public func updateTrustFactors() {
        // don't update too frequently
        if let lastUpdated = lastUpdated, lastUpdated.age < .oneDay { return }

        os_log("CoordinateTrustManager.updateTrustFactors", type: .debug)

        self.lastUpdated = Date()

        // fetch most recent X confirmed stationary samples
        let samples = self.store.samples(where: "confirmedType = ? ORDER BY lastSaved DESC LIMIT 2000", arguments: ["stationary"])

        // collate the samples into coordinate buckets
        var buckets: [Coordinate: [LocomotionSample]] = [:]
        for sample in samples where sample.hasUsableCoordinate {
            guard let coordinate = sample.location?.coordinate else { continue }

            let rounded = CoordinateTrustManager.roundedCoordinateFor(coordinate)
            if let samples = buckets[rounded] {
                buckets[rounded] = samples + [sample]
            } else {
                buckets[rounded] = [sample]
            }
        }

        // for each bucket, fetch/create the model
        var models: [CoordinateTrust] = []
        for (coordinate, samples) in buckets {
            let model: CoordinateTrust
            if let trust = self.modelFor(coordinate.coordinate) {
                model = trust
            } else {
                model = CoordinateTrust(coordinate: coordinate.coordinate)
            }
            models.append(model)

            // update the model's trustFactor
            model.update(from: samples)
        }

        // save/update the models
        do {
            try self.store.auxiliaryPool.write { db in
                for model in models {
                    try model.save(db)
                }
            }
        } catch {
            print("ERROR: \(error)")
        }
    }

}

class Coordinate: NSObject {

    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    var coordinate: CLLocationCoordinate2D { return CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    // MARK: - Hashable

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Coordinate else { return false }
        return other.latitude == latitude && other.longitude == longitude
    }

    override var hash: Int {
        return latitude.hashValue ^ latitude.hashValue
    }

}
