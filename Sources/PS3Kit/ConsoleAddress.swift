import Foundation

/// An address typed by hand (the setup guide): what people paste from the PS3's network status
/// screen or a browser, cleaned up to the host webMAN answers on.
public enum ConsoleAddress {
    /// "192.168.1.20", " http://192.168.1.20/setup.ps3 " or "ps3.local" → the host; nil for
    /// anything that can't be one ("192.168.1", "300.1.1.1", "my ps3").
    public static func clean(_ text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["http://", "https://", "ftp://"] where host.lowercased().hasPrefix(scheme) {
            host = String(host.dropFirst(scheme.count))
        }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        guard !host.isEmpty, host.count <= 253, host.allSatisfy(\.isASCII) else { return nil }

        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            // All digits and dots: it has to be a whole IPv4 address.
            guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.count <= 3 && Int($0).map { $0 <= 255 } == true }) else { return nil }
            return host
        }
        // A name: letters, digits and hyphens between dots.
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let lowered = host.lowercased()
        guard lowered.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" && label.allSatisfy(allowed.contains)
        }) else { return nil }
        return lowered
    }
}
