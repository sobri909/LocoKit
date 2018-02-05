//
//  PersistentSample.swift
//  ArcKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB
import ArcKitCore

open class PersistentSample: LocomotionSample, PersistentObject {

    public override var confirmedType: ActivityTypeName? { didSet { if oldValue != confirmedType { save() } } }

    // MARK: Required initialisers

    public required init(from dict: [String: Any?]) {
        self.lastSaved = dict["lastSaved"] as? Date
        super.init(from: dict)
    }

    public required init(from sample: ActivityBrainSample) { super.init(from: sample) }

    public required init(date: Date, recordingState: RecordingState) {
        super.init(date: date, recordingState: recordingState)
    }

    // MARK: Decodable

    public required init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.lastSaved = try? container.decode(Date.self, forKey: .lastSaved)
            try super.init(from: decoder)
        } catch {
            fatalError("DECODE FAIL: \(error)")
        }
    }

    enum CodingKeys: String, CodingKey {
        case lastSaved
    }

    // MARK: Relationships

    public override var timelineItemId: UUID? { didSet { if oldValue != timelineItemId { save() } } }

    // MARK: Persistable
    
    public static let databaseTableName = "LocomotionSample"

    open func encode(to container: inout PersistenceContainer) {
        container["sampleId"] = sampleId.uuidString
        container["date"] = date
        container["lastSaved"] = transactionDate ?? lastSaved
        container["movingState"] = movingState.rawValue
        container["recordingState"] = recordingState.rawValue
        container["timelineItemId"] = timelineItemId?.uuidString
        container["stepHz"] = stepHz
        container["courseVariance"] = courseVariance
        container["xyAcceleration"] = xyAcceleration
        container["zAcceleration"] = zAcceleration
        container["coreMotionActivityType"] = coreMotionActivityType?.rawValue
        container["confirmedType"] = confirmedType?.rawValue

        // location
        container["latitude"] = location?.coordinate.latitude
        container["longitude"] = location?.coordinate.longitude
        container["altitude"] = location?.altitude
        container["horizontalAccuracy"] = location?.horizontalAccuracy
        container["verticalAccuracy"] = location?.verticalAccuracy
        container["speed"] = location?.speed
        container["course"] = location?.course
    }
    
    // MARK: PersistentObject

    public var persistentStore: PersistentTimelineStore { return store as! PersistentTimelineStore }
    public var transactionDate: Date?
    public var lastSaved: Date?

}

