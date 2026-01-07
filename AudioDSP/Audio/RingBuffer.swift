import Foundation
import os

/// Thread-safe lock-free ring buffer for audio transport
final class RingBuffer<T>: @unchecked Sendable {
    private var buffer: [T]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private let capacity: Int
    private let lock = os_unfair_lock_s()
    private var lockPointer: UnsafeMutablePointer<os_unfair_lock_s>

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = []
        self.lockPointer = UnsafeMutablePointer<os_unfair_lock_s>.allocate(capacity: 1)
        self.lockPointer.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lockPointer.deinitialize(count: 1)
        lockPointer.deallocate()
    }

    func push(_ value: T) {
        os_unfair_lock_lock(lockPointer)
        defer { os_unfair_lock_unlock(lockPointer) }

        if buffer.count < capacity {
            buffer.append(value)
        } else {
            buffer[writeIndex] = value
        }
        writeIndex = (writeIndex + 1) % capacity
    }

    func pop() -> T? {
        os_unfair_lock_lock(lockPointer)
        defer { os_unfair_lock_unlock(lockPointer) }

        guard !buffer.isEmpty else { return nil }
        guard readIndex != writeIndex || buffer.count == capacity else { return nil }

        let value = buffer[readIndex]
        readIndex = (readIndex + 1) % capacity
        return value
    }

    var count: Int {
        os_unfair_lock_lock(lockPointer)
        defer { os_unfair_lock_unlock(lockPointer) }

        if writeIndex >= readIndex {
            return writeIndex - readIndex
        }
        return capacity - readIndex + writeIndex
    }

    func clear() {
        os_unfair_lock_lock(lockPointer)
        defer { os_unfair_lock_unlock(lockPointer) }

        buffer.removeAll()
        writeIndex = 0
        readIndex = 0
    }
}
