import Darwin
import Foundation

/// Finds webMAN on the local /24 network by asking each address for /cpursx_ps3 (read-only).
public enum Discovery {
    public static func localSubnets() -> [String] {
        var result: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en"), let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            let octets = ip.split(separator: ".")
            guard octets.count == 4, !ip.hasPrefix("169.254") else { continue }
            let prefix = octets.prefix(3).joined(separator: ".")
            if !result.contains(prefix) { result.append(prefix) }
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
            return found.sorted()
        }
    }
}
