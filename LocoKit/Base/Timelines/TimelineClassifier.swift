//
//  TimelineClassifier.swift
//  LocoKit
//
//  Created by Matt Greenfield on 30/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

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

    public var transportMeetsThreshold: Bool {
        if let coverage = transportClassifier?.coverageScore, coverage > minimumTransportCoverage {
            return true
        }
        return false
    }

}
