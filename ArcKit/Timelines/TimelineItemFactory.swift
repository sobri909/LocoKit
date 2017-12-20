//
//  TimelineItemFactory.swift
//  ArcKit
//
//  Created by Matt Greenfield on 18/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

public protocol TimelineItemFactory {
    associatedtype VisitItem: TimelineItem
    associatedtype PathItem: TimelineItem

    static var highlander: Self { get }

    func createVisit(from sample: LocomotionSample) -> VisitItem
    func createPath(from sample: LocomotionSample) -> PathItem
}

