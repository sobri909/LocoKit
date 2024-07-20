//
//  Jobs.swift
//  LocoKit
//
//  Created by Matt Greenfield on 5/11/18.
//

import UIKit
import Combine
import Foundation

public class Jobs: ObservableObject {

    // MARK: - PUBLIC

    public static let highlander = Jobs()

    // MARK: - Settings

    public static var debugLogging = false

    // MARK: - Queues

    private(set) public lazy var primaryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LocoKit.primaryQueue"
        queue.qualityOfService = LocomotionManager.highlander.applicationState == .active ? .userInitiated : .background
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // will be converted to serial while in the background
    private(set) public lazy var secondaryQueue: OperationQueue = {
        let loco = LocomotionManager.highlander
        let queue = OperationQueue()
        queue.name = "LocoKit.secondaryQueue"
        queue.qualityOfService = loco.applicationState == .active ? .userInitiated : .background
        queue.maxConcurrentOperationCount = loco.applicationState == .active ? 4 : 1
        return queue
    }()

    // will be suspended while primaryQueue is busy
    public lazy var managedQueues: [OperationQueue] = {
        return [self.secondaryQueue]
    }()

    // MARK: - Adding Operations

    public static func addPrimaryJob(_ name: String, block: @escaping () -> Void) {
        let job = BlockOperation() {
            highlander.runJob(name, work: block)
        }
        job.name = name
        job.qualityOfService = LocomotionManager.highlander.applicationState == .active ? .userInitiated : .background
        highlander.primaryQueue.addOperation(job)

        // suspend the secondary queues while primary queue is non empty
        highlander.pauseManagedQueues()
    }

    public static func addSecondaryJob(_ name: String, dontDupe: Bool = false, block: @escaping () -> Void) {
        if dontDupe {
            for operation in highlander.secondaryQueue.operations {
                if operation.name == name {
                    if Jobs.debugLogging { logger.debug("Not adding duplicate job: \(name)") }
                    return
                }
            }
        }

        let job = BlockOperation() {
            highlander.runJob(name, work: block)
        }
        job.name = name
        job.qualityOfService = LocomotionManager.highlander.applicationState == .active ? .utility : .background
        highlander.secondaryQueue.addOperation(job)
    }

    // MARK: - PRIVATE

    private var observers: [Any] = []

    private init() {

        // if primary queue complete, open up the secondary queue again
        observers.append(primaryQueue.observe(\.operationCount) { _, _ in
            if self.primaryQueue.operationCount == 0, self.resumeWorkItem == nil {
                self.resumeManagedQueues()
            }
            onMain { self.objectWillChange.send() }
        })
        
        observers.append(secondaryQueue.observe(\.operationCount) { _, _ in
            onMain { self.objectWillChange.send() }
        })

        // debug observers
        if Jobs.debugLogging {
            observers.append(primaryQueue.observe(\.operationCount) { _, _ in
                self.logSerialQueueState()
            })
            observers.append(primaryQueue.observe(\.isSuspended) { _, _ in
                self.logSerialQueueState()
            })
            observers.append(secondaryQueue.observe(\.operationCount) { _, _ in
                self.logParallelQueueState()
            })
            observers.append(secondaryQueue.observe(\.isSuspended) { _, _ in
                self.logParallelQueueState()
            })
        }

        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] note in
            self?.didBecomeActive()
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] note in
            self?.didEnterBackground()
        }
    }

    private func logSerialQueueState() {
        logger.debug("  primaryQueue.count: \(self.primaryQueue.operationCount, align: .right(columns: 2)), suspended: \(String(describing: self.primaryQueue.isSuspended))")
    }

    private func logParallelQueueState() {
        logger.debug("secondaryQueue.count: \(self.secondaryQueue.operationCount, align: .right(columns: 2)), suspended: \(String(describing: self.secondaryQueue.isSuspended))")
    }

    // MARK: - Running Operations

    private func runJob(_ name: String, work: () -> Void) {
        let start = Date()
        if Jobs.debugLogging { logger.debug("STARTING JOB: \(name)") }

        // do the job
        work()

        if Jobs.debugLogging {
            logger.debug("FINISHED JOB: \(name) (duration: \(start.age, format: .fixed(precision: 3), align: .right(columns: 6)) seconds)")
        }

        // always pause managed queues between background jobs
        if LocomotionManager.highlander.applicationState == .background { pauseManagedQueues(for: 60) }
    }

    // MARK: - Queue State Management

    private func didEnterBackground() {
        let queues = managedQueues + [primaryQueue]

        // secondary queue goes serial in background
        secondaryQueue.maxConcurrentOperationCount = 1

        // demote queues and operations to .background priority
        for queue in queues {
            if queue != primaryQueue { queue.qualityOfService = .background }
            for operation in queue.operations where operation.qualityOfService != .background {
                if Jobs.debugLogging { logger.debug("DEMOTING: \(queue.name ?? "Unnamed"):\(operation.name ?? "Unnamed")") }
                operation.qualityOfService = .background
            }
        }
    }

    private func didBecomeActive() {
        let queues = [primaryQueue] + managedQueues

        // secondary queue goes mildly parallel in foreground
        secondaryQueue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount

        // promote queues and operations to .utility priority
        for queue in queues {
            queue.qualityOfService = .userInitiated
            for operation in queue.operations where operation.qualityOfService == .background {
                if Jobs.debugLogging { logger.debug("PROMOTING: \(queue.name ?? "Unnamed"):\(operation.name ?? "Unnamed")") }
                operation.qualityOfService = .userInitiated
            }
        }

        resumeManagedQueues()
    }

    private var resumeWorkItem: DispatchWorkItem?

    private func pauseManagedQueues(for duration: TimeInterval? = nil) {

        // don't pause again if already paused and waiting for resume
        guard resumeWorkItem == nil else { return }

        // pause all the secondary queues
        for queue in managedQueues where !queue.isSuspended {
            if Jobs.debugLogging { logger.debug("PAUSING QUEUE: \(queue.name ?? "Unnamed") (duration: \(duration ?? -1))") }
            queue.isSuspended = true
        }

        // queue up a task for resuming the queues
        if let duration = duration {
            let workItem = DispatchWorkItem {
                self.resumeManagedQueues()
            }
            resumeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }

    private func resumeManagedQueues() {
        resumeWorkItem?.cancel()
        resumeWorkItem = nil

        // not allowed to resume when primary queue is still busy
        guard primaryQueue.operationCount == 0 else { return }

        for queue in managedQueues {
            if queue.isSuspended {
                if Jobs.debugLogging { logger.debug("RESUMING: \(queue.name ?? "Unnamed")") }
                queue.isSuspended = false
            }
        }
    }
    
    // MARK: - ObservableObject

    public let objectWillChange = ObservableObjectPublisher()

}

// MARK: -

func delay(_ delay: Double, closure: @escaping () -> ()) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: closure)
}

func delay(_ delay: TimeInterval, onQueue queue: DispatchQueue, closure: @escaping () -> ()) {
    queue.asyncAfter(deadline: .now() + delay, execute: closure)
}
