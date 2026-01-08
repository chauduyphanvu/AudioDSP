import Foundation
import os

/// Thread-safe wrapper for parameters accessed from both UI and audio threads.
/// Uses os_unfair_lock for minimal overhead in real-time audio contexts.
/// Note: os_unfair_lock must have stable memory address - safe here because this is a final class.
final class ThreadSafeValue<T>: @unchecked Sendable {
    private var value: T
    private var lock = os_unfair_lock()  // Safe: final class has stable address

    init(_ initialValue: T) {
        self.value = initialValue
    }

    /// Read the current value with lock protection
    func read() -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }

    /// Write a new value with lock protection
    func write(_ newValue: T) {
        os_unfair_lock_lock(&lock)
        value = newValue
        os_unfair_lock_unlock(&lock)
    }

    /// Atomically read, transform, and write the value
    func modify(_ transform: (inout T) -> Void) {
        os_unfair_lock_lock(&lock)
        transform(&value)
        os_unfair_lock_unlock(&lock)
    }

    /// Atomically read, transform, write, and return a result
    func modifyAndReturn<R>(_ transform: (inout T) -> R) -> R {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return transform(&value)
    }

    /// Read multiple values atomically (use when you need to read several related values)
    func withLock<R>(_ body: (T) -> R) -> R {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body(value)
    }
}

/// Thread-safe boolean flag using os_unfair_lock for correct synchronization.
/// Safe for use between UI and audio threads with minimal overhead.
/// Note: os_unfair_lock must have stable memory address - safe here because this is a final class.
final class AtomicBool: @unchecked Sendable {
    private var storage: Bool
    private var lock = os_unfair_lock()  // Safe: final class has stable address

    init(_ initialValue: Bool) {
        storage = initialValue
    }

    var value: Bool {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return storage
        }
        set {
            os_unfair_lock_lock(&lock)
            storage = newValue
            os_unfair_lock_unlock(&lock)
        }
    }
}

/// Atomic UInt32 for bitmask operations (e.g., solo state for multiple bands).
/// Uses os_unfair_lock since bitmask operations need atomicity guarantees
/// that simple load/store cannot provide.
final class AtomicBitmask: @unchecked Sendable {
    private var storage: UInt32 = 0
    private var lock = os_unfair_lock()

    init(_ initialValue: UInt32 = 0) {
        storage = initialValue
    }

    var value: UInt32 {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storage
    }

    func setBit(_ index: Int, _ value: Bool) {
        os_unfair_lock_lock(&lock)
        let bit = UInt32(1 << index)
        if value {
            storage |= bit
        } else {
            storage &= ~bit
        }
        os_unfair_lock_unlock(&lock)
    }

    func isBitSet(_ index: Int) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (storage & UInt32(1 << index)) != 0
    }

    var isNonZero: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storage != 0
    }
}

/// Thread-safe flag for signaling state changes between threads (e.g., reset requests).
/// Uses os_unfair_lock for correct atomic test-and-set semantics.
/// Note: os_unfair_lock must have stable memory address - safe here because this is a final class.
final class AtomicFlag: @unchecked Sendable {
    private var isSet: Bool = false
    private var lock = os_unfair_lock()  // Safe: final class has stable address

    init() {}

    /// Set the flag (signal)
    func set() {
        os_unfair_lock_lock(&lock)
        isSet = true
        os_unfair_lock_unlock(&lock)
    }

    /// Atomically test and clear the flag. Returns true if the flag was set.
    func testAndClear() -> Bool {
        os_unfair_lock_lock(&lock)
        let wasSet = isSet
        isSet = false
        os_unfair_lock_unlock(&lock)
        return wasSet
    }
}
