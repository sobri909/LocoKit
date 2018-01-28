//
//  MiscTools.swift
//  ArcKit
//
//  Created by Matt Greenfield on 4/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

public func onMain(_ closure: @escaping () -> ()) {
    if Thread.isMainThread {
        closure()
    } else {
        DispatchQueue.main.async(execute: closure)
    }
}

public extension Comparable {

    public mutating func clamp(min: Self, max: Self) {
        if self < min { self = min }
        if self > max { self = max }
    }

    public func clamped(min: Self, max: Self) -> Self {
        var result = self
        if result < min { result = min }
        if result > max { result = max }
        return result
    }

}

