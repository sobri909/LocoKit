//
//  CoordinateTrust.swift
//  LocoKit
//
//  Created by Matt Greenfield on 28/6/19.
//

import GRDB
import CoreLocation

class CoordinateTrust: Record, Codable {

    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
    var trustFactor: Double

    // MARK: -

    var coordinate: CLLocationCoordinate2D {
        get {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }

    // MARK: - Init

    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.trustFactor = 1
        super.init()
    }

    // MARK: - Updating

    func update(from samples: [LocomotionSample]) {
        let speeds = samples.compactMap { $0.location?.speed }.filter { $0 >= 0 }
        let meanSpeed = speeds.mean

        // most common walking speed is 4.4 kmh
        // most common running speed is 9.7 kmh

        let maximumDistrust = 5.0 // maximum distrusted stationary speed in kmh

        trustFactor = 1.0 - (meanSpeed.kmh / maximumDistrust).clamped(min: 0, max: 1)
    }

    // MARK: - Record

    override class var databaseTableName: String { return "CoordinateTrust" }

    enum Columns: String, ColumnExpression {
        case latitude, longitude, trustFactor
    }

    required init(row: Row) {
        self.latitude = row[Columns.latitude]
        self.longitude = row[Columns.longitude]
        self.trustFactor = row[Columns.trustFactor]
        super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.latitude] = coordinate.latitude
        container[Columns.longitude] = coordinate.longitude
        container[Columns.trustFactor] = trustFactor
    }

}
