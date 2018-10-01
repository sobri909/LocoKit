//
//  Matrix.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 7/05/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import CoreLocation

open class CoordinatesMatrix: CustomStringConvertible {
    
    public static let minimumProbability = 0.001
    
    public let bins: [[UInt16]] // [lat][long]
    public let lngBinWidth: Double
    public let latBinWidth: Double
    public let lngRange: (min: Double, max: Double)
    public let latRange: (min: Double, max: Double)
    public let pseudoCount: UInt16
   
    // used for loading from serialised strings
    public convenience init?(string: String) {
        let lines = string.split(separator: ";", omittingEmptySubsequences: false)
        
        guard lines.count > 3 else {
            return nil
        }

        let sizeLine = lines[0].split(separator: ",", omittingEmptySubsequences: false)
        guard let latBinCount = Int(sizeLine[0]), let lngBinCount = Int(sizeLine[1]), let pseudoCount = UInt16(sizeLine[2]) else {
            os_log("BIN COUNTS FAIL")
            return nil
        }
        
        let latRangeLine = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        guard let latMin = Double(latRangeLine[0]), let latMax = Double(latRangeLine[1]) else {
            os_log("LAT RANGE FAIL")
            return nil
        }
        
        let lngRangeLine = lines[2].split(separator: ",", omittingEmptySubsequences: false)
        guard let lngMin = Double(lngRangeLine[0]), let lngMax = Double(lngRangeLine[1]) else {
            os_log("LNG RANGE FAIL")
            return nil
        }
        
        let latRange = (min: latMin, max: latMax)
        let lngRange = (min: lngMin, max: lngMax)
        let lngBinWidth = (lngRange.max - lngRange.min) / Double(lngBinCount)
        let latBinWidth = (latRange.max - latRange.min) / Double(latBinCount)
        
        var bins = Array(repeating: Array<UInt16>(repeating: pseudoCount, count: lngBinCount), count: latBinCount)
        
        let binLines = lines.suffix(from: 3)
        for binLine in binLines {
            let bits = binLine.split(separator: ",", omittingEmptySubsequences: false)
            guard bits.count == 3 else {
                continue
            }
            
            guard let latBin = Int(bits[0]), let lngBin = Int(bits[1]), var value = Int(bits[2]) else {
                os_log("CoordinatesMatrix bin fail: %@", bits)
                return nil
            }
           
            // fix overflows
            if value > Int(UInt16.max) {
                value = Int(UInt16.max)
            }
            
            bins[latBin][lngBin] = UInt16(value)
        }
        
        self.init(bins: bins, latBinWidth: latBinWidth, lngBinWidth: lngBinWidth, latRange: latRange,
                  lngRange: lngRange, pseudoCount: pseudoCount)
    }
    
    // everything pre determined except which bins the coordinates go in. ActivityType uses this directly
    public convenience init(coordinates: [CLLocationCoordinate2D], latBinCount: Int, lngBinCount: Int,
                     latRange: (min: Double, max: Double), lngRange: (min: Double, max: Double),
                     pseudoCount: UInt16) {
        let latBinWidth = (latRange.max - latRange.min) / Double(latBinCount)
        let lngBinWidth = (lngRange.max - lngRange.min) / Double(lngBinCount)
        
        // pre fill the bins with pseudo count
        var bins = Array(repeating: Array<UInt16>(repeating: pseudoCount, count: lngBinCount), count: latBinCount)
        
        // proper fill the bins
        for coordinate in coordinates {
            let lngBin = Int((coordinate.longitude - lngRange.min) / lngBinWidth)
            let latBin = Int((coordinate.latitude - latRange.min) / latBinWidth)
            
            guard latBin >= 0 && latBin < latBinCount && lngBin >= 0 && lngBin < lngBinCount else {
                continue
            }
            
            let existingValue = bins[latBin][lngBin]
            if existingValue < UInt16.max {
                bins[latBin][lngBin] = existingValue + 1
            }
        }
        
        self.init(bins: bins, latBinWidth: latBinWidth, lngBinWidth: lngBinWidth, latRange: latRange,
                  lngRange: lngRange, pseudoCount: pseudoCount)
    }
    
    public init(bins: [[UInt16]], latBinWidth: Double, lngBinWidth: Double, latRange: (min: Double, max: Double),
         lngRange: (min: Double, max: Double), pseudoCount: UInt16) {
        self.bins = bins
        self.lngRange = lngRange
        self.latRange = latRange
        self.lngBinWidth = lngBinWidth
        self.latBinWidth = latBinWidth
        self.pseudoCount = pseudoCount
    }

    lazy var matrixMax: UInt16 = {
        var matrixMax: UInt16 = 0
        for bin in bins {
            if let rowMax = bin.max() {
                matrixMax = max(rowMax, UInt16(matrixMax))
            }
        }
        return matrixMax
    }()

    // MARK: - Scores

    public func probabilityFor(_ coordinate: CLLocationCoordinate2D, maxThreshold: Int? = nil) -> Double {
        guard latBinWidth > 0 && lngBinWidth > 0 else { return 0 }
        guard matrixMax > 0 else { return 0 }

        var trimmedMatrixMax = matrixMax

        if var maxThreshold = maxThreshold {
            // fix overflows
            if maxThreshold > Int(UInt16.max) {
                maxThreshold = Int(UInt16.max)
            }
            
            trimmedMatrixMax.clamp(min: 0, max: UInt16(maxThreshold))
        }
        
        let latBin = Int((coordinate.latitude - latRange.min) / latBinWidth)
        let lngBin = Int((coordinate.longitude - lngRange.min) / lngBinWidth)
        
        guard latBin >= 0 && latBin < bins.count else {
            return (Double(pseudoCount) / Double(trimmedMatrixMax)).clamped(min: 0, max: 1)
        }
        guard lngBin >= 0 && lngBin < bins[0].count else {
            return (Double(pseudoCount) / Double(trimmedMatrixMax)).clamped(min: 0, max: 1)
        }
        
        let binCount = bins[latBin][lngBin]
        
        return (Double(binCount) / Double(trimmedMatrixMax)).clamped(min: 0, max: 1)
    }
    
    // MARK: - Serialisation
   
    // xCount,yCount,pseudoCount;
    // xMin,xMax;
    // yMin,yMax;
    // x,y,value; ...
    
    public var serialised: String {
        var result = "\(bins.count),\(bins[0].count),\(pseudoCount);"
        result += "\(latRange.min),\(latRange.max);"
        result += "\(lngRange.min),\(lngRange.max);"
        
        for (x, bin) in bins.enumerated() {
            for (y, value) in bin.enumerated() {
                if value > pseudoCount {
                    result += "\(x),\(y),\(value);"
                }
            }
        }
        
        return result
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        var result = ""
        
        result += "lngRange: \(lngRange)\n"
        result += "latRange: \(latRange)\n"
        
        var matrixMax: UInt16 = 0
        for lngBins in bins {
            if let maxBin = lngBins.max(), maxBin > matrixMax {
                matrixMax = maxBin
            }
        }
       
        // TODO: this doesn't take into account the maxThreshold (eg 10 events per D2 bin)
        for lngBins in bins.reversed() {
            var yString = ""
            for value in lngBins {
                let pctOfMax = Double(value) / Double(matrixMax)
                if value <= pseudoCount {
                    yString += "-"
                } else if pctOfMax >= 1 {
                    yString += "X"
                } else {
                    yString += String(format: "%1.0f", pctOfMax * 10)
                }
            }
            
            result += yString + "\n"
            
        }
        
        return result
    }

}
