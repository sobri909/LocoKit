//
//  CustomSerialExecutor.swift
//  LocoKit2
//
//  Created by Matt Greenfield on 2024-09-03.
//

import Foundation

final class CustomSerialExecutor: SerialExecutor {
    let queue: DispatchQueue

    init(label: String) {
        self.queue = DispatchQueue(label: label)
    }

    func enqueue(_ job: UnownedJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        return UnownedSerialExecutor(ordinary: self)
    }
}
