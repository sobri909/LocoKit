//
//  TimelineClassifier.swift
//  LocoKit
//
//  Created by Matt Greenfield on 30/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKitCore

#if canImport(Reachability)
import Reachability
#endif

public class TimelineClassifier: MLClassifierManager {

    public typealias Classifier = ActivityTypeClassifier

    public let minimumTransportCoverage = 0.10

    public static var highlander = TimelineClassifier()

    public var baseClassifier: Classifier?
    public var transportClassifier: Classifier?

    #if canImport(Reachability)
    public let reachability = Reachability()!
    #endif

    public let mutex = PThreadMutex(type: .recursive)

    public func classifyTransportTypes(for classifiable: ActivityTypeClassifiable) -> Bool {

        // faster than 300km/h is almost certainly airplane
        if let kmh = classifiable.location?.speed.kmh, kmh > 300 { return true }

        // meeting minimum coverage score is good enough
        if let coverage = transportClassifier?.coverageScore, coverage > minimumTransportCoverage { return true }

        // at least one complete model is good enough
        guard let models = transportClassifier?.models else { return false }
        for model in models {
            if model.completenessScore >= 1.0 { return true }
        }

        return false
    }

}
