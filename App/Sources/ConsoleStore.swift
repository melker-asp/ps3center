import Foundation
import Observation
import PS3Kit

/// Finds the console and polls its status, like `ps3 status --watch`.
@MainActor
@Observable
final class ConsoleStore {
    enum Connection: Equatable {
        case connecting
        case scanning
        case online
        case offline(String)
    }

    private(set) var connection: Connection = .connecting
    private(set) var host: String?
    private(set) var snapshot: ConsoleSnapshot?
    private(set) var latency: TimeInterval?
    private(set) var cpuHistory: [Double] = []
    private(set) var rsxHistory: [Double] = []
    private(set) var fanHistory: [Double] = []
    private(set) var history: [OperationLog.Entry] = []

    let interval: TimeInterval = 3
    private let historyLength = 40
    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.run() }
    }

    func retry() {
        pollTask?.cancel()
        pollTask = nil
        connection = .connecting
        start()
    }

    private func run() async {
        while !Task.isCancelled {
            if host == nil {
                do {
                    host = try await ConsoleLocator.resolve { event in
                        if case .scanning = event { Task { @MainActor [weak self] in self?.connection = .scanning } }
                    }
                } catch {
                    connection = .offline(error.localizedDescription)
                    try? await Task.sleep(for: .seconds(8))
                    continue
                }
            }
            guard let host else { continue }
            let started = Date()
            do {
                let next = try await WebMAN(host: host).snapshot()
                latency = Date().timeIntervalSince(started)
                record(next)
                connection = .online
            } catch {
                connection = .offline(error.localizedDescription)
                self.host = nil  // look again next round; the IP may have changed
            }
            history = OperationLog.read(limit: 12).reversed()
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    /// Fixture mode (`PS3CENTER_FIXTURES=1`): canned data, no network.
    func loadFixture(_ snapshot: ConsoleSnapshot = Fixtures.snapshot) {
        pollTask?.cancel()
        pollTask = nil
        host = snapshot.host
        self.snapshot = snapshot
        latency = 0.18
        cpuHistory = Fixtures.series(around: Double(snapshot.cpuTemp ?? 60))
        rsxHistory = Fixtures.series(around: Double(snapshot.rsxTemp ?? 65))
        fanHistory = Fixtures.series(around: Double(snapshot.fanPercent ?? 30), swing: 2)
        history = Fixtures.history
        connection = .online
    }

    private func record(_ next: ConsoleSnapshot) {
        snapshot = next
        func push(_ value: Int?, into array: inout [Double]) {
            guard let value else { return }
            array.append(Double(value))
            if array.count > historyLength { array.removeFirst(array.count - historyLength) }
        }
        push(next.cpuTemp, into: &cpuHistory)
        push(next.rsxTemp, into: &rsxHistory)
        push(next.fanPercent, into: &fanHistory)
    }
}
