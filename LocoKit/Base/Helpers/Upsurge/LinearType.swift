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

/// The `LinearType` protocol should be implemented by any collection that stores its values in a contiguous memory block. This is the building block for one-dimensional operations that are single-instruction, multiple-data (SIMD).
protocol LinearType: CustomStringConvertible, CustomDebugStringConvertible, BidirectionalCollection {
  
    associatedtype Element
  
    var count: Int { get }
  
    /// Call `body(pointer)` with the pointer to the beginning of the memory block
    func withUnsafePointer<R>(_ body: (UnsafePointer<Element>) throws -> R) rethrows -> R

    /// The index of the first valid element
    var startIndex: Int { get }

    /// One past the end of the data
    var endIndex: Int { get }

    /// The step size between valid elements
    var step: Int { get }

    subscript(position: Int) -> Element { get }
}

extension LinearType {
    var dimensions: [Int] {
        return [count]
    }

    func index(after i: Int) -> Int {
        return i + 1
    }

    func index(before i: Int) -> Int {
        return i - 1
    }

    func formIndex(after i: inout Int) {
        i += 1
    }

    var description: String {
        return "[\(map { "\($0)" }.joined(separator: ", "))]"
    }

    var debugDescription: String {
        return description
    }
}
