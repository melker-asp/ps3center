import CryptoKit
import Foundation
import Security
import Testing
@testable import PS3Kit

// Sony's game patches: the rules that keep an update from ever touching the console's system
// software, the package checksum, and the trust for Sony's own TLS root.

private func patch(_ version: String, system: String?) -> GamePatch {
    GamePatch(titleID: "BCES00569", version: version, size: 1, sha1: "", systemVersion: system,
              url: URL(string: "http://b0.ww.np.dl.playstation.net/tppkg/np/BCES00569/x-A\(version)-V0100-PE.pkg")!)
}

@Test func aPatchThatNeedsNewerSystemSoftwareIsRefused() throws {
    let patches = [patch("02.16", system: "3.55"), patch("02.17", system: "4.95")]
    #expect(throws: PS3Error.self) { try GameUpdateService.checkSystemSoftware(patches, console: "4.93", title: "GT5") }
    #expect(throws: PS3Error.self) { try GameUpdateService.checkSystemSoftware(Array(patches.suffix(1)), console: "4.93", title: "GT5") }
    try GameUpdateService.checkSystemSoftware(Array(patches.prefix(1)), console: "4.93", title: "GT5")
    try GameUpdateService.checkSystemSoftware(patches, console: "4.95", title: "GT5")  // equal is enough
}

@Test func anUnreadableConsoleVersionRefusesOnlyPatchesThatNameOne() throws {
    #expect(throws: PS3Error.self) { try GameUpdateService.checkSystemSoftware([patch("02.16", system: "3.55")], console: nil, title: "GT5") }
    #expect(throws: PS3Error.self) { try GameUpdateService.checkSystemSoftware([patch("02.16", system: "3.55")], console: "HEN", title: "GT5") }
    try GameUpdateService.checkSystemSoftware([patch("02.16", system: nil)], console: nil, title: "GT5")
    try GameUpdateService.checkSystemSoftware([], console: nil, title: "GT5")
}

@Test func thePackageMustMatchSonysChecksumWithOrWithoutItsDigest() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ps3center-sha1-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let body = Data((0..<5000).map { UInt8($0 % 251) })
    let digest = Data(repeating: 0xAB, count: 32)
    let file = folder.appendingPathComponent("patch.pkg")
    try (body + digest).write(to: file)
    func hex(_ data: Data) -> String { Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    #expect(GameUpdateService.matches(file, sha1: hex(body + digest)))
    #expect(GameUpdateService.matches(file, sha1: hex(body)))  // lists that leave the digest out
    #expect(GameUpdateService.matches(file, sha1: hex(body).uppercased()))
    #expect(!GameUpdateService.matches(file, sha1: hex(body.dropLast())))
    #expect(!GameUpdateService.matches(file, sha1: ""))
    #expect(!GameUpdateService.matches(folder.appendingPathComponent("missing.pkg"), sha1: hex(body)))

    let tiny = folder.appendingPathComponent("tiny.pkg")
    try digest.write(to: tiny)
    #expect(!GameUpdateService.matches(tiny, sha1: hex(digest)))
}

// The certificate a0.ww.np.dl.playstation.net served in November 2026 (public, valid until July
// 2028), and one made with openssl that copies its subject but is signed by its own key.
private let sonyLeaf = [
    "MIIEUjCCAzqgAwIBAgICF88wDQYJKoZIhvcNAQEFBQAwVDELMAkGA1UEBhMCSlAxKTAnBgNVBAoTIFNvbnkgQ29tcHV0ZXIgRW50",
    "ZXJ0YWlubWVudCBJbmMuMRowGAYDVQQDExFTQ0VJIEROQVMgUm9vdCAwNTAeFw0yNTA1MTUwMjM3MTVaFw0yODA3MTMwMjM3MTVa",
    "MIG0MQswCQYDVQQGEwJKUDEOMAwGA1UECAwFVE9LWU8xEjAQBgNVBAcMCU1JTkFUTy1LVTEsMCoGA1UECgwjU29ueSBJbnRlcmFj",
    "dGl2ZSBFbnRlcnRhaW5tZW50IEluYy4xLjAsBgNVBAsMJU5ldHdvcmsgRW5naW5lZXJpbmcgJiBPcGVyYXRpb24gRGVwdC4xIzAh",
    "BgNVBAMMGioud3cubnAuZGwucGxheXN0YXRpb24ubmV0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAkP67by9Xa0Re",
    "6dnvrVBgw9ETWR3nAs5fheK3KsS8/kDxvH0fmxHilpsM71Y2jaknxXBcZqJSyQuyreeeNpNej0mEZ8/qoFW/y/jT12323v7On1uz",
    "BUAX4BZLDj3iLKDx9lcI98ObcpzlbQZmXQMrLEylELUoRYF0v+VbIH1IRuevhigSQeHvOmlyWO3YprjDh/plfUr9kdbwOeRDK7ap",
    "4mwcWHMJlZAXVAkaNA/pxjvXgamKRcONjiTWtHeMeCpRcCKcftfKK08+wMQvpqLYpl9I5qNX55CN2DcP+pnPeH5FbGddXTaR2ITw",
    "q3elKa3PugaXSP+4Pn4Pds4Qy4RtHQIDAQABo4HMMIHJMAkGA1UdEwQCMAAwHwYJYIZIAYb4QgENBBIWEEROQVMgQ2VydGlmaWNh",
    "dGUwHQYDVR0OBBYEFMYaB4xTRHTStFZQfl9EKus8gyGaMHwGA1UdIwR1MHOAFMZWoTNbT86Dd2IFRIZtIFe1r9rcoVikVjBUMQsw",
    "CQYDVQQGEwJKUDEpMCcGA1UEChMgU29ueSBDb21wdXRlciBFbnRlcnRhaW5tZW50IEluYy4xGjAYBgNVBAMTEVNDRUkgRE5BUyBS",
    "b290IDA1ggEAMA0GCSqGSIb3DQEBBQUAA4IBAQB5Cf4cnHOtBsGx04lT15Nwpn7JtfutxD9Hvq3B/6hnFJUlBxv0jWwUAAsQnb8b",
    "+STgdyd1eq7yM5uwXyxeswHk5bL6QBZ3wh4mC/Cgz0n13fU/Q17KAQG/GrgseWvaHIQIVkZ/BCwxXMJfTYWhAEMLR46mfbe+jkm5",
    "pqKuRBltAXDmzIAbYaiy4vwp7lN3vFRtdWb9TWnhJjDYOinKOdaPP6sFSkPpewez/S70E2B5OBJmSgJlkJJL99S1sK44dXLs+d0p",
    "xvD+bz3M0X/keoAZ3F8k6AYdtubaAgisiWg3qaIVfpFqPRbum9dGHk5XGcmolagtD7Bl0c9BOAjBOrs2",
].joined()

private let forgedLeaf = [
    "MIIDPDCCAiQCCQCubdH7xp8NOzANBgkqhkiG9w0BAQsFADBgMQswCQYDVQQGEwJKUDEsMCoGA1UECgwjU29ueSBJbnRlcmFjdGl2",
    "ZSBFbnRlcnRhaW5tZW50IEluYy4xIzAhBgNVBAMMGioud3cubnAuZGwucGxheXN0YXRpb24ubmV0MB4XDTI2MTEwNzExNTYzN1oX",
    "DTM2MTEwNDExNTYzN1owYDELMAkGA1UEBhMCSlAxLDAqBgNVBAoMI1NvbnkgSW50ZXJhY3RpdmUgRW50ZXJ0YWlubWVudCBJbmMu",
    "MSMwIQYDVQQDDBoqLnd3Lm5wLmRsLnBsYXlzdGF0aW9uLm5ldDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANK5XUmJ",
    "ca4FVkXlMCGqo65Z9lvp0cCvYl9rOd2iAayHmK4v609p4in5aY1KV2OHeElsS3TMVgBev1vDFsbLarnSBzAY5A/I3ghMDPth6GBA",
    "oUceGMV42r4eAYHagP5dXtV9M4NOKWdLH1Cum/MOuvZiqzwuN+titxSh7AQU/ElJ4Lc7oW9zZNDxfM7XGHHDXCzgCe5qeSkTw+mH",
    "sLNNiYBOnU37mwg5EzMHbeQhO3IMJhAp0BdQ4Sy0baryFf4qFR1hVwKEvLmWHjxIYsgubliDW1/Trn5QluMuw/S6KmaZw7o2fejh",
    "xrAnGqKDWXKfXqm/HPe3vd1+UaRiwtSJNFUCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAiWkkixQXhXfExXvIOLxTqJkvjicH4FUw",
    "lzWB8C9BNQTDUBG/+JNXODTcMegZkXqnv0cRrPAYUusR5WKzI9Ybc+Hm1F+PVoOEsnOEaCeJ+S34YSipUDbIMOTSn5I3ZU2GQKu+",
    "t5HKj32vay6XYBuUD1Ukjh5sYhz61ljPD4meWRoCLW9xc5gkRkAvAl1bVa1bB3szWfXnGmhBWp0d8pkV5O54SrLqBXSlY8lpBfGS",
    "jCio3AUJ3adUe4hMIgNGzwR0blGvy4swCo4Nu/S2iy4UJGEcltpmESIjHfr9F13j0YrnxCbhp3yEi1mZK+RRWApP+B89PEHknIxG",
    "q7crG8eMJw==",
].joined()

private func certificate(_ base64: String) throws -> SecCertificate {
    let der = try #require(Data(base64Encoded: base64))
    return try #require(SecCertificateCreateWithData(nil, der as CFData))
}

/// 2027-01-01, when both certificates are valid.
private let checkDate = Date(timeIntervalSince1970: 1_798_761_600)

@Test func sonysServerCertificateChainsToTheBuiltInRoot() throws {
    let leaf = try certificate(sonyLeaf)
    #expect(SonyTrust.chainsToSony([leaf, SonyTrust.sonyRoot], at: checkDate))
    #expect(SonyTrust.chainsToSony([leaf], at: checkDate))
    // Expired is refused too: 2030.
    #expect(!SonyTrust.chainsToSony([leaf, SonyTrust.sonyRoot], at: Date(timeIntervalSince1970: 1_900_000_000)))
}

@Test func aChainThatOnlyContainsSonysRootIsRefused() throws {
    // What the old fingerprint check let through: a forged server certificate with Sony's
    // public root sent alongside it.
    let forged = try certificate(forgedLeaf)
    #expect(!SonyTrust.chainsToSony([forged, SonyTrust.sonyRoot], at: checkDate))
    #expect(!SonyTrust.chainsToSony([forged], at: checkDate))
    #expect(!SonyTrust.chainsToSony([], at: checkDate))
}

@Test func theBuiltInRootIsSCEIDNASRoot05() {
    let der = SecCertificateCopyData(SonyTrust.sonyRoot) as Data
    let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    #expect(fingerprint == "51d5a7833f67f1d1c6212f75997e4b83dada0f7910ba4b5a3fa4e9b7b9bc827c")
    #expect(SecCertificateCopySubjectSummary(SonyTrust.sonyRoot) as String? == "SCEI DNAS Root 05")
}
