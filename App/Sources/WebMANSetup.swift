import Foundation
import PS3Kit
import WebKit

/// Fills in one of webMAN's network servers (/net0 … /net4) with the Mac's game server.
///
/// webMAN's settings page (include/setup.h) resets every setting when it receives the form and
/// reads them all back from the request, and some fields (icon type, info tags, USB wait times)
/// get their values from JavaScript in the page (setup*.dat). So the page is loaded in a hidden
/// web view, as Safari would show it, only the network server fields are changed, and the form
/// is sent exactly as Safari would send it. The page is then read again to check that every
/// other setting came back the same.
@MainActor
final class WebMANSetup: NSObject, WKNavigationDelegate {
    struct Slot: Decodable, Equatable {
        let enabled: Bool
        let host: String
        let port: Int
    }

    private struct Form: Decodable {
        var slots: [Slot]?
        var query: String?
        var error: String?
    }

    private let host: String
    private let webView = WKWebView(frame: .zero)
    private var loading: CheckedContinuation<Void, Error>?

    init(host: String) {
        self.host = host
        super.init()
        webView.navigationDelegate = self
    }

    /// The network servers as webMAN has them now.
    func slots() async throws -> [Slot] {
        try await load()
        return try await read().slots ?? []
    }

    /// Points a network server at `address:port` and returns its number (0 for /net0). A server
    /// already pointing there is used as it is; otherwise the first empty one. Logged.
    func configure(address: String, port: Int) async throws -> Int {
        try await load()
        let before = try await read()
        let slots = before.slots ?? []
        guard !slots.isEmpty else {
            throw PS3Error.refused("webMAN's settings have no network servers. This version of webMAN can't play from a ps3netsrv.")
        }
        if let ready = slots.firstIndex(where: { $0.enabled && $0.host == address && $0.port == port }) { return ready }
        guard let slot = slots.firstIndex(where: { $0.host == address }) ?? slots.firstIndex(where: { $0.host.isEmpty }) else {
            throw PS3Error.refused("All \(slots.count) network servers in webMAN are already in use. Change one of them yourself in webMAN's settings.")
        }

        let changed = try await read(filling: slot, address: address, port: port)
        guard let query = changed.query, query.contains("ic=") else {
            throw PS3Error.refused("webMAN's settings page didn't look as expected, so nothing was sent.")
        }
        OperationLog.record("webman-setup", "network server \(slot + 1) = \(address):\(port)")
        try await WebMAN(host: host).get(encoded: "/setup.ps3?" + query, timeout: 20)

        // Every field should come back as it was sent.
        try await load()
        guard let saved = try await read().query else { throw PS3Error.refused("webMAN's settings couldn't be read afterwards.") }
        let differing = WebMANSettings.differences(sent: query, saved: saved)
        guard differing.isEmpty else {
            throw PS3Error.refused("webMAN didn't save everything as it was (\(differing.joined(separator: ", "))). A copy of the settings from before the change is in System Files under Maintenance.")
        }
        return slot
    }

    // MARK: The page

    private func load() async throws {
        guard let url = URL(string: "http://\(host)/setup.ps3") else { throw PS3Error.unreachable(host: host) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loading = continuation
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        }
    }

    /// The form as Safari would send it, after filling in a network server when asked to.
    private func read(filling slot: Int? = nil, address: String = "", port: Int = 0) async throws -> Form {
        let fill = slot.map { slot in
            """
            f.elements['nd\(slot)'].checked = true;
            f.elements['neth\(slot)'].value = \(Self.literal(address));
            f.elements['netp\(slot)'].value = '\(port)';
            """
        } ?? ""
        let script = """
        (function () {
          try {
            var f = document.querySelector('form[action="/setup.ps3"]');
            if (!f) return JSON.stringify({error: 'form'});
            var slots = [];
            for (var i = 0; i < 10; i++) {
              var d = f.elements['nd' + i], h = f.elements['neth' + i], p = f.elements['netp' + i];
              if (!h) break;
              slots.push({enabled: !!(d && d.checked), host: h.value, port: parseInt(p ? p.value : '0', 10) || 0});
            }
            \(fill)
            return JSON.stringify({slots: slots, query: new URLSearchParams(new FormData(f)).toString()});
          } catch (e) {
            return JSON.stringify({error: String(e)});
          }
        })();
        """
        guard let json = try await webView.evaluateJavaScript(script) as? String,
              let form = try? JSONDecoder().decode(Form.self, from: Data(json.utf8)) else {
            throw PS3Error.refused("webMAN's settings page couldn't be read.")
        }
        if let error = form.error {
            throw PS3Error.refused("webMAN's settings page didn't look as expected (\(error)), so nothing changed.")
        }
        return form
    }

    private static func literal(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading?.resume()
        loading = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading?.resume(throwing: error)
        loading = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading?.resume(throwing: PS3Error.unreachable(host: host))
        loading = nil
    }
}
