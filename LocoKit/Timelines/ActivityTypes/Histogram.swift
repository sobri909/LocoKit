//
//  Histogram.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 1/05/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import Upsurge

open class Histogram: CustomStringConvertible {
   
    public let bins: [Int]
    public let binWidth: Double
    public let range: (min: Double, max: Double)
    public let pseudoCount: Int
    
    public static let defaultPseudoCount = 1
    
    public var name: String?
    public var binName: String?
    public var binValueName: String?
    public var binValueNamePlural: String?
    public var printFormat: String?
    public var printModifier: Double?
    
    public var binCount: Int { return bins.count }

    public convenience init(values: [Double], maxBins: Int? = nil, minBoundary: Double? = nil, maxBoundary: Double? = nil,
                     pseudoCount: Int = Histogram.defaultPseudoCount, trimOutliers: Bool = false,
                     snapToBoundaries: Bool = false, name: String? = nil,
                     printFormat: String? = nil, printModifier: Double? = nil) {

        let mean = Upsurge.mean(values)
        let sd = Upsurge.std(values)
        
        var filteredValues = values
        
        if trimOutliers {
            let trimRange = (min: mean - (sd * 4), max: mean + (sd * 4))
            filteredValues = filteredValues.filter { $0 >= trimRange.min && $0 <= trimRange.max }
        }
        
        if let minBoundary = minBoundary {
            filteredValues = filteredValues.filter { $0 >= minBoundary }
        }
        
        if let maxBoundary = maxBoundary {
            filteredValues = filteredValues.filter { $0 <= maxBoundary }
        }
        
        guard let minValue = filteredValues.min(), let maxValue = filteredValues.max() else {
            self.init(bins: [pseudoCount], range: (min: 0, max: 0), pseudoCount: pseudoCount)
            return
        }
        
        var range = (min: minValue, max: maxValue)

        // snap range to boundaries if min/max values are close enough
        if snapToBoundaries, let minBoundary = minBoundary, let maxBoundary = maxBoundary {
            let boundarySpread = maxBoundary - minBoundary
            if minValue - minBoundary < boundarySpread * 0.02 { range.min = minBoundary }
            if maxBoundary - maxValue < boundarySpread * 0.02 { range.max = maxBoundary }
        }
        
        guard range.min < range.max else {
            self.init(bins: [pseudoCount + 1], range: range, pseudoCount: pseudoCount)
            return
        }
        
        var binCount = Histogram.numberOfBins(filteredValues)
        if let maxBins = maxBins, binCount > maxBins {
            binCount = maxBins
        }
        let binWidth = (range.max - range.min) / Double(binCount)
        
        var bins = [Int](repeating: pseudoCount, count: binCount)
        for value in filteredValues {
            let bucketDouble = (value - range.min) / binWidth
            var bucket = Int(bucketDouble)
            
            // cope with values just over top of range (ie float inaccuracies)
            if bucket == binCount {
                let overage = bucketDouble - Double(binCount)
                if overage < 0.001 {
                    bucket = binCount - 1
                }
            }
            
            guard bucket >= 0 && bucket < binCount else {
                continue
            }
            
            bins[bucket] += 1
        }
        
        self.init(bins: bins, range: range, pseudoCount: pseudoCount)
        
        self.name = name
        self.printFormat = printFormat
        self.printModifier = printModifier
    }

    // used for loading from serialised strings
    public convenience init?(string: String) {
        let lines = string.split(separator: ";", omittingEmptySubsequences: false)
        
        guard lines.count > 2 else {
            return nil
        }
        
        let sizeLine = lines[0].split(separator: ",", omittingEmptySubsequences: false)
        guard let binCount = Int(sizeLine[0]), let pseudoCount = Int(sizeLine[1]) else {
            os_log("BIN COUNTS FAIL")
            return nil
        }
        
        let rangeLine = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        guard let rangeMin = Double(rangeLine[0]), let rangeMax = Double(rangeLine[1]) else {
            os_log("RANGE FAIL")
            return nil
        }
        
        let range = (min: rangeMin, max: rangeMax)
        
        var bins = [Int](repeating: pseudoCount, count: binCount)
        
        let binLines = lines.suffix(from: 2)
        for binLine in binLines {
            let bits = binLine.split(separator: ",", omittingEmptySubsequences: false)
            guard bits.count == 2 else {
                continue
            }
            
            guard let bin = Int(bits[0]), let value = Int(bits[1]) else {
                os_log("Histogram bin fail: %@", bits)
                return nil
            }
            
            bins[bin] = value
        }
        
        self.init(bins: bins, range: range, pseudoCount: pseudoCount)
    }
    
    public init(bins: [Int], range: (min: Double, max: Double), pseudoCount: Int) {
        self.bins = bins
        self.range = range
        self.binWidth = (range.max - range.min) / Double(bins.count)
        self.pseudoCount = pseudoCount
    }

    public func binFor(_ value: Double, numberOfBins: Int, range: (min: Double, max: Double)) -> Int? {
        let binWidth = (range.max - range.min) / Double(numberOfBins)
        let maxBucket = Double(numberOfBins - 1)
        
        let bucket = (value - range.min) / binWidth
        
        // cope with out of range values
        if floor(bucket) > maxBucket {
            if bucket - Double(numberOfBins) < 0.001 { // return maxBucket for values ~equal to max
                return Int(maxBucket)
            } else {
                os_log("value: %f binWidth: %f maxBucket: %f bucket: %f range: %f - %f",
                       value, binWidth, maxBucket, bucket, range.min, range.max)
                return nil
            }
        }
        
        return Int(bucket)
    }
    
    public var isEmpty: Bool {
        return bins.count == 1 && bins[0] == 0
    }
    
    public func probabilityFor(_ value: Double) -> Double {
        guard let max = bins.max() else {
            return 0
        }
       
        // shouldn't be possible. but... 
        guard !binWidth.isNaN else {
            return 0
        }
        
        // single bin histograms result in binary 0 or 1 scores
        if bins.count == 1 {
            return value == range.min ? 1 : 0
        }
        
        let bin: Int
        if value == range.max {
            bin = bins.count - 1
        } else {
            let binDouble = floor((value - range.min) / binWidth)
            
            if binDouble > Double(bins.count - 1) {
                return 0
            }
            
            guard !binDouble.isNaN && binDouble > Double(Int.min) && binDouble < Double(Int.max) else {
                return 0
            }
            
            bin = binWidth > 0 ? Int(binDouble) : 0
        }
        
        guard bin >= 0 && bin < bins.count else {
            return 0
        }
        
        return (Double(bins[bin]) / Double(max)).clamped(min: 0, max: 1)
    }
   
    public func percentOfTotalFor(bin: Int) -> Double? {
        guard bin < bins.count else {
            return nil
        }
        
        let sum = bins.reduce(0, +)
        
        guard sum > 0 else {
            return nil
        }

        return Double(bins[bin]) / Double(sum)
    }
    
    public func bottomFor(bin: Int) -> Double {
        return range.min + (binWidth * Double(bin))
    }
    
    public func middleFor(bin: Int) -> Double {
        let valueBottom = bottomFor(bin: bin)
        return valueBottom + (binWidth * 0.5)
    }
    
    public func topFor(bin: Int) -> Double {
        let valueBottom = bottomFor(bin: bin)
        return valueBottom + binWidth
    }
    
    public func formattedStringFor(bin: Int) -> String {
        let format = printFormat ?? "%.2f"
        let modifier = printModifier ?? 1.0
        
        return String(format: format, middleFor(bin: bin) * modifier)
    }

    public var peakIndexes: [Int]? {
        guard let maxBin = bins.max(), maxBin > 0 else {
            return nil
        }
        
        // find all the max bins
        var peakIndexes: [Int] = []
        for (i, binValue) in bins.enumerated() {
            if binValue == maxBin {
                peakIndexes.append(i)
            }
        }
        
        return peakIndexes
    }
    
    // the first (and hopefully the only) peak index
    public var peakIndex: Int? {
        guard let peakIndexes = peakIndexes, peakIndexes.count == 1 else {
            return nil
        }
        
        return peakIndexes.first
    }

    public var peakRanges: [(from: Double, to: Double)]? {
        guard let peakIndexes = peakIndexes else {
            return nil
        }
        
        var previousBucket: Int?
        var currentRange: (from: Double, to: Double)?
        var ranges: [(from: Double, to: Double)] = []
        
        for bucket in peakIndexes {
            
            // add previous range if non sequential
            if let previous = previousBucket, bucket != previous + 1, let range = currentRange {
                ranges.append(range)
                currentRange = nil
            }
           
            let bottom = range.min + (binWidth * Double(bucket))
            let top = bottom + binWidth
           
            if currentRange == nil {
                currentRange = (from: bottom, to: top)
                
            } else {
                currentRange!.to = top
            }
            
            previousBucket = bucket
        }
       
        // add the last one
        if let range = currentRange {
            ranges.append(range)
        }
        
        return ranges
    }

    public static func numberOfBins(_ metric: [Double], defaultBins: Int = 10) -> Int {
        let h = binWidth(metric), ulim = max(metric), llim = min(metric)
        if h <= (ulim - llim) / Double(metric.count) {
            return defaultBins
        }
        return Int(ceil((ulim - llim) / h))
    }
    
    static func binWidth(_ metric: [Double]) -> Double {
        return 2.0 * iqr(metric) * pow(Double(metric.count), -1.0 / 3.0)
    }
    
    static func iqr(_ metric: [Double]) -> Double {
        let sorted = metric.sorted { $0 < $1 }
        let q1 = sorted[Int(floor(Double(sorted.count) / 4.0))]
        let q3 = sorted[Int(floor(Double(sorted.count) * 3.0 / 4.0))]
        return q3 - q1
    }

    // binsCount,pseudoCount;
    // range.min,range.max;
    // binIndex,value; ...

    public var serialised: String {
        var result = "\(bins.count),\(pseudoCount);"
        result += "\(range.min),\(range.max);"
        
        for (binIndex, value) in bins.enumerated() {
            if value > pseudoCount {
                result += "\(binIndex),\(value);"
            }
        }
        
        return result
    }

    // MARK: - CustomStringConvertible
    
    public var description: String {
        guard let max = bins.max(), max > 0 else {
            return "\(name ?? "UNNAMED"): Nada."
        }
        
        var result = "\(name ?? "UNNAMED") (pseudoCount: \(pseudoCount))\n"
        
        for bin in 0 ..< binCount {
            let binText = formattedStringFor(bin: bin)
            
            let lengthPct = Double(bins[bin]) / Double(max)
            let barWidth = Int(130.0 * lengthPct)
            
            let bar = "".padding(toLength: barWidth, withPad: "+", startingAt: 0)
            let bucketString = binText + ": " + bar
            
            result += bucketString + "\n"
        }
        
        return result
    }
    
}
