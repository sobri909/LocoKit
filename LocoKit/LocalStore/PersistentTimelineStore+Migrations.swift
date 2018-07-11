//
//  PersistentTimelineStore+Migrations.swift
//  LocoKit
//
//  Created by Matt Greenfield on 4/6/18.
//

import GRDB

internal extension PersistentTimelineStore {

     internal func registerMigrations() {

        // initial tables creation
        migrator.registerMigration("CreateTables") { db in
            try db.create(table: "TimelineItem") { table in
                table.column("itemId", .text).primaryKey()

                table.column("lastSaved", .datetime).notNull().indexed()
                table.column("deleted", .boolean).notNull().indexed()
                table.column("isVisit", .boolean).notNull().indexed()
                table.column("startDate", .datetime).indexed()
                table.column("endDate", .datetime).indexed()

                table.column("previousItemId", .text).indexed().references("TimelineItem", deferred: true)
                    .check(sql: "previousItemId != itemId AND (previousItemId IS NULL OR deleted = 0)")
                table.column("nextItemId", .text).indexed().references("TimelineItem", deferred: true)
                    .check(sql: "nextItemId != itemId AND (nextItemId IS NULL OR deleted = 0)")

                table.column("radiusMean", .double)
                table.column("radiusSD", .double)
                table.column("altitude", .double)
                table.column("stepCount", .integer)
                table.column("floorsAscended", .integer)
                table.column("floorsDescended", .integer)
                table.column("activityType", .text)

                // item.center
                table.column("latitude", .double)
                table.column("longitude", .double)
            }
            try db.create(table: "LocomotionSample") { table in
                table.column("sampleId", .text).primaryKey()

                table.column("date", .datetime).notNull().indexed()
                table.column("lastSaved", .datetime).notNull()
                table.column("movingState", .text).notNull()
                table.column("recordingState", .text).notNull()

                table.column("timelineItemId", .text).references("TimelineItem", deferred: true).indexed()

                table.column("stepHz", .double)
                table.column("courseVariance", .double)
                table.column("xyAcceleration", .double)
                table.column("zAcceleration", .double)
                table.column("coreMotionActivityType", .text)
                table.column("confirmedType", .text)

                // sample.location
                table.column("latitude", .double).indexed()
                table.column("longitude", .double).indexed()
                table.column("altitude", .double)
                table.column("horizontalAccuracy", .double)
                table.column("verticalAccuracy", .double)
                table.column("speed", .double)
                table.column("course", .double)
            }

            // maintain the linked list from the nextItem side
            try db.execute("""
                CREATE TRIGGER TimelineItem_update_nextItemId
                    AFTER UPDATE OF nextItemId ON TimelineItem
                    BEGIN
                        UPDATE TimelineItem SET previousItemId = NULL WHERE itemId = OLD.nextItemId;
                        UPDATE TimelineItem SET previousItemId = NEW.itemId WHERE itemId = NEW.nextItemId;
                    END
                """)

            // maintain the linked list from the previousItem side
            try db.execute("""
                CREATE TRIGGER TimelineItem_update_previousItemId
                    AFTER UPDATE OF previousItemId ON TimelineItem
                    BEGIN
                        UPDATE TimelineItem SET nextItemId = NULL WHERE itemId = OLD.previousItemId;
                        UPDATE TimelineItem SET nextItemId = NEW.itemId WHERE itemId = NEW.previousItemId;
                    END
                """)
        }

        // add some missing indexes
        migrator.registerMigration("5.1.2") { db in
            try db.create(index: "LocomotionSample_on_confirmedType",
                          on: "LocomotionSample", columns: ["confirmedType"])
            try db.create(index: "LocomotionSample_on_lastSaved",
                          on: "LocomotionSample", columns: ["lastSaved"])
        }

        migrator.registerMigration("6.0.0") { db in

            /** table changes **/

            // ability to soft delete samples, same as items
            try db.alter(table: "LocomotionSample") { table in
                table.add(column: "deleted", .boolean).defaults(to: false).notNull().indexed()
            }

            // caching distance to db reduces costs on fetch
            try db.alter(table: "TimelineItem") { table in
                table.add(column: "distance", .double)
            }

            /** indexes **/

            // faster sample fetching for timeline items
            try db.create(index: "LocomotionSample_on_timelineItemId_deleted_date", on: "LocomotionSample",
                          columns: ["timelineItemId", "deleted", "date"])

            /** new and updated triggers **/

            // replacement insert triggers, with more precision
            try db.execute("DROP TRIGGER IF EXISTS TimelineItem_insert")
            try db.execute("""
                CREATE TRIGGER TimelineItem_INSERT_previousEdge
                    AFTER INSERT ON TimelineItem
                    WHEN NEW.previousItemId IS NOT NULL
                    BEGIN
                        UPDATE TimelineItem SET nextItemId = NEW.itemId WHERE itemId = NEW.previousItemId;
                    END
                """)
            try db.execute("""
                CREATE TRIGGER TimelineItem_INSERT_nextEdge
                    AFTER INSERT ON TimelineItem
                    WHEN NEW.nextItemId IS NOT NULL
                    BEGIN
                        UPDATE TimelineItem SET previousItemId = NEW.itemId WHERE itemId = NEW.nextItemId;
                    END
                """)

            // ensure the previous edge is detached when an item is soft deleted
            try db.execute("""
                CREATE TRIGGER TimelineItem_UPDATE_deleted_previousEdge
                    AFTER UPDATE OF deleted ON TimelineItem
                    WHEN NEW.deleted = 1 AND NEW.previousItemId IS NOT NULL
                    BEGIN
                        UPDATE TimelineItem SET nextItemId = NULL WHERE itemId = NEW.previousItemId;
                        UPDATE TimelineItem SET previousItemId = NULL WHERE itemId = NEW.itemId;
                    END
                """)

            // ensure the next edge is detached when an item is soft deleted
            try db.execute("""
                CREATE TRIGGER TimelineItem_UPDATE_deleted_nextEdge
                    AFTER UPDATE OF deleted ON TimelineItem
                    WHEN NEW.deleted = 1 AND NEW.nextItemId IS NOT NULL
                    BEGIN
                        UPDATE TimelineItem SET previousItemId = NULL WHERE itemId = NEW.nextItemId;
                        UPDATE TimelineItem SET nextItemId = NULL WHERE itemId = NEW.itemId;
                    END
                """)
        }

        // add source fields, so that imported data can be distinguished from recorded data
        migrator.registerMigration("6.0.0 source") { db in
            try db.alter(table: "TimelineItem") { table in
                table.add(column: "source", .text).defaults(to: "LocoKit").indexed()
            }
            try db.alter(table: "LocomotionSample") { table in
                table.add(column: "source", .text).defaults(to: "LocoKit").indexed()
            }
        }
    }

}
