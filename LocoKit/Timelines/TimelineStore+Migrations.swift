//
//  TimelineStore+Migrations.swift
//  LocoKit
//
//  Created by Matt Greenfield on 4/6/18.
//

import GRDB

public extension TimelineStore {

    internal func registerMigrations() {

        // initial tables creation
        migrator.registerMigration("CreateTables") { db in

            // MARK: CREATE TimelineItem

            try db.create(table: "TimelineItem") { table in
                table.column("itemId", .text).primaryKey()

                table.column("lastSaved", .datetime).notNull().indexed()
                table.column("deleted", .boolean).notNull()
                table.column("isVisit", .boolean).notNull().indexed()
                table.column("startDate", .datetime).indexed()
                table.column("endDate", .datetime).indexed()
                table.column("source", .text).defaults(to: "LocoKit").indexed()
                table.column("disabled", .boolean).notNull().defaults(to: false)

                table.column("previousItemId", .text).indexed().references("TimelineItem", onDelete: .setNull, deferred: true)
                    .check(sql: "previousItemId != itemId AND (previousItemId IS NULL OR deleted = 0)")
                table.column("nextItemId", .text).indexed().references("TimelineItem", onDelete: .setNull, deferred: true)
                    .check(sql: "nextItemId != itemId AND (nextItemId IS NULL OR deleted = 0)")

                table.column("radiusMean", .double)
                table.column("radiusSD", .double)
                table.column("altitude", .double)
                table.column("stepCount", .integer)
                table.column("floorsAscended", .integer)
                table.column("floorsDescended", .integer)
                table.column("activityType", .text)
                table.column("distance", .double)

                // item.center
                table.column("latitude", .double)
                table.column("longitude", .double)
            }

            // MARK: CREATE LocomotionSample

            try db.create(table: "LocomotionSample") { table in
                table.column("sampleId", .text).primaryKey()
                
                // NOTE: indexing this column will make the SQLite query planner do dumb things
                // make sure you've got a composite index that includes it instead
                // and make sure rtreeId IS NOT the first column in the composite index,
                // otherwise again the query planner will do dumb things
                table.column("rtreeId", .integer)

                table.column("date", .datetime).notNull().indexed()
                table.column("deleted", .boolean).notNull().indexed()
                table.column("lastSaved", .datetime).notNull().indexed()
                table.column("source", .text).defaults(to: "LocoKit").indexed()
                table.column("disabled", .boolean).notNull().defaults(to: false)
                table.column("secondsFromGMT", .integer)

                table.column("movingState", .text).notNull()
                table.column("recordingState", .text).notNull()

                table.column("timelineItemId", .text).references("TimelineItem", onDelete: .setNull, deferred: true)

                table.column("stepHz", .double)
                table.column("courseVariance", .double)
                table.column("xyAcceleration", .double)
                table.column("zAcceleration", .double)
                table.column("classifiedType", .text)
                table.column("confirmedType", .text)
                table.column("previousSampleConfirmedType", .text)

                // sample.location
                table.column("latitude", .double)
                table.column("longitude", .double)
                table.column("altitude", .double)
                table.column("horizontalAccuracy", .double)
                table.column("verticalAccuracy", .double)
                table.column("speed", .double)
                table.column("course", .double)
            }

            // MARK: Multicolumn indexes

            try db.create(index: "LocomotionSample_on_timelineItemId_deleted_date", on: "LocomotionSample",
                          columns: ["timelineItemId", "deleted", "date"])

            try? db.create(
                index: "LocomotionSample_on_lastSaved_rtreeId_confirmedType_xyAcceleration_zAcceleration_stepHz",
                on: "LocomotionSample",
                columns: ["lastSaved", "rtreeId", "confirmedType", "xyAcceleration", "zAcceleration", "stepHz"]
            )

            // MARK: Triggers

            /** maintaining the linked list **/

            try db.execute(sql: """
                CREATE TRIGGER TimelineItem_UPDATE_nextItemId
                    AFTER UPDATE OF nextItemId ON TimelineItem
                    BEGIN
                        UPDATE TimelineItem SET previousItemId = NULL WHERE itemId = OLD.nextItemId;
                        UPDATE TimelineItem SET previousItemId = NEW.itemId WHERE itemId = NEW.nextItemId;
                    END
                """)

            try db.execute(sql: """
                CREATE TRIGGER TimelineItem_UPDATE_previousItemId
                    AFTER UPDATE OF previousItemId ON TimelineItem
                    BEGIN
                        UPDATE TimelineItem SET nextItemId = NULL WHERE itemId = OLD.previousItemId;
                        UPDATE TimelineItem SET nextItemId = NEW.itemId WHERE itemId = NEW.previousItemId;
                    END
                """)

            try db.execute(sql: """
                CREATE TRIGGER TimelineItem_INSERT_previousEdge
                    AFTER INSERT ON TimelineItem
                    WHEN NEW.previousItemId IS NOT NULL
                    BEGIN
                        UPDATE TimelineItem SET nextItemId = NEW.itemId WHERE itemId = NEW.previousItemId;
                    END
                """)
            try db.execute(sql: """
                CREATE TRIGGER TimelineItem_INSERT_nextEdge
                    AFTER INSERT ON TimelineItem
                    WHEN NEW.nextItemId IS NOT NULL
                    BEGIN
                        UPDATE TimelineItem SET previousItemId = NEW.itemId WHERE itemId = NEW.nextItemId;
                    END
                """)

            /** ensure the edges are detached when an item is soft deleted **/

            try db.execute(sql: """
                CREATE TRIGGER TimelineItem_UPDATE_deleted_previousEdge
                    AFTER UPDATE OF deleted ON TimelineItem
                    WHEN NEW.deleted = 1 AND NEW.previousItemId IS NOT NULL
                    BEGIN
                        UPDATE TimelineItem SET nextItemId = NULL WHERE itemId = NEW.previousItemId;
                        UPDATE TimelineItem SET previousItemId = NULL WHERE itemId = NEW.itemId;
                    END
                """)

            try db.execute(sql: """
                CREATE TRIGGER TimelineItem_UPDATE_deleted_nextEdge
                    AFTER UPDATE OF deleted ON TimelineItem
                    WHEN NEW.deleted = 1 AND NEW.nextItemId IS NOT NULL
                    BEGIN
                        UPDATE TimelineItem SET previousItemId = NULL WHERE itemId = NEW.nextItemId;
                        UPDATE TimelineItem SET nextItemId = NULL WHERE itemId = NEW.itemId;
                    END
                """)
        }

        // MARK: - Main database migrations

        migrator.registerMigration("7.0.1 segments") { db in
            try db.create(index: "TimelineItem_on_deleted_startDate", on: "TimelineItem",
                          columns: ["deleted", "startDate"])
        }
    }

    // MARK: - Auxiliary database

    internal func registerAuxiliaryDbMigrations() {

        // MARK: ActivityTypeModel

        auxiliaryDbMigrator.registerMigration("7.0.0 models") { db in
            try db.create(table: "ActivityTypeModel") { table in
                table.column("geoKey", .text).primaryKey()
                table.column("lastSaved", .datetime).notNull().indexed()
                table.column("version", .integer).notNull().indexed()
                table.column("lastUpdated", .datetime).indexed()

                table.column("name", .text).notNull().indexed()
                table.column("depth", .integer).notNull().indexed()
                table.column("isShared", .boolean).notNull().indexed()
                table.column("needsUpdate", .boolean).indexed()
                table.column("totalSamples", .integer).notNull()
                table.column("accuracyScore", .double)

                table.column("latitudeMax", .double).notNull().indexed()
                table.column("latitudeMin", .double).notNull().indexed()
                table.column("longitudeMax", .double).notNull().indexed()
                table.column("longitudeMin", .double).notNull().indexed()

                table.column("movingPct", .double)
                table.column("coreMotionTypeScores", .text)
                table.column("altitudeHistogram", .text)
                table.column("courseHistogram", .text)
                table.column("courseVarianceHistogram", .text)
                table.column("speedHistogram", .text)
                table.column("stepHzHistogram", .text)
                table.column("timeOfDayHistogram", .text)
                table.column("xyAccelerationHistogram", .text)
                table.column("zAccelerationHistogram", .text)
                table.column("horizontalAccuracyHistogram", .text)
                table.column("coordinatesMatrix", .text) // deprecated
                table.column("coordinatesMatrixBlob", .blob)
                table.column("previousSampleActivityTypeScores", .text)
            }
        }

        // MARK: CoreMLModel

        auxiliaryDbMigrator.registerMigration("CoreMLModel") { db in
            try db.create(table: "CoreMLModel") { table in
                table.column("geoKey", .text).primaryKey()
                table.column("lastSaved", .datetime).notNull().indexed()
                table.column("lastUpdated", .datetime).indexed()
                table.column("filename", .text).notNull()

                table.column("depth", .integer).notNull().indexed()
                table.column("needsUpdate", .boolean).indexed()
                table.column("totalSamples", .integer).notNull()
                table.column("accuracyScore", .double)

                table.column("latitudeMax", .double).notNull().indexed()
                table.column("latitudeMin", .double).notNull().indexed()
                table.column("longitudeMax", .double).notNull().indexed()
                table.column("longitudeMin", .double).notNull().indexed()
            }
        }

        // MARK: CoordinateTrust

        auxiliaryDbMigrator.registerMigration("7.0.6 trust factor") { db in
            try db.create(table: "CoordinateTrust") { table in
                table.column("latitude", .double).notNull()
                table.column("longitude", .double).notNull()
                table.primaryKey(["latitude", "longitude"])
                table.column("trustFactor", .double).notNull()
            }
        }

        // MARK: - Auxiliary database migrations
        
        auxiliaryDbMigrator.registerMigration("ActivityTypeModel FlatBuffers") { db in
            try? db.alter(table: "ActivityTypeModel") { table in
                table.add(column: "coordinatesMatrixBlob", .blob)
            }
        }

        auxiliaryDbMigrator.registerMigration("Faster model lookup") { db in
            try? db.create(index: "ActivityTypeModel_on_isShared_depth", on: "ActivityTypeModel",
                           columns: ["isShared", "depth"])
        }
    }

    // MARK: - Delayed migrations

    func registerDelayedMigrations(to migrator: inout DatabaseMigrator) {

        // for HealthKit Workout Route imports
        migrator.registerMigration("LocomotionSample.disabled") { db in
            try? db.alter(table: "LocomotionSample") { table in
                table.add(column: "disabled", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("TimelineItem.disabled") { db in
            try? db.alter(table: "TimelineItem") { table in
                table.add(column: "disabled", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("LocomotionSample_on_source_lastSaved_confirmedType") { db in
            try? db.create(index: "LocomotionSample_on_source_lastSaved_confirmedType", on: "LocomotionSample",
                           columns: ["source", "lastSaved", "confirmedType"])
        }

        migrator.registerMigration("LocomotionSample RTree indexing") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS SampleRTree")
            try db.execute(sql: "CREATE VIRTUAL TABLE SampleRTree USING rtree(id, latMin, latMax, lonMin, lonMax)")
            try? db.alter(table: "LocomotionSample") { table in
                table.add(column: "rtreeId", .integer) // see note above for why not to index this
            }
        }

        migrator.registerMigration("LocomotionSample composite indexes") { db in
            try? db.drop(index: "LocomotionSample_on_rtreeId")
            try? db.drop(index: "LocomotionSample_on_confirmedType_date")
            try? db.drop(index: "LocomotionSample_on_confirmedType_lastSaved")
            try? db.drop(index: "LocomotionSample_on_confirmedType_lastSaved_rtreeId")
            try? db.drop(index: "LocomotionSample_on_lastSaved_confirmedType_rtreeId")
            try? db.drop(index: "LocomotionSample_on_lastSaved_rtreeId_confirmedType_xyAcceleration_zAcceleration_stepHz")

            try? db.create(
                index: "LocomotionSample_on_rtreeId_lastSaved_confirmedType", on: "LocomotionSample",
                columns: ["rtreeId", "lastSaved", "confirmedType"]
            )
            try? db.create(
                index: "LocomotionSample_on_lastSaved_confirmedType", on: "LocomotionSample",
                columns: ["lastSaved", "confirmedType"]
            )
        }
    }

}
