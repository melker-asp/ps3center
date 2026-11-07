import Foundation
import Testing
@testable import PS3Kit

// The connection sheet and `ps3 connection`: the Mac's connections, the search order, and the
// values for a cable. The interfaces are what this Mac reported on Nov 7, 2026 (en7 a USB adapter
// straight to the PS3 at 100 Mbit, en0 Wi-Fi to the router).

private let services: [String: MacNetwork.Service] = [
    "en0": .init(type: "IEEE80211", label: "Wi-Fi"),
    "en7": .init(type: "Ethernet", label: "USB 10/100/1000 LAN"),
    "en1": .init(type: "Ethernet", label: "Thunderbolt 1"),
    "bridge0": .init(type: "Bridge", label: "Thunderbolt Bridge"),
]

@Test func readsTheMacsConnections() {
    let records: [String: MacNetwork.Record] = [
        "en0": .init(address: "10.0.1.62", netmask: "255.255.0.0", baud: 547_560_000),
        "en7": .init(address: "192.168.2.1", netmask: "255.255.255.0", baud: 100_000_000),
        "en1": .init(address: nil, netmask: nil, baud: 0),            // a Thunderbolt port, nothing in it
        "bridge0": .init(address: "10.9.9.1", netmask: "255.255.255.0"), // Thunderbolt Bridge: never a PS3
        "utun3": .init(address: "100.64.0.2", netmask: "255.255.255.255"),
    ]
    let interfaces = MacNetwork.combine(records: records, services: services, routers: ["en0"])
    #expect(interfaces.map(\.name) == ["en7", "en0"])  // cables first

    let cable = interfaces[0]
    #expect(cable.kind == .ethernet)
    #expect(cable.label == "USB 10/100/1000 LAN")
    #expect(cable.linkSpeed == 100_000_000)
    #expect(cable.linkSpeedLabel == "100 Mbit")
    #expect(cable.isSlowLink)
    #expect(!cable.hasRouter)

    let wifi = interfaces[1]
    #expect(wifi.kind == .wifi)
    #expect(wifi.linkSpeed == nil)  // Wi-Fi's rate is not a cable's speed
    #expect(!wifi.isSlowLink)
    #expect(wifi.hasRouter)
}

@Test func keepsACableWithoutAnAddressAndFindsInternetSharing() {
    let records: [String: MacNetwork.Record] = [
        "en0": .init(address: "10.0.1.62", netmask: "255.255.0.0", baud: 547_560_000),
        "en7": .init(address: nil, netmask: nil, baud: 1_000_000_000),
        "bridge100": .init(address: "192.168.2.1", netmask: "255.255.255.0"),
    ]
    let interfaces = MacNetwork.combine(records: records, services: services, routers: ["en0"])
    #expect(interfaces.map(\.name) == ["en7", "bridge100", "en0"])
    #expect(interfaces[0].address == nil)
    #expect(interfaces[0].linkSpeedLabel == "1 Gbit")
    #expect(!interfaces[0].isSlowLink)
    #expect(interfaces[1].kind == .sharing)
    #expect(interfaces[1].label == "Internet Sharing")
    // Internet Sharing's network is searched too, which the en*-only search missed.
    #expect(Discovery.localSubnets(interfaces) == ["192.168.2", "10.0.1"])
    #expect(MacNetwork.addresses(interfaces) == ["192.168.2.1", "10.0.1.62"])
}

@Test func ordersFoundConsolesByNetworkThenNumber() {
    let hosts = ["10.0.1.35", "192.168.2.2", "10.0.1.9"]
    #expect(Discovery.order(hosts, subnets: ["192.168.2", "10.0.1"]) == ["192.168.2.2", "10.0.1.9", "10.0.1.35"])
}

@Test func checksTypedAddresses() {
    #expect(MacNetwork.isIPv4("192.168.2.2"))
    #expect(!MacNetwork.isIPv4("192.168.2"))
    #expect(!MacNetwork.isIPv4("ps3.local"))
    #expect(!MacNetwork.isIPv4(" 10.0.0.1"))
    #expect(!MacNetwork.isIPv4("192.168.2.256"))
}

// MARK: Cable values

private let wifi = MacInterface(name: "en0", label: "Wi-Fi", kind: .wifi, address: "10.0.1.62", netmask: "255.255.0.0", hasRouter: true)

private func cable(_ address: String?, router: Bool = false) -> MacInterface {
    MacInterface(name: "en7", label: "USB 10/100/1000 LAN", kind: .ethernet, address: address,
                 netmask: address == nil ? nil : "255.255.255.0", linkSpeed: 100_000_000, hasRouter: router)
}

@Test func givesThePS3sValuesForADirectCable() {
    let setup = WiredSetup.plan([cable("192.168.2.1"), wifi])
    let values = WiredSetup.Values(address: "192.168.2.2", subnetMask: "255.255.255.0", router: "192.168.2.1", dns: "192.168.2.1")
    #expect(setup == .direct(cable("192.168.2.1"), ps3: values))
    #expect(setup.advice.contains(WiredSetup.ps3ManualMenu))

    // The Mac on .2 leaves .3 for the PS3; a PS3 already on the cable keeps its address.
    guard case .direct(_, let next) = WiredSetup.plan([cable("10.10.10.2")]) else { Issue.record("not direct"); return }
    #expect(next.address == "10.10.10.3")
    guard case .direct(_, let current) = WiredSetup.plan([cable("192.168.2.1")], console: "192.168.2.40") else { Issue.record("not direct"); return }
    #expect(current.address == "192.168.2.40")
    // A console on Wi-Fi does not move the cable's suggestion.
    guard case .direct(_, let other) = WiredSetup.plan([cable("192.168.2.1"), wifi], console: "10.0.1.35") else { Issue.record("not direct"); return }
    #expect(other.address == "192.168.2.2")
}

@Test func picksTheRightAdviceForEachSetup() {
    #expect(WiredSetup.plan([wifi]) == .noCable)
    #expect(WiredSetup.plan([cable("10.0.1.80", router: true), wifi]) == .router(cable("10.0.1.80", router: true)))

    let sharing = MacInterface(name: "bridge100", label: "Internet Sharing", kind: .sharing, address: "192.168.2.1", netmask: "255.255.255.0")
    // The cable is a member of the bridge and has no address of its own: Internet Sharing wins.
    #expect(WiredSetup.plan([cable(nil), sharing, wifi]) == .sharing(sharing))

    guard case .needsAddress(_, let mac) = WiredSetup.plan([cable(nil), wifi]) else { Issue.record("no address advice"); return }
    #expect(mac == WiredSetup.Values(address: "192.168.2.1", subnetMask: "255.255.255.0"))
    // A home network on 192.168.2.x pushes the suggestion to the next free one.
    let home = MacInterface(name: "en0", label: "Wi-Fi", kind: .wifi, address: "192.168.2.20", netmask: "255.255.255.0", hasRouter: true)
    guard case .needsAddress(_, let free) = WiredSetup.plan([cable(nil), home]) else { Issue.record("no address advice"); return }
    #expect(free.address == "192.168.3.1")
}
