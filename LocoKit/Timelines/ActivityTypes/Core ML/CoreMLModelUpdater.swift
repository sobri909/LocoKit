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

    public var store: TimelineStore?

    var backgroundTaskExpired = false

    public func queueUpdatesForModelsContaining(_ timelineItem: TimelineItem) {
        guard let store else {
            logger.error("Called queueUpdatesForModelsContaining() on a CoreMLModelUpdater with nil store")
            return
        }

        var lastModel: CoreMLModelWrapper?
        var models: Set<CoreMLModelWrapper> = []

        for sample in timelineItem.samples where sample.confirmedType != nil {
            guard sample.hasUsableCoordinate, let coordinate = sample.location?.coordinate else { continue }

            if let lastModel, lastModel.contains(coordinate: coordinate) {
                continue
            }

            if let model = store.coreMLModelFor(coordinate: coordinate, depth: 2) {
                models.insert(model)
                lastModel = model
            }
            
            if let model = store.coreMLModelFor(coordinate: coordinate, depth: 1) {
                models.insert(model)
            }
            
            if let model = store.coreMLModelFor(coordinate: coordinate, depth: 0) {
                models.insert(model)
            }
        }

        for model in models {
            model.needsUpdate = true
            model.save()
        }
    }

    public func queueUpdatesForModelsContaining(_ segment: ItemSegment) {
        guard let store else {
            logger.error("Called queueUpdatesForModelsContaining() on a CoreMLModelUpdater with nil store")
            return
        }

        var lastModel: CoreMLModelWrapper?
        var models: Set<CoreMLModelWrapper> = []

        for sample in segment.samples where sample.confirmedType != nil {
            guard sample.hasUsableCoordinate, let coordinate = sample.location?.coordinate else { continue }

            if let lastModel, lastModel.contains(coordinate: coordinate) {
                continue
            }

            if let model = store.coreMLModelFor(coordinate: coordinate, depth: 2) {
                models.insert(model)
                lastModel = model
            }
            
            if let model = store.coreMLModelFor(coordinate: coordinate, depth: 1) {
                models.insert(model)
            }
            
            if let model = store.coreMLModelFor(coordinate: coordinate, depth: 0) {
                models.insert(model)
            }
        }

        for model in models {
            model.needsUpdate = true
            model.save()
        }
    }

    private var onUpdatesComplete: ((Bool) -> Void)?

    public func updateQueuedModels(task: BGProcessingTask, currentClassifier classifier: ActivityClassifier?, onComplete: ((Bool) -> Void)? = nil) {
        guard let store else {
            logger.error("Called updateQueuedModels() on a CoreMLModelUpdater with nil store")
            return
        }

        if let onComplete {
            onUpdatesComplete = onComplete
        }

        // not allowed to continue?
        if backgroundTaskExpired {
            backgroundTaskExpired = false
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

        store.connectToDatabase()

        // do the current CD2 first, if it needs it
        let currentModel = classifier?.discreteClassifiers.first { $0.value.geoKey.hasPrefix("CD2") }?.value
        if let model = currentModel as? CoreMLModelWrapper, model.needsUpdate {
            model.updateTheModel(task: task, currentClassifier: classifier)
            return
        }

        // CD0 update intervals
        let cd0UpdateInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        let cd0FrequentUpdateInterval: TimeInterval = 24 * 60 * 60 // 1 day

        // check for any queued model, prioritising by depth and completeness
        if let model = store.coreMLModel(
            where: """
                needsUpdate = 1 AND 
                (depth > 0 OR 
                 (depth = 0 AND 
                  (lastUpdated IS NULL OR 
                   (totalSamples < ? AND lastUpdated < datetime('now', '-\(Int(cd0FrequentUpdateInterval)) seconds')) OR
                   (totalSamples >= ? AND lastUpdated < datetime('now', '-\(Int(cd0UpdateInterval)) seconds'))
                  )
                 )
                )
                ORDER BY depth DESC, totalSamples ASC
                """,
            arguments: [CoreMLModelWrapper.modelMinTrainingSamples[0]!, CoreMLModelWrapper.modelMinTrainingSamples[0]!]
        ) {
            // backfill r-tree for old dbs or restores from backup
            Task.detached {
                await store.backfillSampleRTree(batchSize: CoreMLModelWrapper.modelMaxTrainingSamples[0]!)
            }

            model.updateTheModel(task: task, currentClassifier: classifier)
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
