//
// Created by Matt Greenfield on 21/11/17.
// Copyright (c) 2015 Big Paua. All rights reserved.
//

import LocoKitCore

public typealias LocoKitService = LocoKitCore.LocoKitService

public typealias MovingState = LocoKitCore.MovingState
public typealias LocomotionMagicValue = LocoKitCore.LocomotionMagicValue

public typealias ActivityTypeName = LocoKitCore.ActivityTypeName
public typealias ActivityTypeClassifier = LocoKitCore.ActivityTypeClassifier
public typealias ActivityTypeClassifiable = LocoKitCore.ActivityTypeClassifiable

public typealias CoreMotionActivityTypeName = LocoKitCore.CoreMotionActivityTypeName

public typealias ClassifierResults = LocoKitCore.ClassifierResults
public typealias ClassifierResultItem = LocoKitCore.ClassifierResultItem

public func +(left: ClassifierResults, right: ClassifierResults) -> ClassifierResults {
    return ClassifierResults(results: left.array + right.array, moreComing: left.moreComing || right.moreComing)
}

public func -(left: ClassifierResults, right: ActivityTypeName) -> ClassifierResults {
    return ClassifierResults(results: left.array.filter { $0.name != right }, moreComing: left.moreComing)
}
