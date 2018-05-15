//
//  TimelineSegment.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/04/18.
//

import os.log
import GRDB

public class TimelineSegment: TransactionObserver {

    public let store: PersistentTimelineStore
    public var onUpdate: (() -> Void)?

    public private(set) var timelineItems: [TimelineItem]?

    private let query: String
    private let arguments: StatementArguments?
    private let queue = DispatchQueue(label: "TimelineSegment")
    private var updateTimer: Timer?
    private var lastSaveDate: Date?
    private var lastItemCount: Int?
    private var pendingChanges = false

    public convenience init(for dateRange: DateInterval, in store: PersistentTimelineStore,
                            onUpdate: (() -> Void)? = nil) {
        self.init(for: "deleted = 0 AND endDate > ? AND startDate < ? ORDER BY startDate",
                  arguments: [dateRange.start, dateRange.end], in: store)
    }

    public init(for query: String, arguments: StatementArguments? = nil, in store: PersistentTimelineStore,
                onUpdate: (() -> Void)? = nil) {
        self.store = store
        self.query = "SELECT * FROM TimelineItem WHERE " + query
        self.arguments = arguments
        self.onUpdate = onUpdate
        store.pool.add(transactionObserver: self)
    }

    // MARK: - Result updating

    private func needsUpdate() {
        onMain {
            self.updateTimer?.invalidate()
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                self?.update()
            }
        }
    }

    private func update() {
        // TODO: this should change test the updated items versus the previous, to avoid wasteful calls to onUpdate()
        // (test against oldLastSaved == newLastSaved && oldCount == newCount)
        queue.async { [weak self] in
            self?.updateItems()
            if self?.hasChanged == true {
                self?.reclassifySamples()
                self?.process()
                self?.onUpdate?()
            }
        }
    }

    private func updateItems() {
        timelineItems = store.items(for: query, arguments: arguments)
    }

    private var hasChanged: Bool {
        guard let items = timelineItems as? [PersistentItem] else { return false }

        let freshLastSaveDate = items.compactMap { $0.lastSaved }.max()
        let freshItemCount = timelineItems?.count

        defer {
            lastSaveDate = freshLastSaveDate
            lastItemCount = freshItemCount
        }

        if freshItemCount != lastItemCount { return true }
        if freshLastSaveDate != lastSaveDate { return true }
        return false
    }

    private func reclassifySamples() {
        guard let items = timelineItems else { return }
        guard let classifier = store.recorder?.classifier, classifier.canClassify else { return }

        for item in items {
            var count = 0
            for sample in item.samples where sample.confirmedType == nil {
                if let moreComing = sample.classifierResults?.moreComing, moreComing == false { continue }
                sample.classifierResults = classifier.classify(sample, filtered: true)
                sample.unfilteredClassifierResults = classifier.classify(sample, filtered: false)
                count += 1
            }
            if count > 0 {
                os_log("Reclassified samples: %d", type: .debug, count)
            }
        }
    }

    private func process() {
        if let items = timelineItems {
            TimelineProcessor.process(items)
        }
    }

    // MARK: - TransactionObserver

    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        return eventKind.tableName == "TimelineItem"
    }

    public func databaseDidChange(with event: DatabaseEvent) {
        pendingChanges = true

        // it is pointless to keep on tracking further changes
        stopObservingDatabaseChangesUntilNextTransaction()
    }

    public func databaseDidCommit(_ db: Database) {
        guard pendingChanges else { return }
        onMain { [weak self] in
            self?.needsUpdate()
        }
    }

    public func databaseDidRollback(_ db: Database) {
        pendingChanges = false
    }

}
