//
//  ItemsObserver.swift
//  LocoKit
//
//  Created by Matt Greenfield on 11/9/18.
//

import os.log
import GRDB

class ItemsObserver: TransactionObserver {

    var store: TimelineStore
    var changedRowIds: Set<Int64> = []

    init(store: TimelineStore) {
        self.store = store
    }

    // observe updates to next/prev item links
    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        switch eventKind {
        case .update(let tableName, let columnNames):
            guard tableName == "TimelineItem" else { return false }
            let itemEdges: Set<String> = ["previousItemId", "nextItemId"]
            return itemEdges.intersection(columnNames).count > 0
        default: return false
        }
    }

    func databaseDidChange(with event: DatabaseEvent) {
        changedRowIds.insert(event.rowID)
    }

    func databaseDidCommit(_ db: Database) {
        let rowIds: Set<Int64> = store.mutex.sync {
            let rowIds = changedRowIds
            changedRowIds = []
            return rowIds
        }

        if rowIds.isEmpty { return }

        /** maintain the timeline items linked list locally, for changes made outside the managed environment **/

        do {
            let marks = repeatElement("?", count: rowIds.count).joined(separator: ",")
            let query = "SELECT itemId, previousItemId, nextItemId FROM TimelineItem WHERE rowId IN (\(marks))"
            let rows = try Row.fetchCursor(db, sql: query, arguments: StatementArguments(rowIds))

            while let row = try rows.next() {
                let previousItemIdString = row["previousItemId"] as String?
                let nextItemIdString = row["nextItemId"] as String?

                guard let uuidString = row["itemId"] as String?, let itemId = UUID(uuidString: uuidString) else { continue }
                guard let item = store.object(for: itemId) as? TimelineItem else { continue }

                if let uuidString = previousItemIdString, item.previousItemId?.uuidString != uuidString {
                    item.previousItemId = UUID(uuidString: uuidString)

                } else if previousItemIdString == nil && item.previousItemId != nil {
                    item.previousItemId = nil
                }

                if let uuidString = nextItemIdString, item.nextItemId?.uuidString != uuidString {
                    item.nextItemId = UUID(uuidString: uuidString)

                } else if nextItemIdString == nil && item.nextItemId != nil {
                    item.nextItemId = nil
                }
            }

        } catch {
            os_log("SQL Exception: %@", error.localizedDescription)
        }
    }

    func databaseDidRollback(_ db: Database) {}
}
