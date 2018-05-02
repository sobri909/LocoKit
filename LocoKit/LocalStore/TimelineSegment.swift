//
//  TimelineSegment.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/04/18.
//

import GRDB

public class TimelineSegment {

    public let store: PersistentTimelineStore
    public private(set) var timelineItems: [TimelineItem]?
    public var onUpdate: (() -> Void)?

    private let query: String
    private let arguments: StatementArguments?
    private let queue = DispatchQueue(label: "TimelineSegment")
    private let observer: FetchedRecordsController<RowCopy>
    private var updateTimer: Timer?

    public convenience init(for dateRange: DateInterval, in store: PersistentTimelineStore,
                            onUpdate: (() -> Void)? = nil) {
        self.init(for: "deleted = 0 AND endDate > ? AND startDate < ? ORDER BY startDate",
                  arguments: [dateRange.start, dateRange.end], in: store)
    }

    public init(for query: String, arguments: StatementArguments? = nil, in store: PersistentTimelineStore,
                onUpdate: (() -> Void)? = nil) {
        self.store = store
        self.query = query
        self.arguments = arguments
        self.onUpdate = onUpdate

        do {
            let fullQuery = "SELECT * FROM TimelineItem WHERE " + query
            self.observer = try FetchedRecordsController<RowCopy>(store.pool, sql: fullQuery, arguments: arguments,
                                                                  queue: queue)

            observer.trackChanges { [weak self] observer in
                self?.needsUpdate()
            }

            queue.async {
                do {
                    try self.observer.performFetch()
                    self.update()
                } catch {
                    fatalError("OOPS: \(error)")
                }
            }

        } catch {
            fatalError("OOPS: \(error)")
        }
    }

    // MARK: - Result updating

    private func needsUpdate() {
        onMain {
            self.updateTimer?.invalidate()
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { [weak self] _ in
                self?.update()
            }
        }
    }

    private func update() {
        var items: [TimelineItem] = []
        for row in observer.fetchedRecords {
            items.append(store.item(for: row.row))
        }
        self.timelineItems = items
        onUpdate?()
    }

}
