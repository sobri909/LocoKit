//
//  DefaultItemFactory.swift
//  ArcKit
//
//  Created by Matt Greenfield on 18/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

public final class DefaultItemFactory: TimelineItemFactory {
    public typealias PathItem = Path
    public typealias VisitItem = Visit

    public static var highlander = DefaultItemFactory()

    public func createVisit(from sample: LocomotionSample) -> Visit {
        return Visit(sample: sample)
    }
    public func createPath(from sample: LocomotionSample) -> Path {
        return Path(sample: sample)
    }
}

