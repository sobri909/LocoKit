//
//  Array.helpers.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 5/09/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

extension Array where Element: FloatingPoint {

    var sum: Element {
        return reduce(0, +)
    }
    
    var mean: Element {
        return isEmpty ? 0 : sum / Element(count)
    }
    
    var variance: Element {
        let mean = self.mean
        let squareDiffs = self.map { value -> Element in
            let diff = value - mean
            return diff * diff
        }
        return squareDiffs.mean
    }
    
    var standardDeviation: Element {
        return variance.squareRoot()
    }
    
}
