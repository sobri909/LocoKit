//
//  PersistentTimelineManager.swift
//  ArcKit
//
//  Created by Matt Greenfield on 9/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

import GRDB

/**
 Add some description here. 
 */
open class PersistentTimelineManager: TimelineManager {

    private lazy var _store = PersistentTimelineStore()
    open override var store: PersistentTimelineStore { return _store }

    // MARK: Startup

    public func bootstrapActiveItems() {
        guard currentItem == nil else { return }

        var activeItems: [TimelineItem] = []

        // get current item
        let query = "SELECT * FROM TimelineItem WHERE deleted = 0 ORDER BY endDate DESC LIMIT 1"
        guard let item = store.item(for: query) else { return }
        activeItems.append(item)

        // work backwards to get the rest of the active items
        var workingItem = item, keeperCount = 0
        while keeperCount < 2 {
            if workingItem.isWorthKeeping { keeperCount += 1 }

            guard let previousItem = workingItem.previousItem, !previousItem.deleted else { break }

            activeItems.append(previousItem)
            workingItem = previousItem
        }

        // add them in chronological order
        for item in activeItems.reversed() { add(item) }
    }

}
