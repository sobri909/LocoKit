//
//  ClassifierResults.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 29/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Upsurge

/**
 The results of a call to `classify(_:types:)` on an `ActivityTypeClassifier`.

 Classifier Results are an iterable sequence of `ClassifierResultItem` rows, with each row representing a single
 `ActivityTypeName` and its match probability score.

 The results are ordered from best match to worst match, thus the first result row represents the best match for the
 given sample.

 ## Using The Results

 The simplest way to use the results is to take the first result row (ie the best match) and ignore the rest.

 ```swift
 let results = classifier.classify(sample)

 let bestMatch = results.first
 ```

 You could also iterate through the results, in order from best match to worst match.

 ```swift
 for result in results {
     print("name: \(result.name) score: \(result.score)")
 }
 ```

 If you want to know the probability score of a specific type, you could extract that result row by `ActivityTypeName`:

 ```swift
 let walkingResult = results[.walking]
 ```

 If you want the first and second result rows:

 ```swift
 let firstResult = results[0]
 let secondResult = results[1]
 ```

 ## Interpreting Classifier Results

 Two key indicators can help to interpret the probability scores. The first being the most obvious: a higher score
 indicates a better match.

 The second, and perhaps more important indicator, is the ratio of the best match's score to the second best match's
 score.

 For example if the first result row has a probability score of 0.9 (a 90% match) while the second result row's score
 is 0.1 (a 10% match), that indicates that the best match is nine times more probable than the second best match
 (`0.9 / 0.1 = 9.0`). However if the second row's score where instead 0.8, the first row would only be 1.125 times more
 probable than the second (`0.9 / 0.8 = 1.125`).

 The ratio between the first and second best matches can be loosely considered a "confidence" score. Thus the
 `0.9 / 0.1 = 9.0` example gives a confidence score of 9.0, whilst the second example of `0.9 / 0.8 = 1.125` gives
 a much lower confidence score of 1.125.

 A real world example might be results that have "car" and "bus" as the top two results. If both types achieve a high
 probability score, but the scores are close together, that indicates there is high confidence that the type is either
 car or bus, but low confidence of knowing which one of the two it is.

 The easiest way to apply these two metrics is with simple thresholds. For example a raw score threshold of 0.01
 and a first-to-second-match ratio threshold of 2.0. If the first match falls below these thresholds, you could consider
 it an "uncertain" match. Although which kinds of thresholds to use will depend heavily on the application.
 */
public struct ClassifierResults: Sequence, IteratorProtocol {
    
    internal let results: [ClassifierResultItem]

    public init(results: [ClassifierResultItem], moreComing: Bool) {
        self.results = results.sorted { $0.score > $1.score }
        self.moreComing = moreComing
    }

    public init(confirmedType: ActivityTypeName) {
        var resultItems = [ClassifierResultItem(name: confirmedType, score: 1)]
        for activityType in ActivityTypeName.allTypes where activityType != confirmedType {
            resultItems.append(ClassifierResultItem(name: activityType, score: 0))
        }
        self.results = resultItems
        self.moreComing = false
    }
    
    private lazy var arrayIterator: IndexingIterator<Array<ClassifierResultItem>> = {
        return self.results.makeIterator()
    }()

    /**
     Indicates that the classifier does not yet have all relevant model data, so a subsequent attempt to classify the
     same sample again may produce new results with higher accuracy.

     - Note: Classifiers manage the fetching and caching of model data internally, so if the classifier returns results
         flagged with `moreComing` it will already have requested the missing model data from the server. Provided a
         working internet connection is available, the missing model data should be available in the classifier in less
         than a second.
     */
    public let moreComing: Bool

    /**
     Returns the result rows as a plain array.
     */
    public var array: [ClassifierResultItem] {
        return results
    }

    public var isEmpty: Bool {
        return count == 0
    }

    public var count: Int {
        return results.count
    }

    public var best: ClassifierResultItem {
        if let first = first, first.score > 0 { return first }
        return ClassifierResultItem(name: .unknown, score: 0)
    }
    
    public var first: ClassifierResultItem? {
        return self.results.first
    }

    public var scoresTotal: Double {
        return sum(results.map { $0.score })
    }

    // MARK: -

    public subscript(index: Int) -> ClassifierResultItem {
        return results[index]
    }

    /**
     A convenience subscript to enable lookup by `ActivityTypeName`.

     ```swift
     let walkingResult = results[.walking]
     ```
     */
    public subscript(activityType: ActivityTypeName) -> ClassifierResultItem? {
        return results.first { $0.name == activityType }
    }
    
    public mutating func next() -> ClassifierResultItem? {
        return arrayIterator.next()
    }
}

public func +(left: ClassifierResults, right: ClassifierResults) -> ClassifierResults {
    return ClassifierResults(results: left.array + right.array, moreComing: left.moreComing || right.moreComing)
}

public func -(left: ClassifierResults, right: ActivityTypeName) -> ClassifierResults {
    return ClassifierResults(results: left.array.filter { $0.name != right }, moreComing: left.moreComing)
}
