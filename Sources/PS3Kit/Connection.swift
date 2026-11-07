import Darwin
import Foundation
import SystemConfiguration

// MARK: The Mac's connections

/// One of the Mac's network connections, as the connection sheet and `ps3 connection` show it.
public struct MacInterface: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case wifi
        case ethernet
        /// macOS Internet Sharing (bridge100 …): the Mac hands out addresses and internet.
        case sharing
    }

    public var id: String { name }
    /// The BSD name, "en7".
    public let name: String
    /// What System Settings calls it: "Wi-Fi", "USB 10/100/1000 LAN", "Internet Sharing".
    public let label: String
    public let kind: Kind
    /// The IPv4 address; nil without one, or with only a 169.254 address the Mac gave itself.
    public var address: String?
    public var netmask: String?
    /// Bits per second on a cable that has a link (`ifi_baudrate`); nil for Wi-Fi.
    public var linkSpeed: UInt64?
    /// Whether macOS knows a router on this connection (from DHCP or set by hand).
    public var hasRouter: Bool

    public init(name: String, label: String, kind: Kind, address: String? = nil, netmask: String? = nil,
                linkSpeed: UInt64? = nil, hasRouter: Bool = false) {
        self.name = name
        self.label = label
        self.kind = kind
        self.address = address
        self.netmask = netmask
        self.linkSpeed = linkSpeed
        self.hasRouter = hasRouter
    }

    /// "192.168.2": Discovery searches this /24.
    public var subnetPrefix: String? {
        address.map(MacNetwork.prefix(of:))
    }

    /// A cable below gigabit. The PS3 and the Mac's adapter both have gigabit ports, so 100 Mbit
    /// almost always means a cable with only two working pairs (an old or flat one).
    public var isSlowLink: Bool {
        guard kind == .ethernet, let speed = linkSpeed else { return false }
        return speed < 1_000_000_000
    }

    /// "100 Mbit", "1 Gbit"
    public var linkSpeedLabel: String? {
        guard let speed = linkSpeed else { return nil }
        if speed >= 1_000_000_000 {
            let gbit = Double(speed) / 1e9
            return gbit == gbit.rounded() ? "\(Int(gbit)) Gbit" : String(format: "%.1f Gbit", gbit)
        }
        return "\(speed / 1_000_000) Mbit"
    }
}

/// Reads the Mac's connections: addresses from getifaddrs, names and kinds from
/// SystemConfiguration, routers from the dynamic store. Nothing here changes the Mac.
public enum MacNetwork {
    /// What getifaddrs says about one interface.
    struct Record: Equatable {
        var address: String?
        var netmask: String?
        var baud: UInt64 = 0
    }

    /// What System Settings knows about one interface.
    struct Service: Equatable {
        /// `kSCNetworkInterfaceType…`: "IEEE80211", "Ethernet", "Bridge" …
        let type: String
        let label: String
    }

    public static func interfaces() -> [MacInterface] {
        combine(records: readRecords(), services: readServices(), routers: readRouters())
    }

    /// The Mac's IPv4 addresses, for webMAN's settings and the game server.
    public static func addresses(_ interfaces: [MacInterface] = interfaces()) -> [String] {
        var result: [String] = []
        for address in interfaces.compactMap(\.address) where !result.contains(address) {
            result.append(address)
        }
        return result
    }

    static func prefix(of address: String) -> String {
        address.split(separator: ".").prefix(3).joined(separator: ".")
    }

    /// "192.168.2.2" yes; "192.168.2", "ps3.local" and " 10.0.0.1" no.
    public static func isIPv4(_ text: String) -> Bool {
        var address = in_addr()
        return inet_pton(AF_INET, text, &address) == 1
    }

    /// Kept apart from the system calls so the rules can be tested with made-up interfaces.
    static func combine(records: [String: Record], services: [String: Service], routers: Set<String>) -> [MacInterface] {
        var result: [MacInterface] = []
        for (name, record) in records {
            let service = services[name]
            let kind: MacInterface.Kind
            if name.hasPrefix("bridge") {
                // Internet Sharing makes bridge100 and up; bridge0 is the Thunderbolt Bridge
                // between Macs, never the way to a PS3.
                guard let number = Int(name.dropFirst("bridge".count)), number >= 100 else { continue }
                kind = .sharing
            } else if name.hasPrefix("en") {
                kind = service?.type == (kSCNetworkInterfaceTypeIEEE80211 as String) ? .wifi : .ethernet
            } else {
                continue
            }
            let linkSpeed = kind == .ethernet && record.baud > 0 ? record.baud : nil
            // A cable with a link but no address still counts: the sheet says how to give it one.
            guard record.address != nil || linkSpeed != nil else { continue }
            let label = service?.label ?? (kind == .sharing ? "Internet Sharing" : name)
            result.append(MacInterface(name: name, label: label, kind: kind, address: record.address, netmask: record.netmask,
                                       linkSpeed: linkSpeed, hasRouter: routers.contains(name)))
        }
        // Cables first: a PS3 on a cable answers sooner and is the one worth choosing.
        func rank(_ kind: MacInterface.Kind) -> Int {
            switch kind {
            case .ethernet: return 0
            case .sharing: return 1
            case .wifi: return 2
            }
        }
        return result.sorted { (rank($0.kind), $0.name) < (rank($1.kind), $1.name) }
    }

    static func readRecords() -> [String: Record] {
        var records: [String: Record] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [:] }
        defer { freeifaddrs(pointer) }
        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let addr = ifa.pointee.ifa_addr else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                guard let ip = numericHost(addr), !ip.hasPrefix("169.254") else { continue }
                records[name, default: Record()].address = ip
                records[name, default: Record()].netmask = ifa.pointee.ifa_netmask.flatMap(numericHost)
            case AF_LINK:
                guard let data = ifa.pointee.ifa_data else { continue }
                records[name, default: Record()].baud = UInt64(data.assumingMemoryBound(to: if_data.self).pointee.ifi_baudrate)
            default:
                continue
            }
        }
        return records
    }

    private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        // A netmask's sockaddr can come with sa_len 0; it is still an IPv4 address.
        let length = addr.pointee.sa_len > 0 ? socklen_t(addr.pointee.sa_len) : socklen_t(MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }

    static func readServices() -> [String: Service] {
        let all = SCNetworkInterfaceCopyAll()
        var services: [String: Service] = [:]
        for index in 0..<CFArrayGetCount(all) {
            // A CFArray of SCNetworkInterface; Swift cannot cast it to a typed array.
            let interface = unsafeBitCast(CFArrayGetValueAtIndex(all, index), to: SCNetworkInterface.self)
            guard let name = SCNetworkInterfaceGetBSDName(interface).map({ $0 as String }),
                  let type = SCNetworkInterfaceGetInterfaceType(interface).map({ $0 as String }) else { continue }
            let label = SCNetworkInterfaceGetLocalizedDisplayName(interface).map { $0 as String } ?? name
            services[name] = Service(type: type, label: label)
        }
        return services
    }

    /// The interfaces whose IPv4 state names a router.
    static func readRouters() -> Set<String> {
        guard let store = SCDynamicStoreCreate(nil, "PS3 Center" as CFString, nil, nil),
              let states = SCDynamicStoreCopyMultiple(store, nil, ["State:/Network/Service/[^/]+/IPv4"] as CFArray) as? [String: Any]
        else { return [] }
        var routers: Set<String> = []
        for case let state as [String: Any] in states.values {
            if let name = state["InterfaceName"] as? String, state["Router"] != nil { routers.insert(name) }
        }
        return routers
    }
}

// MARK: Consoles on the network

/// A PS3 that answered the search, with what the connection sheet shows about it.
public struct FoundConsole: Equatable, Sendable, Identifiable {
    public var id: String { host }
    public let host: String
    /// Wi-Fi or a cable, as the console reports it.
    public var network: NetworkKind?
    /// "4.93 CEX · PS3HEN 3.5.0"
    public var firmware: String?
    /// The Mac's connection it answered on ("USB 10/100/1000 LAN").
    public var via: String?

    public init(host: String, network: NetworkKind? = nil, firmware: String? = nil, via: String? = nil) {
        self.host = host
        self.network = network
        self.firmware = firmware
        self.via = via
    }
}

extension Discovery {
    /// Searches every connection and asks each PS3 that answers for its network and firmware.
    /// `found` gets each console as soon as it is known, so a list can fill in while it runs.
    public static func find(interfaces: [MacInterface] = MacNetwork.interfaces(),
                            found: @escaping @Sendable (FoundConsole) -> Void = { _ in }) async -> [FoundConsole] {
        let hosts = await scan(subnets: localSubnets(interfaces))
        var consoles: [FoundConsole] = []
        for host in hosts {
            let console = await identify(host, interfaces: interfaces)
            found(console)
            consoles.append(console)
        }
        return consoles
    }

    /// GETSYSINFO has the firmware and "IP: 10.0.1.35 WLAN"; a console that does not say keeps
    /// only its address.
    public static func identify(_ host: String, interfaces: [MacInterface] = MacNetwork.interfaces()) async -> FoundConsole {
        let sysInfo = (try? await WebMAN(host: host, timeout: 6).ps3mapi("PS3 GETSYSINFO")) ?? ""
        let snapshot = ConsoleSnapshot.parse(sysInfo: sysInfo, statusPage: "")
        let profile = ConsoleProfile(snapshot: snapshot)
        let prefix = MacNetwork.prefix(of: host)
        return FoundConsole(host: host, network: snapshot.network,
                            firmware: profile.firmware == nil ? nil : profile.label,
                            via: interfaces.first { $0.subnetPrefix == prefix }?.label)
    }
}

// MARK: A cable to the PS3

/// What to do on each side for a cable, worked out from the Mac's connections. PS3 Center only
/// shows the values to type on the PS3: its network settings live in xRegistry.sys, which is never
/// written (DESIGN.md), and changing them over the network would cut the connection doing it.
public enum WiredSetup: Equatable, Sendable {
    /// No cable with a link on the Mac.
    case noCable
    /// A cable has a link but the Mac has no address on it yet; `mac` is a free one to set by hand.
    case needsAddress(MacInterface, mac: Values)
    /// The cable goes to a router: plug the PS3 into the same router and choose Easy on it.
    case router(MacInterface)
    /// Internet Sharing gives the PS3 an address and internet: Easy → Wired on the PS3.
    case sharing(MacInterface)
    /// A cable straight to the PS3 with a fixed address on the Mac: type `ps3` on the PS3.
    case direct(MacInterface, ps3: Values)

    public struct Values: Equatable, Sendable {
        public let address: String
        public let subnetMask: String
        /// The PS3 wants a router and a DNS server even on a cable to the Mac; the Mac's own
        /// address fills both (there is no internet that way anyway).
        public let router: String?
        public let dns: String?

        public init(address: String, subnetMask: String, router: String? = nil, dns: String? = nil) {
            self.address = address
            self.subnetMask = subnetMask
            self.router = router
            self.dns = dns
        }
    }

    /// Where the values go on the PS3 (the XMB's English menus).
    public static let ps3ManualMenu = "Settings → Network Settings → Internet Connection Settings → Custom → Wired Connection → Auto-Detect → IP Address Setting: Manual"
    public static let ps3EasyMenu = "Settings → Network Settings → Internet Connection Settings → Easy → Wired Connection"
    /// What the PS3 asks after the addresses in a custom setup.
    public static let ps3Remaining = "Then MTU: Automatic, Proxy Server: Do Not Use, and UPnP: Enable. The connection test says there is no internet; that is expected on a cable to the Mac."

    public static func macMenu(for interface: MacInterface) -> String {
        "System Settings → Network → \(interface.label) → Details → TCP/IP → Configure IPv4: Manually"
    }

    /// What to do, for the connection sheet and `ps3 connection`.
    public var advice: String {
        switch self {
        case .noCable:
            return "No cable is connected to the Mac. Connect the PS3 with a network cable, to the Mac or to your router: the PS3's Wi-Fi is what makes transfers slow."
        case .needsAddress(let cable, let mac):
            return "\(cable.label) has a cable but no address yet. In \(Self.macMenu(for: cable)), enter IP address \(mac.address) and subnet mask \(mac.subnetMask), and leave Router empty so the internet stays on Wi-Fi."
        case .router(let cable):
            return "\(cable.label) goes to a router. Plug the PS3 into the same router and choose \(Self.ps3EasyMenu) on the PS3."
        case .sharing:
            return "Internet Sharing is on, so the Mac gives the PS3 an address and internet. On the PS3, choose \(Self.ps3EasyMenu)."
        case .direct(let cable, _):
            return "\(cable.label) goes straight to the PS3. On the PS3, choose \(Self.ps3ManualMenu) and enter:"
        }
    }

    /// The connection the advice is about, if there is one.
    public var interface: MacInterface? {
        switch self {
        case .noCable: return nil
        case .needsAddress(let interface, _), .router(let interface), .sharing(let interface), .direct(let interface, _):
            return interface
        }
    }

    /// `console` is the PS3's current address: when it is already on the cable's subnet, that
    /// is the address shown, so the values match what the PS3 has.
    public static func plan(_ interfaces: [MacInterface], console: String? = nil) -> WiredSetup {
        if let sharing = interfaces.first(where: { $0.kind == .sharing && $0.address != nil }) {
            return .sharing(sharing)
        }
        guard let cable = interfaces.first(where: { $0.kind == .ethernet && $0.linkSpeed != nil }) else { return .noCable }
        guard let mac = cable.address else {
            return .needsAddress(cable, mac: Values(address: freeSubnet(avoiding: interfaces) + ".1", subnetMask: "255.255.255.0"))
        }
        if cable.hasRouter { return .router(cable) }
        let prefix = MacNetwork.prefix(of: mac)
        let ps3: String
        if let console, MacNetwork.prefix(of: console) == prefix, console != mac {
            ps3 = console
        } else {
            ps3 = prefix + (mac.hasSuffix(".2") ? ".3" : ".2")
        }
        return .direct(cable, ps3: Values(address: ps3, subnetMask: cable.netmask ?? "255.255.255.0", router: mac, dns: mac))
    }

    /// A /24 no other connection uses, for the Mac's side of a direct cable.
    static func freeSubnet(avoiding interfaces: [MacInterface]) -> String {
        let taken = Set(interfaces.compactMap(\.subnetPrefix))
        return ["192.168.2", "192.168.3", "10.10.10", "172.16.42"].first { !taken.contains($0) } ?? "172.16.43"
    }
}
