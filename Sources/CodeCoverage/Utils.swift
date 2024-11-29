/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation

final class UnfairLock {
    private let _lock: os_unfair_lock_t
    
    init() {
        _lock = .allocate(capacity: 1)
        _lock.initialize(to: .init())
    }
    
    deinit {
        _lock.deinitialize(count: 1)
        _lock.deallocate()
    }
    
    func lock() {
        os_unfair_lock_lock(_lock)
    }
    
    func unlock() {
        os_unfair_lock_unlock(_lock)
    }
    
    func whileLocked<T>(_ action: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return try action()
    }
}

struct Weak<T: AnyObject> {
    weak var value: T?
    
    init(_ value: T? = nil) {
        self.value = value
    }
}

extension Array where Element: StringProtocol {
    public func withCStringsArray<R>(_ body: ([UnsafePointer<CChar>]) throws -> R) rethrows -> R {
        let utf8s = self.map { $0.utf8 }
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: utf8s.reduce(0) { $0 + $1.count + 1 })
        defer { buffer.deallocate() }
        var start = buffer
        let ptrs = utf8s.map {
            var str = $0.withContiguousStorageIfAvailable {
                $0.withMemoryRebound(to: CChar.self) {
                    start.initialize(from: $0.baseAddress!, count: $0.count)
                    return UnsafePointer(start)
                }
            }
            if str != nil {
                start += $0.count
            } else {
                str = UnsafePointer(start)
                $0.forEach {
                    start.initialize(to: CChar(bitPattern: $0))
                    start += 1
                }
            }
            start.initialize(to: 0)
            start += 1
            // it's safe to unwrap.
            // It's initialized at this moment
            return str!
        }
        return try body(ptrs)
    }
}
