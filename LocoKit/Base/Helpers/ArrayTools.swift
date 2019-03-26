//
//  ArrayTools.swift
//  LocoKit
//
//  Created by Matt Greenfield on 5/09/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

public extension Array {

    var second: Element? {
        guard count > 1 else { return nil }
        return self[1]
    }

    var secondToLast: Element? {
        guard count > 1 else { return nil }
        return self[count - 2]
    }

}

public extension Array where Element: FloatingPoint {

    var sum: Element { return reduce(0, +) }
    var mean: Element { return isEmpty ? 0 : sum / Element(count) }
    
    var variance: Element {
        let mean = self.mean
        let squareDiffs = self.map { value -> Element in
            let diff = value - mean
            return diff * diff
        }
        return squareDiffs.mean
    }
    
    var standardDeviation: Element { return variance.squareRoot() }

}

public extension Array where Element: Equatable {
    mutating func remove(_ object: Element) { if let index = index(of: object) { remove(at: index) } }
    mutating func removeObjects(_ array: [Element]) { for object in array { remove(object) } }
}

public extension Array where Element: Comparable {
    var range: (min: Element, max: Element)? {
        guard let min = self.min(), let max = self.max() else { return nil }
        return (min: min, max: max)
    }
}

