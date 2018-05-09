//
//  TimelineSegment.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/04/18.
//

import os.log
import GRDB

public class TimelineSegment {

    public let store: PersistentTimelineStore
    public var onUpdate: (() -> Void)?

    private var _timelineItems: [TimelineItem]?
    public var timelineItems: [TimelineItem] {
        if let existing = _timelineItems { return existing }
        _timelineItems = updatedItems
        return _timelineItems!
    }

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

            self.observer.trackChanges { [weak self] observer in
                self?.needsUpdate()
            }
            self.observer.trackErrors { observer, error in
                os_log("FetchedRecordsController error: %@", type: .error, error.localizedDescription)
            }

            queue.async {
                do {
                    try self.observer.performFetch()
                    self.onUpdate?()

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
        _timelineItems = nil
        onMain {
            self.updateTimer?.invalidate()
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { [weak self] _ in
                self?.onUpdate?()
            }
        }
    }

    private var updatedItems: [TimelineItem] {
        return observer.fetchedRecords.map { store.item(for: $0.row) }
    }

}
