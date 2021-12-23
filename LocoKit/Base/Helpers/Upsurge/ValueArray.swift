// Copyright © 2015 Venture Media Labs.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Accelerate

/// A `ValueArray` is similar to an `Array` but it's a `class` instead of a `struct` and it has a fixed size. As opposed to an `Array`, assigning a `ValueArray` to a new variable will not create a copy, it only creates a new reference. If any reference is modified all other references will reflect the change. To copy a `ValueArray` you have to explicitly call `copy()`.
final class ValueArray<Element: Value>: LinearType, CustomStringConvertible, Equatable {
    typealias Index = Int
    typealias IndexDistance = Int

    var mutablePointer: UnsafeMutablePointer<Element>
    var capacity: IndexDistance
    var count: IndexDistance

    var startIndex: Index {
        return 0
    }

    var endIndex: Index {
        return count
    }

    var step: IndexDistance {
        return 1
    }

    func withUnsafePointer<R>(_ body: (UnsafePointer<Element>) throws -> R) rethrows -> R {
        return try body(mutablePointer)
    }

    var pointer: UnsafePointer<Element> {
        return UnsafePointer(mutablePointer)
    }

    /// Construct an uninitialized ValueArray with the given capacity
    required init(capacity: IndexDistance) {
        mutablePointer = UnsafeMutablePointer.allocate(capacity: capacity)
        self.capacity = capacity
        self.count = 0
    }

    deinit {
        mutablePointer.deallocate()
    }

    subscript(index: Index) -> Element {
        get {
            assert(indexIsValid(index))
            return pointer[index]
        }
        set {
            assert(indexIsValid(index))
            mutablePointer[index] = newValue
        }
    }

    subscript(intervals: [Int]) -> Element {
        get {
            assert(intervals.count == 1)
            return self[intervals[0]]
        }
        set {
            assert(intervals.count == 1)
            self[intervals[0]] = newValue
        }
    }

    func append(_ newElement: Element) {
        precondition(count + 1 <= capacity)
        mutablePointer[count] = newElement
        count += 1
    }

    func append<S: Sequence>(contentsOf newElements: S) where S.Iterator.Element == Element {
        let a = Array(newElements)
        precondition(count + a.count <= capacity)
        let endPointer = mutablePointer + count
        _ = UnsafeMutableBufferPointer(start: endPointer, count: capacity - count).initialize(from: a)
        count += a.count
    }

    func replaceSubrange<C: Collection>(_ subrange: Range<Index>, with newElements: C) where C.Iterator.Element == Element {
        assert(subrange.lowerBound >= startIndex && subrange.upperBound <= endIndex)
        _ = UnsafeMutableBufferPointer(start: mutablePointer + subrange.lowerBound, count: capacity - subrange.lowerBound).initialize(from: newElements)
    }

    // MARK: - Equatable

    static func == (lhs: ValueArray, rhs: ValueArray) -> Bool {
        return lhs.count == rhs.count && lhs.elementsEqual(rhs)
    }
}
