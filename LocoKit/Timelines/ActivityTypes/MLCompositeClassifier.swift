//
//  MLCompositeClassifier.swift
//  Pods
//
//  Created by Matt Greenfield on 10/04/18.
//

import CoreLocation

public protocol MLCompositeClassifier: class {

    func canClassify(_ coordinate: CLLocationCoordinate2D?) -> Bool
    func classify(_ classifiable: ActivityTypeClassifiable, filtered: Bool) -> ClassifierResults?
    func classify(_ samples: [ActivityTypeClassifiable], filtered: Bool) -> ClassifierResults?
    func classify(_ timelineItem: TimelineItem, filtered: Bool) -> ClassifierResults?
    func classify(_ segment: ItemSegment, filtered: Bool) -> ClassifierResults?

}
