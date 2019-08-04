//
//  TimelineStore+Migrations.swift
//  LocoKit
//
//  Created by Matt Greenfield on 4/6/18.
//

import GRDB

internal extension TimelineStore {

    func registerMigrations() {

        // initial tables creation
        migrator.registerMigration("CreateTables") { db in
            try db.create(table: "TimelineItem") { table in
                table.column("itemId", .text).primaryKey()

                table.column("lastSaved", .datetime).notNull().indexed()
                table.column("deleted", .boolean).notNull()
                table.column("isVisit", .boolean).notNull().indexed()
                table.column("startDate", .datetime).indexed()
                table.column("endDate", .datetime).indexed()
                table.column("source", .text).defaults(to: "LocoKit").indexed()

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

            try db.create(table: "LocomotionSample") { table in
                table.column("sampleId", .text).primaryKey()

                table.column("date", .datetime).notNull().indexed()
                table.column("deleted", .boolean).notNull().indexed()
                table.column("lastSaved", .datetime).notNull().indexed()
                table.column("source", .text).defaults(to: "LocoKit").indexed()

                table.column("movingState", .text).notNull()
                table.column("recordingState", .text).notNull()

                table.column("timelineItemId", .text).references("TimelineItem", onDelete: .setNull, deferred: true)

                table.column("stepHz", .double)
                table.column("courseVariance", .double)
                table.column("xyAcceleration", .double)
                table.column("zAcceleration", .double)
                table.column("coreMotionActivityType", .text)
                table.column("classifiedType", .text)
                table.column("confirmedType", .text)
                table.column("previousSampleConfirmedType", .text)

                // sample.location
                table.column("latitude", .double).indexed()
                table.column("longitude", .double).indexed()
                table.column("altitude", .double)
                table.column("horizontalAccuracy", .double)
                table.column("verticalAccuracy", .double)
                table.column("speed", .double)
                table.column("course", .double)
            }

            try db.create(index: "LocomotionSample_on_timelineItemId_deleted_date", on: "LocomotionSample",
                          columns: ["timelineItemId", "deleted", "date"])
            try db.create(index: "LocomotionSample_on_confirmedType_latitude_longitude_date", on: "LocomotionSample",
                          columns: ["confirmedType", "latitude", "longitude", "date"])
            try db.create(index: "LocomotionSample_on_confirmedType_lastSaved", on: "LocomotionSample",
                          columns: ["confirmedType", "lastSaved"])

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

        migrator.registerMigration("7.0.1 segments") { db in
            try db.create(index: "TimelineItem_on_deleted_startDate", on: "TimelineItem",
                          columns: ["deleted", "startDate"])
        }

        migrator.registerMigration("7.0.2") { db in
            try? db.alter(table: "LocomotionSample") { table in
                table.add(column: "previousSampleConfirmedType", .text)
            }
        }

        migrator.registerMigration("7.0.4 timezones") { db in
            try db.alter(table: "LocomotionSample") { table in
                table.add(column: "secondsFromGMT", .integer)
            }
        }

        migrator.registerMigration("7.0.5 cached activity types") { db in
            try? db.alter(table: "LocomotionSample") { table in
                table.add(column: "classifiedType", .text)
            }
        }
    }

    // MARK: - Auxiliary database

    func registerAuxiliaryDbMigrations() {
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
                table.column("coordinatesMatrix", .text)
                table.column("previousSampleActivityTypeScores", .text)
            }
        }

        auxiliaryDbMigrator.registerMigration("7.0.6 trust factor") { db in
            try db.create(table: "CoordinateTrust") { table in
                table.column("latitude", .double).notNull()
                table.column("longitude", .double).notNull()
                table.primaryKey(["latitude", "longitude"])
                table.column("trustFactor", .double).notNull()
            }
        }
    }

    // MARK: - Delayable migrations

    func registerDelayedMigrations() {
        migrator.registerMigration("7.0.6 recent confirmed samples") { db in
            try? db.create(index: "LocomotionSample_on_confirmedType_lastSaved", on: "LocomotionSample",
                           columns: ["confirmedType", "lastSaved"])
        }

        migrator.registerMigration("7.0.6 models have moved") { db in
            try? db.drop(table: "ActivityTypeModel")
            try? db.drop(table: "CoordinateTrust")
        }

        migrator.registerMigration("7.0.6 redundant indexes") { db in
            try? db.drop(index: "LocomotionSample_on_confirmedType")
            try? db.drop(index: "LocomotionSample_on_timelineItemId")
        }

        migrator.registerMigration("7.0.6 even better sample index") { db in
            try? db.drop(index: "LocomotionSample_on_confirmedType_latitude_longitude")
            try? db.create(index: "LocomotionSample_on_confirmedType_latitude_longitude_date", on: "LocomotionSample",
                           columns: ["confirmedType", "latitude", "longitude", "date"])
        }
    }

}
