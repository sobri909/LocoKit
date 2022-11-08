//
//  ClassifierResults.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 29/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Upsurge

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

    public init(merging resultsArray: [ClassifierResults]) {
        var allScores: [ActivityTypeName: ValueArray<Double>] = [:]
        for typeName in ActivityTypeName.allTypes {
            allScores[typeName] = ValueArray(capacity: resultsArray.count)
        }

        for result in resultsArray {
            for typeName in ActivityTypeName.allTypes {
                if let resultRow = result[typeName] {
                    allScores[resultRow.name]!.append(resultRow.score)
                } else {
                    allScores[typeName]!.append(0)
                }
            }
        }

        var mergedResults: [ClassifierResultItem] = []
        for typeName in ActivityTypeName.allTypes {
            var finalScore = 0.0
            if let scores = allScores[typeName], !scores.isEmpty {
                finalScore = mean(scores)
            }
            mergedResults.append(ClassifierResultItem(name: typeName, score: finalScore))
        }

        self.init(results: mergedResults, moreComing: false)
    }

    func merging(_ otherResults: ClassifierResults, withWeight otherWeight: Double) -> ClassifierResults {
        let selfWeight = 1.0 - otherWeight

        var combinedDict: [ActivityTypeName: ClassifierResultItem] = [:]
        let combinedTypes = Set(self.results.map { $0.name } + otherResults.map { $0.name })

        for typeName in combinedTypes {
            let selfScore = self[typeName]?.score ?? 0.0
            let otherScore = otherResults[typeName]?.score ?? 0.0
            let mergedScore = (selfScore * selfWeight) + (otherScore * otherWeight)
            let mergedItem = ClassifierResultItem(name: typeName, score: mergedScore)
            combinedDict[typeName] = mergedItem
        }

        return ClassifierResults(results: Array(combinedDict.values),
                                 moreComing: self.moreComing || otherResults.moreComing)
    }

    // MARK: -
    
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
        return results.map { $0.score }.sum
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
