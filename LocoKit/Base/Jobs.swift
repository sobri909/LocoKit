//
//  Jobs.swift
//  LocoKit
//
//  Created by Matt Greenfield on 5/11/18.
//

import os.log

public class Jobs {

    // MARK: - PUBLIC

    public static let highlander = Jobs()

    // MARK: - Settings

    public static var debugLogging = false

    // MARK: - Queues

    private(set) public lazy var primaryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LocoKit.primaryQueue"
        queue.qualityOfService = applicationState == .active ? .userInitiated : .background
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // will be converted to serial while in the background
    private(set) public lazy var secondaryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LocoKit.secondaryQueue"
        queue.qualityOfService = applicationState == .active ? .utility : .background
        queue.maxConcurrentOperationCount = applicationState == .active ? OperationQueue.defaultMaxConcurrentOperationCount : 1
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
        job.qualityOfService = highlander.applicationState == .active ? .userInitiated : .background
        highlander.primaryQueue.addOperation(job)

        // suspend the secondary queues while primary queue is non empty
        highlander.pauseManagedQueues()
    }

    public static func addSecondaryJob(_ name: String, dontDupe: Bool = false, block: @escaping () -> Void) {
        if dontDupe {
            for operation in highlander.secondaryQueue.operations {
                if operation.name == name {
                    if Jobs.debugLogging { os_log("Not adding duplicate job: %@", type: .debug, name) }
                    return
                }
            }
        }

        let job = BlockOperation() {
            highlander.runJob(name, work: block)
        }
        job.name = name
        job.qualityOfService = highlander.applicationState == .active ? .utility : .background
        highlander.secondaryQueue.addOperation(job)
    }

    // MARK: - PRIVATE

    private var observers: [Any] = []
    private var applicationState: UIApplication.State

    private init() {
        self.applicationState = UIApplication.shared.applicationState

        // background / foreground observers
        let notes =  NotificationCenter.default
        notes.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            self.applicationState = .background
            self.didEnterBackground()
        }
        notes.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            self.applicationState = .active
            self.didBecomeActive()
        }

        // if primary queue complete, open up the secondary queue again
        observers.append(primaryQueue.observe(\.operationCount) { _, _ in
            if self.primaryQueue.operationCount == 0, self.resumeWorkItem == nil {
                self.resumeManagedQueues()
            }
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
    }

    private func logSerialQueueState() {
        os_log("  primaryQueue.count: %2d, suspended: %@", type: .debug, primaryQueue.operationCount,
               String(describing: primaryQueue.isSuspended))
    }

    private func logParallelQueueState() {
        os_log("secondaryQueue.count: %2d, suspended: %@", type: .debug, secondaryQueue.operationCount,
               String(describing: secondaryQueue.isSuspended))
    }

    // MARK: - Running Operations

    private func runJob(_ name: String, work: () -> Void) {
        let start = Date()
        if Jobs.debugLogging { os_log("STARTING JOB: %@", type: .debug, name) }

        // do the job
        work()

        if Jobs.debugLogging { os_log("FINISHED JOB: %@ (duration: %6.3f seconds)", type: .debug, name, start.age) }

        // always pause managed queues between background jobs
        if applicationState == .background { pauseManagedQueues(for: 60) }
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
                if Jobs.debugLogging {
                    os_log("DEMOTING: %@:%@", type: .debug, queue.name ?? "Unnamed", operation.name ?? "Unnamed")
                }
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
            queue.qualityOfService = queue == primaryQueue ? .userInitiated : .utility
            for operation in queue.operations where operation.qualityOfService == .background {
                if Jobs.debugLogging {
                    os_log("PROMOTING: %@:%@", type: .debug, queue.name ?? "Unnamed", operation.name ?? "Unnamed")
                }
                operation.qualityOfService = queue == primaryQueue ? .userInitiated : .utility
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
            if Jobs.debugLogging { os_log("PAUSING QUEUE: %@ (duration: %d)", queue.name ?? "Unnamed", duration ?? -1) }
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
                if Jobs.debugLogging { os_log("RESUMING: %@", queue.name ?? "Unnamed") }
                queue.isSuspended = false
            }
        }
    }

}

// MARK: -

func delay(_ delay: Double, closure: @escaping () -> ()) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: closure)
}

func delay(_ delay: TimeInterval, onQueue queue: DispatchQueue, closure: @escaping () -> ()) {
    queue.asyncAfter(deadline: .now() + delay, execute: closure)
}
