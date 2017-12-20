//
//  TimelineManager.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import CoreLocation
import Reachability

/// Custom notification events that the TimelineManager may send.
public extension NSNotification.Name {
    public static let newTimelineItem = Notification.Name("newTimelineItem")
    public static let updatedTimelineItem = Notification.Name("updatedTimelineItem")
    public static let finalisedTimelineItem = Notification.Name("finalisedTimelineItem")
    public static let mergedTimelineItems = Notification.Name("mergedTimelineItems")
    public static let debugInfo = Notification.Name("debugInfo")
}

public final class DefaultTimelineManager: TimelineManager {

    public typealias ItemFactory = DefaultItemFactory

    public var lastRecorded: Date?

    private let reachability = Reachability()!

    public static var highlander = DefaultTimelineManager()

    public var recording: Bool {
        willSet(newValue) {
            if newValue {
                LocomotionManager.highlander.startRecording()
            } else {
                LocomotionManager.highlander.stopRecording()
            }
        }
    }

    // MARK: Settings

    /**
     The target number of samples to record per minute.

     - Note: The actual number of samples recorded per minute may be less than this, depending on data availability.
     */
    public var samplesPerMinute: Double = 10

    /**
     The duration of historical timeline items to retain in `finalisedTimelineItems`.

     Once a timeline item is older than this (measured from the item's `end` date) it will be removed from
     `finalisedTimelineItems`.
     */
    public var timelineItemHistoryRetention: TimeInterval = 60 * 60 * 6

    public var activityTypeClassifySamples = true

    public var minimumTransportCoverage = 0.10

    // MARK: The Recorded Timeline Items
    
    /**
     The current (most recent) timeline item.

     - Note: This value is equivalent to `activeTimelineItems.last`.
     */
    public var currentItem: TimelineItem? {
        return activeTimelineItems.last
    }

    /**
     The timeline items that are still being considered for modification by the processing engine, in ascending date
     order.

     Once each timeline item is finalised, it is moved to `finalisedTimelineItems`, at which point it will no longer
     be modified by the processing engine.
     */
    private(set) public var activeTimelineItems: [TimelineItem] = []

    /**
     The timeline items that have received their final processing and will no longer be modified, in ascending date
     order.

     - Note: The last item in this array will usually be linked to the first item in `activeTimelineItems` by its
     `nextItem` property. And in turn, that item will be linked back by its `previousItem` property.
     */
    private(set) public var finalisedTimelineItems: [TimelineItem] = []

    // MARK: The Classifiers

    private(set) public var baseClassifier: ActivityTypeClassifier<ActivityTypesCache>?
    private(set) public var transportClassifier: ActivityTypeClassifier<ActivityTypesCache>?

    public func add(_ timelineItem: TimelineItem) {
        activeTimelineItems.append(timelineItem)
    }

    public func remove(_ timelineItems: [TimelineItem]) {
        activeTimelineItems.removeObjects(timelineItems)
        finalisedTimelineItems.removeObjects(timelineItems)
    }

    public func finalise(_ timelineItems: [TimelineItem]) {
        if timelineItems.isEmpty {
            return
        }
        activeTimelineItems.removeObjects(Array(timelineItems))
        finalisedTimelineItems.append(contentsOf: timelineItems)
        for item in timelineItems {
            NotificationCenter.default.post(Notification(name: .finalisedTimelineItem, object: self,
                                                         userInfo: ["timelineItem": item]))
        }
    }

    // MARK: Internal Classifier Management

    public func classify(_ classifiable: ActivityTypeClassifiable) -> ClassifierResults? {

        // attempt to keep the classifiers relevant / fresh
        if let coordinate = classifiable.location?.coordinate {
            updateTheBaseClassifier(for: coordinate)
            updateTheTransportClassifier(for: coordinate)
        }

        // if possible, get the base type results
        guard let classifier = baseClassifier else {
            return nil
        }
        let results = classifier.classify(classifiable)

        // don't need to go further if transport didn't win the base round
        guard results.first?.name == .transport else {
            return results
        }

        // don't include specific transport types if classifier has less than required coverage
        guard let coverageScore = transportClassifier?.coverageScore, coverageScore > minimumTransportCoverage else {
            return results
        }

        // attempt to get the transport type results
        guard let transportClassifier = transportClassifier else {
            return results
        }
        let transportResults = transportClassifier.classify(classifiable)

        // combine and return the results
        return (results - ActivityTypeName.transport) + transportResults
    }

    private func updateTheBaseClassifier(for coordinate: CLLocationCoordinate2D) {

        // don't try to fetch classifiers without a network connection
        guard reachability.connection != .none else {
            return
        }

        // have a classifier already, and it's still valid?
        if let classifier = baseClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        // attempt to get an updated classifier
        if let replacement = ActivityTypeClassifier<ActivityTypesCache>(requestedTypes: ActivityTypeName.baseTypes,
                                                                        coordinate: coordinate) {
            baseClassifier = replacement
        }
    }

    private func updateTheTransportClassifier(for coordinate: CLLocationCoordinate2D) {

        // don't try to fetch classifiers without a network connection
        guard reachability.connection != .none else {
            return
        }

        // have a classifier already, and it's still valid?
        if let classifier = transportClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        // attempt to get an updated classifier
        if let replacement = ActivityTypeClassifier<ActivityTypesCache>(requestedTypes: ActivityTypeName.transportTypes,
                                                                        coordinate: coordinate) {
            transportClassifier = replacement
        }
    }

    private init() {
        self.recording = false

        NotificationCenter.default.addObserver(forName: .locomotionSampleUpdated, object: nil, queue: nil) { _ in
            self.sampleUpdated()
        }

        // want to be able to store a sample to mark the start of most recent sleep cycle
        NotificationCenter.default.addObserver(forName: .willStartSleepMode, object: nil, queue: nil) { _ in
            self.sampleUpdated()
        }
    }
}
