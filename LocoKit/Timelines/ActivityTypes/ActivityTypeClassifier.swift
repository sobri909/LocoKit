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

     stationary, walking, running, cycling

 Base types match one-to-one with [Core Motion activity types](https://developer.apple.com/documentation/coremotion/cmmotionactivity),
 with the exception of Core Motion's "automotive" type, which is instead handled by extended types in LocoKit.

 #### Extended Types

    car, train, bus, motorcycle, boat, airplane, tram, horseback, scooter, skateboarding, tractor, skiing,
    inline skating, metro, tuk-tuk, songthaew

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

 #### Stationary, Walking, Running, Cycling

 The base activity types of stationary, walking, running, and should achieve high detection accuracy everywhere in
 the world, regardless of local data availability.

 These types can be considered to have global coverage.

 #### Car, Train, Bus, Motorcycle, Airplane, Boat, etc

 Determining the specific mode of transport requires local knowledge. If knowing the specific mode of transport is
 important to your application, you should check the coverage maps for your required regions.

 When local data coverage is not high enough to distinguish specific modes of transport, a threshold probability
 score should be used on the "best match" classifier result, to determine when to fall back to presenting a generic
 "transport" classification to the user.

 For example if the highest scoring type is "cycling", but its probability score is only 0.001, that identifies it as
 a terrible match, thus the real type is most likely some other mode of transport. Your UI should then avoid claiming
 "cycling", and instead report a generic type name to the user, such as "transport", "automotive", or "unknown".
 */
public class ActivityTypeClassifier: MLClassifier {

    public typealias Cache = ActivityTypesCache
    public typealias ParentClassifier = Cache.ParentClassifier

    let cache = Cache.highlander

    public let depth: Int
    public let supportedTypes: [ActivityTypeName]
    public let models: [Cache.Model]

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

    // MARK: - Init
    
    public convenience required init?(requestedTypes: [ActivityTypeName] = ActivityTypeName.baseTypes,
                                      coordinate: CLLocationCoordinate2D) {
        self.init(requestedTypes: requestedTypes, coordinate: coordinate, depth: 2)
    }
    
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

