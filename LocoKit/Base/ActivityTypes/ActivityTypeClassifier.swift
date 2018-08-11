//
//  ActivityTypeClassifier.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 3/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import CoreLocation

/**
 Activity Type Classifiers are Machine Learning Classifiers. Use an Activity Type Classifier to determine the
 `ActivityTypeName` of a `LocomotionSample`.

 - Precondition: An API key is required to make use of classifiers. See `LocoKitService.apiKey` for details.

 ## Supported Activity Types

 #### Base Types

     stationary, transport, walking, running, cycling

 Base types match one-to-one with [Core Motion activity types](https://developer.apple.com/documentation/coremotion/cmmotionactivity),
 with the exception of Core Motion's "automotive" being renamed to "transport" in LocoKit.

 #### Extended Types

     car, train, bus, motorcycle, airplane, boat

 Extended types are a subset of the base "transport" type, allowing for more specific classification when enough
 local data is available.

 ## Region Specific Classifiers

 LocoKit provides geographical region specific machine learning data, with each classifier containing the data for a
 specific region.

 This allows for detecting activity types based on region specific characteristics, with much higher accuracy than
 iOS's built in Core Motion types detection. It also makes it possible to detect a greater number of activity types,
 for example distinguishing between travel by car or train.

 LocoKit's data regions are roughly 100 kilometres by 100 kilometres squared (0.1 by 0.1 degrees), or about the size of
 a small town, or a single neighbourhood in a larger city.

 Larger cities might encompass anywhere from four to ten or more classifier regions, thus allowing the classifers to
 accurately detect activity type differences within different areas of a single city.

 ## Determining Regional Coverage

 - [LocoKit transport coverage maps](https://www.bigpaua.com/locokit/coverage/transport)
 - [LocoKit cycling coverage maps](https://www.bigpaua.com/locokit/coverage/cycling)

 #### Stationary, Transport, Walking, Running

 The base activity types of stationary, transport, walking, and running do not significantly differ by geographical
 region, thus should achieve high detection accuracy everywhere in the world, regardless of local data availability.

 These types can be considered to have global coverage.

 #### Cycling

 Cycling has enough regional variance in locomotive characteristics that detection accuracy can range from excellent
 to average depending on the availability of local model data.

 If very high accuracy cycling detection is important to your application, you should check the cycling coverage map
 for the regions you require. However if cycling detection is not a core function of your app, then the results from
 even low coverage classifiers should achieve adequate accuracy, and will certainly exceed the accuracy of Core
 Motion's detection.

 #### Car, Train, Bus, Motorcycle, Airplane, Boat

 While the base "transport" type can be detected anywhere in the world with high accuracy, determining the specific
 mode of transport requires local knowledge. If knowing the specific mode of transport is important to your
 application, you should check the coverage maps for your required regions.
 */
public class ActivityTypeClassifier: MLClassifier {

    public typealias Cache = ActivityTypesCache
    public typealias ParentClassifier = Cache.ParentClassifier

    let cache = Cache.highlander

    public let depth: Int
    public let supportedTypes: [ActivityTypeName]
    public let models: [Cache.Model]

    public lazy var requiredTypes: [ActivityTypeName] = {
        return supportedTypes.filter { $0 != .transport }
    }()

    private var _parent: ParentClassifier?
    public var parent: ParentClassifier? {
        get {
            if let parent = _parent {
                return parent
            }

            let parentDepth = depth - 1
            
            // can only get supported depths
            guard cache.providesDepths.contains(parentDepth) else {
                return nil
            }
            
            // no point in getting a parent if current depth is complete
            guard completenessScore < 1 else {
                return nil
            }
            
            // can't do anything without a coord
            guard let coordinate = centerCoordinate else {
                return nil
            }
            
            // try to fetch one
            _parent = ParentClassifier(requestedTypes: supportedTypes, coordinate: coordinate, depth: parentDepth)
            
            return _parent
        }
        
        set (newParent) {
            _parent = newParent
        }
    }

    public convenience required init?(requestedTypes: [ActivityTypeName] = ActivityTypeName.baseTypes,
                                      coordinate: CLLocationCoordinate2D) {
        self.init(requestedTypes: requestedTypes, coordinate: coordinate, depth: 2)
    }

    public lazy var lastUpdated: Date? = {
        return self.models.lastUpdated
    }()

    public lazy var lastFetched: Date = {
        return models.lastFetched
    }()

    public lazy var accuracyScore: Double? = {
        return self.models.accuracyScore
    }()

    public lazy var completenessScore: Double = {
        return self.models.completenessScore
    }()
    
    convenience init?(requestedTypes: [ActivityTypeName], coordinate: CLLocationCoordinate2D, depth: Int) {
        if requestedTypes.isEmpty {
            return nil
        }
        
        let models = Cache.highlander.modelsFor(names: requestedTypes, coordinate: coordinate, depth: depth)
        
        guard !models.isEmpty else {
            return nil
        }
        
        self.init(supportedTypes: requestedTypes, models: models, depth: depth)
        
        // bootstrap the parent
        _ = parent
    }
    
    init(supportedTypes: [ActivityTypeName], models: [Cache.Model], depth: Int) {
        self.supportedTypes = supportedTypes
        self.depth = depth
        self.models = models
    }
}

