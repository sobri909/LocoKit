//
//  TimelineSegment.swift
//  LocoKit
//
//  Created by Matt Greenfield on 29/04/18.
//

import os.log
import GRDB

public extension NSNotification.Name {
    static let timelineSegmentUpdated = Notification.Name("timelineSegmentUpdated")
}

public class TimelineSegment: TransactionObserver, Encodable, Hashable {

    // MARK: -

    public var debugLogging = false
    public var shouldReprocessOnUpdate = false
    public var shouldUpdateMarkovValues = true
    public var shouldReclassifySamples = true

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
    private let arguments: StatementArguments
    public var dateRange: DateInterval?

    // MARK: -

    private var updateTimer: Timer?
    private var lastSaveDate: Date?
    private var lastItemCount: Int?
    private var pendingChanges = false
    private var updatingEnabled = true

    // MARK: -

    public init(where query: String, arguments: StatementArguments? = nil, in store: TimelineStore,
                onUpdate: (() -> Void)? = nil) {
        self.store = store
        self.query = "SELECT * FROM TimelineItem WHERE " + query
        self.arguments = arguments ?? StatementArguments()
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
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                self?.update()
            }
        }
    }

    private func update() {
        guard updatingEnabled else { return }
        Jobs.addSecondaryJob("TimelineSegment.\(self.hashValue).update", dontDupe: true) {
            guard self.updatingEnabled else { return }
            guard self.hasChanged else { return }

            if self.shouldReprocessOnUpdate {
                self.timelineItems.forEach { TimelineProcessor.healEdges(of: $0) }
            }
            
            self.reclassifySamples()

            if self.shouldReprocessOnUpdate {
                self.updateMarkovValues()
                self.process()
            }

            self.onUpdate?()

            NotificationCenter.default.post(Notification(name: .timelineSegmentUpdated, object: self))
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
        guard shouldReclassifySamples else { return }
        
        guard let classifier = store.recorder?.classifier else { return }

        var lastResults: ClassifierResults?

        for item in timelineItems {
            var count = 0

            for sample in item.samples where sample.confirmedType == nil {

                // don't reclassify samples if they've been done within the past few months
                if sample._classifiedType != nil, let lastSaved = sample.lastSaved, lastSaved.age < .oneMonth * 3 { continue }

                let oldClassifiedType = sample._classifiedType
                sample._classifiedType = nil
                sample.classifierResults = classifier.classify(sample, previousResults: lastResults)
                if sample.classifiedType != oldClassifiedType {
                    count += 1
                }

                lastResults = sample.classifierResults
            }

            // item needs rebuild?
            if count > 0 { item.sampleTypesChanged() }

            if debugLogging && count > 0 {
                os_log("Reclassified samples: %d", type: .debug, count)
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
        if dateRange == nil, timelineItems.count == 1 {
            return singleItemFilename
        }

        guard let dateRange = dateRange else { return nil }

        if (dateRange.start + 1).isSameDayAs(dateRange.end - 1) {
            return dayFilename
        }

        if (dateRange.start + 1).isSameMonthAs(dateRange.end - 1) {
            return monthFilename
        }

        return yearFilename
    }

    public var singleItemFilename: String? {
        guard let firstRange = timelineItems.first?.dateRange else { return nil }
        guard timelineItems.count == 1 else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter.string(from: firstRange.start)
    }

    public var dayFilename: String? {
        guard let dateRange = dateRange else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: dateRange.middle)
    }

    public var monthFilename: String? {
        guard let dateRange = dateRange else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: dateRange.middle)
    }

    public var yearFilename: String? {
        guard let dateRange = dateRange else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: dateRange.middle)
    }

    // MARK: - Encodable

    enum CodingKeys: String, CodingKey {
        case timelineItems
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timelineItems, forKey: .timelineItems)
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(query)
        hasher.combine(arguments.description)
    }

    // MARK: - Equatable

    public static func == (lhs: TimelineSegment, rhs: TimelineSegment) -> Bool {
        return lhs.query == rhs.query && lhs.arguments == rhs.arguments
    }

}
