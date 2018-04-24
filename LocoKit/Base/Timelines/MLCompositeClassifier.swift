//
//  MLCompositeClassifier.swift
//  Pods
//
//  Created by Matt Greenfield on 10/04/18.
//

public protocol MLCompositeClassifier: class {

    var canClassify: Bool { get }

    func classify(_ classifiable: ActivityTypeClassifiable, filtered: Bool) -> ClassifierResults?
    func classify(_ samples: [ActivityTypeClassifiable], filtered: Bool) -> ClassifierResults?
    func classify(_ timelineItem: TimelineItem, filtered: Bool) -> ClassifierResults?
    func classify(_ segment: ItemSegment, filtered: Bool) -> ClassifierResults?

}
