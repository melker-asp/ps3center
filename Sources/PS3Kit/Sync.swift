import os

/// Lets exactly one caller through: the first `claim()` returns true, every later one false.
/// For callbacks that may race to finish the same continuation (a reply and its timeout).
public final class Once: Sendable {
    private let done = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    public func claim() -> Bool {
        done.withLock { done in
            if done { return false }
            done = true
            return true
        }
    }

    public var isClaimed: Bool { done.withLock { $0 } }
}
