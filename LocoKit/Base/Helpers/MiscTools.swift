//
//  MiscTools.swift
//  LocoKit
//
//  Created by Matt Greenfield on 4/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Foundation

public func onMain(_ closure: @escaping () -> ()) {
    if Thread.isMainThread {
        closure()
    } else {
        DispatchQueue.main.async(execute: closure)
    }
}

public extension Comparable {
    mutating func clamp(min: Self, max: Self) {
        if self < min { self = min }
        if self > max { self = max }
    }
    func clamped(min: Self, max: Self) -> Self {
        var result = self
        if result < min { result = min }
        if result > max { result = max }
        return result
    }
}

public extension UUID {
    var shortString: String {
        return String(uuidString.split(separator: "-")[0])
    }
}

public extension DateInterval {
    var middle: Date {
        return start + duration * 0.5
    }

    func contains(_ other: DateInterval) -> Bool {
        if let overlap = intersection(with: other), overlap == other {
            return true
        }
        return false
    }
    
    var containsNow: Bool {
        return contains(Date())
    }
}

public extension Date {
    func isSameDayAs(_ date: Date) -> Bool { return Calendar.current.isDate(date, inSameDayAs: self) }
    func isSameMonthAs(_ date: Date) -> Bool { return Calendar.current.isDate(date, equalTo: self, toGranularity: .month) }
}

public extension TimeInterval {
    static var oneMinute: TimeInterval { return 60 }
    static var oneHour: TimeInterval { return oneMinute * 60 }
    static var oneDay: TimeInterval { return oneHour * 24 }
    static var oneWeek: TimeInterval { return oneDay * 7 }
    static var oneMonth: TimeInterval { return oneDay * 30 }
    static var oneYear: TimeInterval { return oneDay * 365 }
}

