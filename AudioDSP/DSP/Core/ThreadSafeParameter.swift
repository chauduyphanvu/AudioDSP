import Foundation
import os

/// Thread-safe wrapper for parameters accessed from both UI and audio threads.
/// Uses os_unfair_lock for minimal overhead in real-time audio contexts.
final class ThreadSafeValue<T>: @unchecked Sendable {
    private var value: T
    private var lock = os_unfair_lock()

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

/// Atomic boolean flag using lock-free operations for ultra-low-overhead audio thread access.
/// Preferred over ThreadSafeValue<Bool> when the flag is read on every sample.
/// Uses Swift's native atomic support via UnsafeAtomic pattern with memory ordering.
final class AtomicBool: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Int32>

    init(_ initialValue: Bool) {
        storage = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        storage.initialize(to: initialValue ? 1 : 0)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    var value: Bool {
        get {
            // Atomic load with acquire semantics
            // On ARM64, this compiles to LDAR instruction
            // On x86, plain load has acquire semantics
            return withUnsafeMutablePointer(to: &storage.pointee) { ptr in
                // Use memory barrier for correct ordering on ARM64
                OSMemoryBarrier()
                return ptr.pointee != 0
            }
        }
        set {
            // Atomic store with release semantics
            withUnsafeMutablePointer(to: &storage.pointee) { ptr in
                ptr.pointee = newValue ? 1 : 0
                OSMemoryBarrier()
            }
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

/// Atomic flag for signaling state changes between threads (e.g., reset requests).
/// Implements test-and-set semantics for single-producer, single-consumer scenarios.
final class AtomicFlag: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Int32>

    init() {
        storage = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        storage.initialize(to: 0)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    /// Set the flag (signal)
    func set() {
        withUnsafeMutablePointer(to: &storage.pointee) { ptr in
            ptr.pointee = 1
            OSMemoryBarrier()
        }
    }

    /// Test and clear the flag. Returns true if the flag was set.
    /// Uses memory barrier to ensure visibility across threads.
    func testAndClear() -> Bool {
        OSMemoryBarrier()
        let wasSet = storage.pointee != 0
        if wasSet {
            storage.pointee = 0
            OSMemoryBarrier()
        }
        return wasSet
    }
}
