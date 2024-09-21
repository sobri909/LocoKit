//
//  Debouncer.swift
//  Arc
//
//  Created by Matt Greenfield on 26/10/23.
//  Copyright © 2023 Big Paua. All rights reserved.
//

import Foundation

final class Debouncer {
    private var currentTask: Task<Void, Error>? {
        willSet { currentTask?.cancel() }
    }

    deinit {
        currentTask?.cancel()
    }

    func debounce(duration: TimeInterval, _ action: @escaping @Sendable () async -> Void) {
        currentTask = Task {
            try await Task.sleep(for: .seconds(duration))
            await action()
        }
    }
}
