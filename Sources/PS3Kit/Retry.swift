import Foundation
import os
import Network

/// Another try when the network fails during a transfer: the queue waits a little longer each
/// time and carries on where the console's file ends (SIZE, then APPE on the .part).
public enum RetryPolicy {
    /// Seconds before each new try: five more tries, about eight minutes in all.
    public static let delays: [UInt64] = [15, 30, 60, 120, 240]

    /// Errors from the network, not from the files or from what the console said.
    public static func isTransient(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let error = error as? PS3Error {
            switch error {
            case .unreachable, .timeout:
                return true
            case .ftp(let code, _):
                // Connection closed, data connection failed or aborted, local error on the console.
                return [421, 425, 426, 450, 451].contains(code)
            case .transferInterrupted:
                // The connection broke or closed, or the size did not match (FTPClient, Transfer).
                return true
            default:
                return false
            }
        }
        if error is NWError || error is POSIXError { return true }
        if let error = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(error.code)
        }
        return false
    }

    /// Runs `body`, and again after a transient failure, saying why and when on `events`.
    public static func run<T>(events: TransferHandler, _ body: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await body()
            } catch {
                // Stopping the queue cancels the connection too; that is not a failure to retry.
                guard !Task.isCancelled, isTransient(error), attempt < delays.count else { throw error }
                let delay = delays[attempt]
                attempt += 1
                events(.note("The connection broke (\(error.localizedDescription)). Trying again in \(delay) s, attempt \(attempt + 1) of \(delays.count + 1)."))
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }
}

/// How far each file got, so a new try can tell when the console threw away a half-sent file.
final class SentMemory: Sendable {
    private let sent = OSAllocatedUnfairLock(initialState: [String: Int64]())

    func note(_ remote: String, _ bytes: Int64) {
        sent.withLock { $0[remote] = max($0[remote] ?? 0, bytes) }
    }

    func bytes(_ remote: String) -> Int64 {
        sent.withLock { $0[remote] ?? 0 }
    }
}
