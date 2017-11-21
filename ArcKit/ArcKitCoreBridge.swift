//
// Created by Matt Greenfield on 21/11/17.
// Copyright (c) 2015 Big Paua. All rights reserved.
//

import ArcKitCore

public typealias ArcKitService = ArcKitCore.ArcKitService

public typealias MovingState = ArcKitCore.MovingState
public typealias LocomotionMagicValue = ArcKitCore.LocomotionMagicValue

public typealias ActivityTypeName = ArcKitCore.ActivityTypeName
public typealias ActivityTypesCache = ArcKitCore.ActivityTypesCache
public typealias ActivityTypeClassifier = ArcKitCore.ActivityTypeClassifier
public typealias ActivityTypeClassifiable = ArcKitCore.ActivityTypeClassifiable

public typealias CoreMotionActivityTypeName = ArcKitCore.CoreMotionActivityTypeName

public typealias ClassifierResults = ArcKitCore.ClassifierResults
public typealias ClassifierResultItem = ArcKitCore.ClassifierResultItem


public func +(left: ClassifierResults, right: ClassifierResults) -> ClassifierResults {
    return ClassifierResults(results: left.array + right.array, moreComing: left.moreComing || right.moreComing)
}

public func -(left: ClassifierResults, right: ActivityTypeName) -> ClassifierResults {
    return ClassifierResults(results: left.array.filter { $0.name != right }, moreComing: left.moreComing)
}
