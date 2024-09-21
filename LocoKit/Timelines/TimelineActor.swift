//
//  TimelineActor.swift
//  LocoKit2
//
//  Created by Matt Greenfield on 2024-08-13.
//

import Foundation

@globalActor
public actor TimelineActor: GlobalActor {
    public static let shared = TimelineActor()

    public static var queue: DispatchQueue { executor.queue }

    private static let executor = CustomSerialExecutor(label: "TimelineActorQueue")

    public static let sharedUnownedExecutor: UnownedSerialExecutor = TimelineActor.executor.asUnownedSerialExecutor()

    nonisolated
    public var unownedExecutor: UnownedSerialExecutor { Self.sharedUnownedExecutor }
}
