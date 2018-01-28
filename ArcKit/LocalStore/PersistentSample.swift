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

    // MARK: PersistentObject

    public var persistentStore: PersistentTimelineStore { return store as! PersistentTimelineStore }
    public var transactionDate: Date?
    public var lastSaved: Date?

    open func insert(in db: Database) throws {
        guard unsaved else { return }
        try db.execute("""
            INSERT INTO LocomotionSample (
                sampleId, lastSaved, timelineItemId, date, movingState,
                recordingState, stepHz, courseVariance, xyAcceleration, zAcceleration,
                coreMotionActivityType, confirmedType, latitude,
                longitude, altitude, horizontalAccuracy,
                verticalAccuracy, speed, course
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                sampleId.uuidString, transactionDate, timelineItemId?.uuidString, date, movingState.rawValue,
                recordingState.rawValue, stepHz, courseVariance, xyAcceleration, zAcceleration,
                coreMotionActivityType?.rawValue, confirmedType?.rawValue, location?.coordinate.latitude,
                location?.coordinate.longitude, location?.altitude, location?.horizontalAccuracy,
                location?.verticalAccuracy, location?.speed, location?.course
            ])
    }

    open func update(in db: Database) throws {
        if unsaved { return }
        try db.execute("""
            UPDATE LocomotionSample SET
                lastSaved = ?, timelineItemId = ?, date = ?, movingState = ?, recordingState = ?, stepHz = ?,
                courseVariance = ?, xyAcceleration = ?, zAcceleration = ?, coreMotionActivityType = ?,
                confirmedType = ?, latitude = ?, longitude = ?,
                altitude = ?, horizontalAccuracy = ?, verticalAccuracy = ?, speed = ?,
                course = ?
            WHERE sampleId = ?
            """, arguments: [
                transactionDate, timelineItemId?.uuidString, date, movingState.rawValue, recordingState.rawValue, stepHz,
                courseVariance, xyAcceleration, zAcceleration, coreMotionActivityType?.rawValue,
                confirmedType?.rawValue, location?.coordinate.latitude, location?.coordinate.longitude,
                location?.altitude, location?.horizontalAccuracy, location?.verticalAccuracy, location?.speed,
                location?.course, sampleId.uuidString
            ])
    }
}

