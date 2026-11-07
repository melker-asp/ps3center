import Foundation

/// Finds webMAN on the Mac's /24 networks by asking each address for /cpursx_ps3 (read-only).
/// The networks are the Mac's cables, Internet Sharing and Wi-Fi (`MacNetwork`), cables first.
public enum Discovery {
    public static func localSubnets(_ interfaces: [MacInterface] = MacNetwork.interfaces()) -> [String] {
        var result: [String] = []
        for prefix in interfaces.compactMap(\.subnetPrefix) where !result.contains(prefix) {
            result.append(prefix)
        }
        return result
    }

    public static func scan(subnets: [String] = localSubnets()) async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            var found: [String] = []
            var launched = 0
            let addresses = subnets.flatMap { prefix in (1...254).map { "\(prefix).\($0)" } }
            var iterator = addresses.makeIterator()
            func launchNext() {
                guard let address = iterator.next() else { return }
                launched += 1
                group.addTask {
                    // The console answers slowly while a game runs, so allow a few seconds.
                    await WebMAN(host: address).isReachable(timeout: 4) ? address : nil
                }
            }
            for _ in 0..<64 { launchNext() }
            for await result in group {
                if let result { found.append(result) }
                launchNext()
            }
            return order(found, subnets: subnets)
        }
    }

    /// In the order of the subnets (cables first), then by number: "10.0.1.9" before "10.0.1.35".
    static func order(_ hosts: [String], subnets: [String]) -> [String] {
        func key(_ host: String) -> (Int, Int) {
            let subnet = subnets.firstIndex(of: MacNetwork.prefix(of: host)) ?? subnets.count
            return (subnet, Int(host.split(separator: ".").last ?? "") ?? 0)
        }
        return hosts.sorted { key($0) < key($1) }
    }
}
