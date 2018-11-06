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

    public static var debugLogging = true

    // MARK: - Adding Operations

    public static func addSerialJob(_ name: String, block: @escaping () -> Void) {
        let job = BlockOperation() {
            highlander.runJob(name) { block() }
        }
        job.name = name
        job.qualityOfService = highlander.applicationState == .active ? .utility : .background
        highlander.serialQueue.addOperation(job)

        // suspend the parallel queue while serial queue is non empty
        if !highlander.parallelQueue.isSuspended {
            if Jobs.debugLogging { os_log("PAUSING PARALLEL QUEUE (serialQueue.operationCount > 0)") }
            highlander.parallelQueue.isSuspended = true
        }
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
            if self.parallelQueue.isSuspended, self.serialQueue.operationCount == 0, self.resumeWorkItem == nil {
                self.resumeParallelQueue()
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
        os_log("parallelQueue.count: %2d, suspended: %@", type: .debug, parallelQueue.operationCount,
               String(describing: parallelQueue.isSuspended))
    }

    // MARK: - Running Operations

    private func runJob(_ name: String, work: () -> Void) {
        let start = Date()
        if Jobs.debugLogging { os_log("STARTING JOB: %@", type: .debug, name) }

        // do the job
        work()

        if Jobs.debugLogging { os_log("FINISHED JOB: %@ (duration: %6.3f seconds)", type: .debug, name, start.age) }

        // always pause between background jobs
        if applicationState == .background { pauseParallelQueue(for: 60) }
    }

    // MARK: - Queue State Management

    private func didEnterBackground() {

        // change parallel queue to be a serial queue
        parallelQueue.maxConcurrentOperationCount = 1

        // change all operations to .background priority
        for operation in serialQueue.operations where operation.qualityOfService != .background {
            if Jobs.debugLogging {
                os_log("DEMOTING: %@ (from %d to %d)", type: .debug, operation.name!,
                       operation.qualityOfService.rawValue, QualityOfService.background.rawValue)
            }
            operation.qualityOfService = .background
        }
        for operation in parallelQueue.operations where operation.qualityOfService != .background {
            if Jobs.debugLogging {
                os_log("DEMOTING: %@ (from %d to %d)", type: .debug, operation.name!,
                       operation.qualityOfService.rawValue, QualityOfService.background.rawValue)
            }
            operation.qualityOfService = .background
        }
    }

    private func didBecomeActive() {

        // change parallel queue back to being a parallel queue in foreground
        parallelQueue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount

        // resume the parallel queue in foreground
        resumeParallelQueue()
    }

    private var resumeWorkItem: DispatchWorkItem?

    private func pauseParallelQueue(for duration: TimeInterval) {
        resumeWorkItem?.cancel()
        resumeWorkItem = nil

        // already paused? then nothing to do here
        if parallelQueue.isSuspended { return }

        // pause the parallel queue
        if Jobs.debugLogging { os_log("PAUSING PARALLEL QUEUE (duration: %d)", duration) }
        parallelQueue.isSuspended = true

        // queue up a task for resuming the queues
        let workItem = DispatchWorkItem {
            self.resumeParallelQueue()
        }
        resumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func resumeParallelQueue() {
        resumeWorkItem?.cancel()
        resumeWorkItem = nil

        guard serialQueue.operationCount == 0 else { return }

        if parallelQueue.isSuspended {
            if Jobs.debugLogging { os_log("RESUMING PARALLEL QUEUE") }
            parallelQueue.isSuspended = false
        }
    }

    // MARK: - Queues

    private(set) public var serialQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private(set) public var parallelQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .background
        return queue
    }()

}

// MARK: -

func delay(_ delay: Double, closure: @escaping () -> ()) {
    DispatchQueue.main.asyncAfter(
        deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
        execute: closure)
}
