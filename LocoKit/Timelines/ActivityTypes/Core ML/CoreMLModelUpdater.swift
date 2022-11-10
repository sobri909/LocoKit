//
//  CoreMLModelUpdater.swift
//  
//
//  Created by Matt Greenfield on 5/11/22.
//

import Foundation
import BackgroundTasks

public class CoreMLModelUpdater {

    public static var highlander = CoreMLModelUpdater()

    var backgroundTaskExpired = false

    public func queueUpdatesForModelsContaining(_ timelineItem: TimelineItem) {
        let cache = ActivityTypesCache.highlander

        var lastModel: CoreMLModelWrapper?
        var models: Set<CoreMLModelWrapper> = []

        for sample in timelineItem.samples where sample.confirmedType != nil {
            guard sample.hasUsableCoordinate, let coordinate = sample.location?.coordinate else { continue }

            if let lastModel, lastModel.contains(coordinate: coordinate) {
                continue
            }

            if let model = cache.coreMLModelFor(coordinate: coordinate, depth: 2) {
                models.insert(model)
                lastModel = model
            }
        }

        for model in models {
            model.needsUpdate = true
            model.save()
        }
    }

    public func queueUpdatesForModelsContaining(_ segment: ItemSegment) {
        let cache = ActivityTypesCache.highlander

        var lastModel: CoreMLModelWrapper?
        var models: Set<CoreMLModelWrapper> = []

        for sample in segment.samples where sample.confirmedType != nil {
            guard sample.hasUsableCoordinate, let coordinate = sample.location?.coordinate else { continue }

            if let lastModel, lastModel.contains(coordinate: coordinate) {
                continue
            }

            if let model = cache.coreMLModelFor(coordinate: coordinate, depth: 2) {
                models.insert(model)
                lastModel = model
            }
        }

        for model in models {
            model.needsUpdate = true
            model.save()
        }
    }

    private var onUpdatesComplete: ((Bool) -> Void)?

    @available(iOS 15, *)
    public func updateQueuedModels(task: BGProcessingTask, store: TimelineStore, onComplete: ((Bool) -> Void)? = nil) {
        if let onComplete {
            onUpdatesComplete = onComplete
        }

        // not allowed to continue?
        if backgroundTaskExpired {
            onUpdatesComplete?(true)
            return
        }

        // catch background expiration
        if task.expirationHandler == nil {
            backgroundTaskExpired = false
            task.expirationHandler = {
                self.backgroundTaskExpired = true
                task.setTaskCompleted(success: false)
            }
        }

        // do the job
        store.connectToDatabase()
        if let model = store.coreMLModel(where: "needsUpdate = 1") {
            model.updatedModel(task: task, in: store)
            return
        }

        // job's finished
        onUpdatesComplete?(false)
        task.setTaskCompleted(success: true)
    }

    // MARK: -

    public lazy var updatesQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LocoKit.CoreMLModelUpdater.updatesQueue"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .background
        return queue
    }()

}
