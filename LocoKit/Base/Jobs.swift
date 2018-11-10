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

    private(set) public var serialQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LocoKit.serialQueue"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // will be converted to serial while in the background
    private(set) public var parallelQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LocoKit.parallelQueue"
        queue.qualityOfService = .background
        return queue
    }()

    // will be suspended while serialQueue is busy
    public lazy var managedQueues: [OperationQueue] = {
        return [self.parallelQueue]
    }()

    // MARK: - Adding Operations

    public static func addSerialJob(_ name: String, block: @escaping () -> Void) {
        let job = BlockOperation() {
            highlander.runJob(name) { block() }
        }
        job.name = name
        job.qualityOfService = highlander.applicationState == .active ? .utility : .background
        highlander.serialQueue.addOperation(job)

        // suspend the parallel queue while serial queue is non empty
        highlander.pauseManagedQueues()
    }

    public static func addParallelJob(_ name: String, block: @escaping () -> Void) {
        let job = BlockOperation() {
            highlander.runJob(name) { block() }
        }
        job.name = name
        job.qualityOfService = .background
        highlander.parallelQueue.addOperation(job)
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

        // if serial queue complete, open up the parallel queue again
        observers.append(serialQueue.observe(\.operationCount) { _, _ in
            if self.serialQueue.operationCount == 0, self.resumeWorkItem == nil {
                self.resumeManagedQueues()
            }
        })

        // debug observers
        if Jobs.debugLogging {
            observers.append(serialQueue.observe(\.operationCount) { _, _ in
                self.logSerialQueueState()
            })
            observers.append(serialQueue.observe(\.isSuspended) { _, _ in
                self.logSerialQueueState()
            })
            observers.append(parallelQueue.observe(\.operationCount) { _, _ in
                self.logParallelQueueState()
            })
            observers.append(parallelQueue.observe(\.isSuspended) { _, _ in
                self.logParallelQueueState()
            })
        }
    }

    private func logSerialQueueState() {
        os_log("  serialQueue.count: %2d, suspended: %@", type: .debug, serialQueue.operationCount,
               String(describing: serialQueue.isSuspended))
    }

    private func logParallelQueueState() {
        os_log("parallelQueue.count: %2d, suspended: %@, maxConcurrent: %d", type: .debug, parallelQueue.operationCount,
               String(describing: parallelQueue.isSuspended), parallelQueue.maxConcurrentOperationCount)
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

        // change parallel queue to be a serial queue
        parallelQueue.maxConcurrentOperationCount = 1

        let queues = managedQueues + [serialQueue]

        // demote all operations on all queues to .background priority
        for queue in queues {
            for operation in queue.operations where operation.qualityOfService != .background {
                if Jobs.debugLogging {
                    os_log("DEMOTING: %@ (from %d to %d)", type: .debug, operation.name!,
                           operation.qualityOfService.rawValue, QualityOfService.background.rawValue)
                }
                operation.qualityOfService = .background
            }
        }
    }

    private func didBecomeActive() {

        // change parallel queue back to being a parallel queue in foreground
        parallelQueue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount

        // resume the parallel queue in foreground
        resumeManagedQueues()
    }

    private var resumeWorkItem: DispatchWorkItem?

    private func pauseManagedQueues(for duration: TimeInterval? = nil) {
        resumeWorkItem?.cancel()
        resumeWorkItem = nil

        for queue in managedQueues where !queue.isSuspended {
            if Jobs.debugLogging { os_log("PAUSING QUEUE: %@ (duration: %d)", queue.name ?? "Unnamed",
                                          duration ?? -1) }
            parallelQueue.isSuspended = true
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

        // not allowed to resume when serial queue is still busy
        guard serialQueue.operationCount == 0 else { return }

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
    DispatchQueue.main.asyncAfter(
        deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
        execute: closure)
}
