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
            highlander.runJob(name, suspendParallelQueue: true) { block() }
        }
        job.name = name
        job.qualityOfService = qos
        highlander.serialQueue.addOperation(job)
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

    private var applicationState: UIApplication.State

    private init() {
        self.applicationState = UIApplication.shared.applicationState

        let notes =  NotificationCenter.default
        notes.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            self.applicationState = .background
            self.didEnterBackground()
        }
        notes.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            self.applicationState = .active
            self.didBecomeActive()
        }
    }

    // MARK: - Operation Management

    private func runJob(_ name: String, suspendParallelQueue: Bool = false, block: () -> Void) {
        if Jobs.debugLogging {
            os_log("serialQueue.count: %d, parallelQueue.count: %d", type: .debug,
                   serialQueue.operationCount, parallelQueue.operationCount)
        }

        // suspend the parallel queue while serial queue is active
        if suspendParallelQueue { parallelQueue.isSuspended = true }

        let start = Date()
        if Jobs.debugLogging { os_log("Starting job: %@", type: .debug, name) }

        // do the job
        block()

        if Jobs.debugLogging { os_log("Finished job: %@ (duration: %6.3f seconds)", type: .debug, name, start.age) }

        // open up the parallel queue again
        parallelQueue.isSuspended = false

        if Jobs.debugLogging {
            os_log("serialQueue.count: %2d, parallelQueue.count: %2d", type: .debug,
                   serialQueue.operationCount, parallelQueue.operationCount)
        }

        // always insert a second pause between background jobs
        if applicationState == .background { pauseQueues(for: 60) }
    }

    // MARK: - Queue Management

    private func didEnterBackground() {

        // change all operations to .background priority
        serialQueue.operations.forEach {
            if Jobs.debugLogging {
                os_log("Demoting: %@ (from %d to %d)", type: .debug, $0.name!, $0.qualityOfService.rawValue,
                       QualityOfService.background.rawValue)
            }
            $0.qualityOfService = .background
        }
        parallelQueue.operations.forEach {
            if Jobs.debugLogging {
                os_log("Demoting: %@ (from %d to %d)", type: .debug, $0.name!, $0.qualityOfService.rawValue,
                       QualityOfService.background.rawValue)
            }
            $0.qualityOfService = .background
        }

        // change parallel queue to be a serial queue
        parallelQueue.maxConcurrentOperationCount = 1
    }

    private func didBecomeActive() {
        if Jobs.debugLogging {
            os_log("serialQueue.count: %2d, parallelQueue.count: %2d", type: .debug,
                   serialQueue.operationCount, parallelQueue.operationCount)
        }

        // change parallel queue back to being a parallel queue
        parallelQueue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount

        // resume paused queues
        parallelQueue.isSuspended = false
        serialQueue.isSuspended = false
    }

    private func pauseQueues(for duration: TimeInterval) {
        if parallelQueue.isSuspended { return } // don't bother pausing if already paused

        if canPauseSerialQueue {
            if Jobs.debugLogging { os_log("PAUSING SERIAL QUEUE") }
            serialQueue.isSuspended = true
        }
        if Jobs.debugLogging { os_log("PAUSING PARALLEL QUEUE") }
        parallelQueue.isSuspended = true

        delay(duration) {
            self.parallelQueue.isSuspended = false
            self.serialQueue.isSuspended = false
            if Jobs.debugLogging { os_log("RESUMING QUEUES") }
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
