//
//  PersistentSample.swift
//  LocoKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB
import LocoKitCore
import CoreLocation

open class PersistentSample: LocomotionSample, PersistentObject {

    public override var confirmedType: ActivityTypeName? {
        didSet {
            if oldValue != confirmedType {
                hasChanges = true
                save()
            }
        }
    }

    // MARK: Required initialisers

    public required init(from dict: [String: Any?]) {
        self.lastSaved = dict["lastSaved"] as? Date
        super.init(from: dict)
    }

    public required init(from sample: ActivityBrainSample) { super.init(from: sample) }

    public required init(date: Date, location: CLLocation? = nil, movingState: MovingState = .uncertain,
                         recordingState: RecordingState) {
        super.init(date: date, location: location, movingState: movingState, recordingState: recordingState)
    }

    // MARK: Decodable

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    // MARK: Relationships

    public override var timelineItemId: UUID? {
        didSet {
            if oldValue != timelineItemId {
                hasChanges = true
                save()
            }
        }
    }

    public private(set) var deleted = false 
    open override func delete() {
        deleted = true
        hasChanges = true
        timelineItem?.remove(self)
        save()
    }

    // MARK: Persistable
    
    public static let databaseTableName = "LocomotionSample"

    open func encode(to container: inout PersistenceContainer) {
        container["sampleId"] = sampleId.uuidString
        container["source"] = source
        container["date"] = date
        container["deleted"] = deleted
        container["lastSaved"] = transactionDate ?? lastSaved ?? Date()
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

    public var persistentStore: PersistentTimelineStore? { return store as? PersistentTimelineStore }
    public var transactionDate: Date?
    public var lastSaved: Date?
    public var hasChanges: Bool = false

}

