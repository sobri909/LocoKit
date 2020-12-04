//
//  CwlMutex.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
//  Copyright © 2015 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

import Foundation

public protocol ScopedMutex {
	@discardableResult func sync<R>(execute work: () throws -> R) rethrows -> R
	@discardableResult func trySync<R>(execute work: () throws -> R) rethrows -> R?
}

public protocol RawMutex: ScopedMutex {
	associatedtype MutexPrimitive

	/// The raw primitive is exposed as an "unsafe" property for faster access in some cases
	var unsafeMutex: MutexPrimitive { get set }

	func unbalancedLock()
	func unbalancedTryLock() -> Bool
	func unbalancedUnlock()
}

public extension RawMutex {
    @discardableResult func sync<R>(execute work: () throws -> R) rethrows -> R {
		unbalancedLock()
		defer { unbalancedUnlock() }
		return try work()
	}
    @discardableResult func trySync<R>(execute work: () throws -> R) rethrows -> R? {
		guard unbalancedTryLock() else { return nil }
		defer { unbalancedUnlock() }
		return try work()
	}
}

public final class PThreadMutex: RawMutex {
    public typealias MutexPrimitive = pthread_mutex_t

	public enum PThreadMutexType {
		case normal // PTHREAD_MUTEX_NORMAL
		case recursive // PTHREAD_MUTEX_RECURSIVE
	}

    public var unsafeMutex = pthread_mutex_t()
	
	public init(type: PThreadMutexType = .normal) {
		var attr = pthread_mutexattr_t()
		guard pthread_mutexattr_init(&attr) == 0 else {
			preconditionFailure()
		}
		switch type {
		case .normal:
			pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_NORMAL)
		case .recursive:
			pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE)
		}
		guard pthread_mutex_init(&unsafeMutex, &attr) == 0 else {
			preconditionFailure()
		}
	}
	
	deinit { pthread_mutex_destroy(&unsafeMutex) }
	
    public func unbalancedLock() { pthread_mutex_lock(&unsafeMutex) }
    public func unbalancedTryLock() -> Bool { return pthread_mutex_trylock(&unsafeMutex) == 0 }
    public func unbalancedUnlock() { pthread_mutex_unlock(&unsafeMutex) }
}

public final class UnfairLock: RawMutex {
    public typealias MutexPrimitive = os_unfair_lock

    public init() {}
	
	/// Exposed as an "unsafe" property so non-scoped patterns can be implemented, if required.
    public var unsafeMutex = os_unfair_lock()
	
    public func unbalancedLock() { os_unfair_lock_lock(&unsafeMutex) }
    public func unbalancedTryLock() -> Bool { return os_unfair_lock_trylock(&unsafeMutex) }
    public func unbalancedUnlock() { os_unfair_lock_unlock(&unsafeMutex) }
}
