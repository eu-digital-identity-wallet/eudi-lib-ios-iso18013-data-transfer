import Foundation

/// Keeps synchronous transport access on the queue used by CoreBluetooth callbacks.
/// Execute inline on main to support nested access and synchronous delegate callbacks.
enum BleMainQueue {
    static func sync<T>(_ operation: () throws -> T) rethrows -> T {
        if Thread.isMainThread {
            return try operation()
        }
        return try DispatchQueue.main.sync(execute: operation)
    }
}
