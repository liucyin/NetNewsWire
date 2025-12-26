//
//  Mutex.swift
//  RSCore

import Foundation

/// A simple mutual exclusion primitive that supports iOS 17.
///
/// This mirrors the API surface used from `Synchronization.Mutex` (iOS 18+),
/// but is implemented with `NSLock` so we can keep the deployment target at iOS 17.
public final class Mutex<Value>: @unchecked Sendable {
	private let lock = NSLock()
	private var value: Value

	public init(_ value: Value) {
		self.value = value
	}

	@discardableResult
	public func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
		lock.lock()
		defer { lock.unlock() }
		return try body(&value)
	}
}
