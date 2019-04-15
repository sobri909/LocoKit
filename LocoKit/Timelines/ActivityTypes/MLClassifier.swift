//
//  MLClassifier.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 20/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreLocation

public protocol MLClassifier {
    
    associatedtype Cache: MLModelSource

    var depth: Int { get }
    var parent: Cache.ParentClassifier? { get }
    var supportedTypes: [ActivityTypeName] { get }
    var models: [Cache.Model] { get }

    var availableTypes: [ActivityTypeName] { get }
    var centerCoordinate: CLLocationCoordinate2D? { get }

    // MARK: Creating a Classifier

    /**
     Use this init method to create a new classifier.

     The classifier will be created from locally cached model data. If no appropriate model data is found in cache,
     a fetch request will be made to the server, and the init will immediately return nil. Assuming an internet
     connection is available, a second attempt to create the classifier, a second later, should return a valid
     classifier.

     - Note: Classifiers should be retained and reused. Classifier creation requires potentially expensive cache
     lookups and remote model data fetches. As such, creating new classifiers should only be done on an as needed
     basis, and existing classifiers should be reused while still valid.
     */
    init?(requestedTypes: [ActivityTypeName], coordinate: CLLocationCoordinate2D)

    /**
     Classify a `LocomotionSample` to determine its most likely `ActivityTypeName`.
     
     - Note: This method is the main purpose of classifiers, and is optimised with the expectation that it will called
     repeatedly during an app session. Although there is unavoidably some energy cost to classifying samples,
     so the frequency of classifications should be considered carefully, especially in long running apps.
     
     For example, the LocoKit Demo App calls a classifier every time a new location is received, thus up to about
     once every second. On the other hand, [Arc App](https://itunes.apple.com/us/app/arc-app-location-activity-tracker/id1063151918?mt=8)
     classifies samples only once every six seconds at most, due to the expectation that the app will be recording
     and classifying potentially hours of data each day.
     */
    func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults

    /**
     Determine whether the given coordinate is inside the classifier's geographical region.

     This method works well in combination with `isStale` as a test for whether a classifier should be used to classify
     a sample, or whether a fresh classifier should instead be requested.

     - Note: Ideally classifiers should only be used to classify samples that fall inside the classifier's region.
     However if relevant model data is in the local cache and no internet connection is available, thus a fresh
     classifier cannot be fetched, a stale and/or geographically inappropriate classifier may continue to be used,
     albeit with potentially reduced accuracy.

     Extended transport activity types (car, train, etc) will have especially inaccurate results when classified
     by a geographically inappropriate classifier. However base types (walking, running, etc) should receive
     adequately accurate results in any classifier, regardless of geographical appropriateness.
     */
    func contains(coordinate: CLLocationCoordinate2D) -> Bool

    // MARK: Classifier Validity

    /**
     Whether the classifier's model data is old enough to justify requesting a new classifier with fresh model data.

     This bool works well in combination with `contains(coordinate:)` as a test for whether a classifier should be
     used to classify a sample, or whether a fresh classifier should instead be used.
     */
    var isStale: Bool { get }

    var lastUpdated: Date? { get }

    // MARK: Data Coverage and Accuracy

    /**
     Coverage Score is the result of `completenessScore x accuracyScore`, in the range of 0.0 to 1.0.

     This value is best used to get a general sense of the expected quality and usability of the classifier's results.

     In practice, any score above 0.15 indicates a usable classifier in terms of local model data, however you should
     experiment with a range of thresholds to determine a best fit minimum for your app's accuracy requirements.
     */
    var coverageScore: Double { get }

    /**
     Accuracy Score is the expected minimum accuracy of the clasifier's results, in the range of 0.0 to 1.0.

     This value should not be used directly. Instead you should use `coverageStore` to determine the usability of a
     classifier.

     - Note: This number represents the worst case accuracy. The achieved accuracy will typically be considerably
     higher than this value. A classifier with an Accuracy Score above 0.75 will appear to give essentially
     perfect results in most cases.
     */
    var accuracyScore: Double? { get }

    /**
     Completeness Score is an internal, machine learning specific measure of the number of training samples used to
     compose the model versus a threshold sample count.

     This value should not be used directly. Instead you should use `coverageStore` to determine the usability of a
     classifier.
     */
    var completenessScore: Double { get }

    var coverageScoreString: String { get }
}

extension MLClassifier {

    public func classify(_ classifiable: ActivityTypeClassifiable, previousResults: ClassifierResults?) -> ClassifierResults {
        var totalSamples = 1 // start with 1 to avoid potential div by zero
        for model in models {
            totalSamples += model.totalSamples
        }

        var scores: [ClassifierResultItem] = []
        for model in models {
            let typeScore = model.scoreFor(classifiable: classifiable, previousResults: previousResults)
            let pctOfAllEvents = Double(model.totalSamples) / Double(totalSamples)
            let finalScore = typeScore * pctOfAllEvents

            let result = ClassifierResultItem(name: model.name, score: finalScore,
                                              modelAccuracyScore: model.accuracyScore)
            scores.append(result)
        }

        var contained = false
        if let coordinate = classifiable.location?.coordinate, contains(coordinate: coordinate) {
            contained = true
        }

        // classifier is complete, and contains the coord?
        if contained && completenessScore >= 1 {
            return ClassifierResults(results: scores, moreComing: false)
        }

        // no parent? we'll have to settle for what we've got
        guard let parent = parent else {
            return ClassifierResults(results: scores, moreComing: depth > 1)
        }

        let parentResults = parent.classify(classifiable, previousResults: previousResults)

        // if classifier doesn't contain the coord, it should defer all weight to parent
        let selfWeight = contained ? completenessScore : 0
        let parentWeight = 1.0 - selfWeight

        var selfScoresDict: [ActivityTypeName: ClassifierResultItem] = [:]
        for result in scores {
            selfScoresDict[result.name] = result
        }

        var finalScores: [ClassifierResultItem] = []

        for typeName in supportedTypes {

            // combine self result and parent result
            if let selfResult = selfScoresDict[typeName], let parentResult = parentResults[typeName] {
                let score = (parentResult.score * parentWeight) + (selfResult.score * selfWeight)
                let finalResult = ClassifierResultItem(name: selfResult.name, score: score,
                                                       modelAccuracyScore: selfResult.modelAccuracyScore)
                finalScores.append(finalResult)
                continue
            }

            // only have self result
            if let selfResult = selfScoresDict[typeName] {
                let score = (selfResult.score * selfWeight)
                let finalResult = ClassifierResultItem(name: selfResult.name, score: score,
                                                       modelAccuracyScore: selfResult.modelAccuracyScore)
                finalScores.append(finalResult)
                continue
            }

            // only have parent result
            if let parentResult = parentResults[typeName] {
                let score = (parentResult.score * parentWeight)
                let finalResult = ClassifierResultItem(name: parentResult.name, score: score, modelAccuracyScore: nil)
                finalScores.append(finalResult)
                continue
            }
        }

        return ClassifierResults(results: finalScores, moreComing: parentResults.moreComing)
    }

    public func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        if depth == 0 { return true }
        guard let firstType = models.first else { return false }
        return firstType.contains(coordinate: coordinate)
    }

    public var availableTypes: [ActivityTypeName] {
        return models.sorted { $0.totalSamples > $1.totalSamples }.map { $0.name }
    }

    public var centerCoordinate: CLLocationCoordinate2D? {
        return models.first?.centerCoordinate
    }

    public var isStale: Bool {
        return models.isStale
    }

    public var coverageScore: Double {
        guard let accuracyScore = self.accuracyScore else {
            return self.completenessScore
        }
        return self.completenessScore * accuracyScore
    }

    public var coverageScoreString: String {
        let score = coverageScore

        let intScore = Int(score * 10).clamped(min: 0, max: 10)

        var words: String
        switch intScore {
        case 8...10:
            words = "Excellent"
        case 5...7:
            words = "Very Good"
        case 3...4:
            words = "Good"
        case 1...2:
            words = "Low"
        default:
            words = "Very Low"
        }

        return String(format: "%@ (%.0f%%)", words, score * 100)
    }
}

