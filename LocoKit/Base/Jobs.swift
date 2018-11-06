//
//  Jobs.swift
//  LocoKit
//
//  Created by Matt Greenfield on 5/11/18.
//

import os.log

public class Jobs {

    public static var debugLogging = true

    // MARK: - Adding Operations

    public static func addSerialJob(_ name: String, qos: QualityOfService = .background, block: @escaping () -> Void) {
        let job = BlockOperation() {
            highlander.runJob(name) { block() }
        }
        job.name = name
        job.qualityOfService = qos
        highlander.serialQueue.addOperation(job)

        // suspend the parallel queue while serial queue is non empty
        highlander.parallelQueue.isSuspended = true
    }

    public static func addParallelJob(_ name: String, qos: QualityOfService = .background, block: @escaping () -> Void) {
        let job = BlockOperation() {
            highlander.runJob(name) { block() }
        }
        job.name = name
        job.qualityOfService = qos
        highlander.parallelQueue.addOperation(job)
    }

    // MARK: - Singleton

    public static let highlander = Jobs()

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
                if Jobs.debugLogging { os_log("RESUMING PARALLEL QUEUE (serialQueue.operationCount == 0)") }
                self.parallelQueue.isSuspended = false
            }
        })

        // debug observers
        if Jobs.debugLogging {
            observers.append(serialQueue.observe(\.operationCount) { _, _ in
                self.logQueueStates()
            })
            observers.append(parallelQueue.observe(\.operationCount) { _, _ in
                self.logQueueStates()
            })
            observers.append(serialQueue.observe(\.isSuspended) { _, _ in
                self.logQueueStates()
            })
            observers.append(parallelQueue.observe(\.isSuspended) { _, _ in
                self.logQueueStates()
            })
        }
    }

    private func logQueueStates() {
        os_log("  serialQueue.count: %2d, suspended: %@", type: .debug, serialQueue.operationCount,
               String(describing: serialQueue.isSuspended))
        os_log("parallelQueue.count: %2d, suspended: %@", type: .debug, parallelQueue.operationCount,
               String(describing: parallelQueue.isSuspended))
    }

    // MARK: - Operation Management

    private func runJob(_ name: String, work: () -> Void) {
        let start = Date()
        if Jobs.debugLogging { os_log("Starting job: %@", type: .debug, name) }

        // do the job
        work()

        if Jobs.debugLogging { os_log("Finished job: %@ (duration: %6.3f seconds)", type: .debug, name, start.age) }

        // always pause between background jobs
        if applicationState == .background { pauseQueues(for: 60) }
    }

    // MARK: - Queue Management

    private func didEnterBackground() {

        // change parallel queue to be a serial queue
        parallelQueue.maxConcurrentOperationCount = 1

        // change all operations to .background priority
        for operation in serialQueue.operations where operation.qualityOfService != .background {
            if Jobs.debugLogging {
                os_log("Demoting: %@ (from %d to %d)", type: .debug, operation.name!,
                       operation.qualityOfService.rawValue, QualityOfService.background.rawValue)
            }
            operation.qualityOfService = .background
        }
        for operation in parallelQueue.operations where operation.qualityOfService != .background {
            if Jobs.debugLogging {
                os_log("Demoting: %@ (from %d to %d)", type: .debug, operation.name!,
                       operation.qualityOfService.rawValue, QualityOfService.background.rawValue)
            }
            operation.qualityOfService = .background
        }
    }

    private func didBecomeActive() {

        // change parallel queue back to being a parallel queue
        parallelQueue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount

        // resume paused queues
        resumeQueues()
    }

    private var resumeWorkItem: DispatchWorkItem?

    private func pauseQueues(for duration: TimeInterval) {
        print("resumeWorkItem: \(resumeWorkItem)")

        // cancel any previous resume task
        resumeWorkItem?.cancel()
        resumeWorkItem = nil

        // pause the queues
        if canPauseSerialQueue && !serialQueue.isSuspended {
            if Jobs.debugLogging { os_log("PAUSING SERIAL QUEUE") }
            serialQueue.isSuspended = true
        }
        if !parallelQueue.isSuspended {
            if Jobs.debugLogging { os_log("PAUSING PARALLEL QUEUE") }
            parallelQueue.isSuspended = true
        }

        // queue up a task for resuming the queues
        let workItem = DispatchWorkItem {
            self.resumeQueues()
        }
        resumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func resumeQueues() {
        resumeWorkItem?.cancel()
        resumeWorkItem = nil

        if parallelQueue.isSuspended {
            if Jobs.debugLogging { os_log("RESUMING PARALLEL QUEUE") }
            parallelQueue.isSuspended = false
        }
        if serialQueue.isSuspended {
            if Jobs.debugLogging { os_log("RESUMING SERIAL QUEUE") }
            serialQueue.isSuspended = false
        }
    }

    private var canPauseSerialQueue: Bool {
        return LocomotionManager.highlander.recordingState != .recording
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

func delay(_ delay: Double, closure: @escaping () -> ()) {
    DispatchQueue.main.asyncAfter(
        deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
        execute: closure)
}
