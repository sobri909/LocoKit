//
//  TimelineSegment.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/04/18.
//

import os.log
import GRDB

public class TimelineSegment: TransactionObserver, Encodable, Equatable {

    public static var reclassifySamples = true

    // MARK: -

    public var debugLogging = false
    public var shouldReprocessOnUpdate = true
    public var shouldUpdateMarkovValues = true

    // MARK: -

    public let store: TimelineStore
    public var onUpdate: (() -> Void)?

    // MARK: -

    private var _timelineItems: [TimelineItem]?
    public var timelineItems: [TimelineItem] {
        if pendingChanges || _timelineItems == nil {
            _timelineItems = store.items(for: query, arguments: arguments)
            pendingChanges = false
        }
        return _timelineItems ?? []
    }

    private let query: String
    private let arguments: StatementArguments?
    public var dateRange: DateInterval?

    // MARK: -

    private var updateTimer: Timer?
    private var lastSaveDate: Date?
    private var lastItemCount: Int?
    private var pendingChanges = false
    private var updatingEnabled = true

    // MARK: -

    public convenience init(for dateRange: DateInterval, in store: TimelineStore, onUpdate: (() -> Void)? = nil) {
        self.init(for: "endDate > :startDate AND startDate < :endDate AND deleted = 0 ORDER BY startDate",
                  arguments: ["startDate": dateRange.start, "endDate": dateRange.end], in: store)
        self.dateRange = dateRange
    }

    public init(for query: String, arguments: StatementArguments? = nil, in store: TimelineStore,
                onUpdate: (() -> Void)? = nil) {
        self.store = store
        self.query = "SELECT * FROM TimelineItem WHERE " + query
        self.arguments = arguments
        self.onUpdate = onUpdate
        store.pool.add(transactionObserver: self)
    }

    public func startUpdating() {
        if updatingEnabled { return }
        updatingEnabled = true
        needsUpdate()
    }

    public func stopUpdating() {
        if !updatingEnabled { return }
        updatingEnabled = false
        _timelineItems = nil
    }

    // MARK: - Result updating

    private func needsUpdate() {
        onMain {
            guard self.updatingEnabled else { return }
            self.updateTimer?.invalidate()
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.update()
            }
        }
    }

    private func update() {
        guard updatingEnabled else { return }
        Jobs.addSecondaryJob("TimelineSegment.\(ObjectIdentifier(self).hashValue).update", dontDupe: true) {
            guard self.updatingEnabled else { return }
            guard self.hasChanged else { return }

            if self.shouldReprocessOnUpdate {
                self.timelineItems.forEach { TimelineProcessor.healEdges(of: $0) }
            }
            
            self.reclassifySamples()
            self.updateMarkovValues()

            if self.shouldReprocessOnUpdate {
                self.process()
            }

            self.onUpdate?()
        }
    }

    private var hasChanged: Bool {
        let items = timelineItems 

        let freshLastSaveDate = items.compactMap { $0.lastSaved }.max()
        let freshItemCount = items.count

        defer {
            lastSaveDate = freshLastSaveDate
            lastItemCount = freshItemCount
        }

        if freshItemCount != lastItemCount { return true }
        if freshLastSaveDate != lastSaveDate { return true }
        return false
    }

    // Note: this expects samples to be in date ascending order
    private func reclassifySamples() {
        guard TimelineSegment.reclassifySamples else { return }
        
        guard let classifier = store.recorder?.classifier else { return }

        var lastResults: ClassifierResults?

        for item in timelineItems {
            var count = 0
            var typeChanged = false

            for sample in item.samples where sample.confirmedType == nil {

                // existing classifier results are already complete?
                if let moreComing = sample.classifierResults?.moreComing, moreComing == false { continue }

                // reclassify
                let oldActivityType = sample.activityType
                sample.classifierResults = classifier.classify(sample, previousResults: lastResults)
                if sample.classifierResults != nil { count += 1 }

                // activity type changed?
                if sample.activityType != oldActivityType { typeChanged = true }

                lastResults = sample.classifierResults
            }

            // item needs rebuild?
            if typeChanged { item.samplesChanged() }

            if debugLogging && count > 0 {
                if typeChanged {
                    os_log("Reclassified samples: %d (typeChanged: true)", type: .debug, count)
                } else {
                    os_log("Reclassified samples: %d", type: .debug, count)
                }
            }
        }
    }

    public func updateMarkovValues() {
        guard shouldUpdateMarkovValues else { return }

        for item in timelineItems {
            for sample in item.samples where sample.confirmedType != nil {
                sample.nextSample?.previousSampleConfirmedType = sample.confirmedType
            }
        }
    }

    private func process() {

        // shouldn't do processing if currentItem is in the segment and isn't a keeper
        // (the TimelineRecorder should be the sole authority on processing those cases)
        for item in timelineItems { if item.isCurrentItem && !item.isWorthKeeping { return } }

        TimelineProcessor.process(timelineItems)
    }

    // MARK: - TransactionObserver

    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        guard updatingEnabled else { return false }
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

    // MARK: - Export helpers

    public var filename: String? {
        guard let firstRange = timelineItems.first?.dateRange else { return nil }
        guard let lastRange = timelineItems.last?.dateRange else { return nil }

        let formatter = DateFormatter()

        // single item?
        if timelineItems.count == 1 {
            formatter.dateFormat = "yyyy-MM-dd HHmm"
            return formatter.string(from: firstRange.start)

        }

        // single day?
        if firstRange.start.isSameDayAs(lastRange.end) || firstRange.end.isSameDayAs(lastRange.start) {
            formatter.dateFormat = "yyyy-MM-dd"

        } else { // multiple days
            formatter.dateFormat = "yyyy-MM"
        }

        return formatter.string(from: lastRange.start)
    }

    // MARK: - Encodable

    enum CodingKeys: String, CodingKey {
        case timelineItems
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timelineItems, forKey: .timelineItems)
    }

    // MARK: - Equatable

    public static func == (lhs: TimelineSegment, rhs: TimelineSegment) -> Bool {
        return lhs.query == rhs.query && lhs.arguments == rhs.arguments
    }

}
