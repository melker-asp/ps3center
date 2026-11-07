import CryptoKit
import Foundation

public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let size: Int64
        public let browserDownloadURL: URL
        public let updatedAt: String
        /// "sha256:<hex>", on assets uploaded since GitHub started computing it (2025).
        public let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
            case updatedAt = "updated_at"
        }
    }

    public let tagName: String
    public let publishedAt: String?
    public let htmlURL: URL
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case assets
    }

    public func asset(matching pattern: String) -> Asset? {
        assets.first { $0.name.range(of: pattern, options: .regularExpression) != nil }
    }
}

public enum GitHub {
    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("ps3center", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// The release with `tag`, or the latest one when `tag` is nil.
    public static func release(repo: String, tag: String? = nil) async throws -> GitHubRelease {
        let path = tag.map { "tags/" + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0) } ?? "latest"
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/\(path)")!
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try validate(response, repo: repo)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func validate(_ response: URLResponse, repo: String, notFound: String? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw PS3Error.github("No answer from GitHub.") }
        if http.statusCode == 403 || http.statusCode == 429 {
            throw PS3Error.github("GitHub is rate-limiting requests right now. Wait a while or set GITHUB_TOKEN.")
        }
        if http.statusCode == 404, let notFound { throw PS3Error.github(notFound) }
        guard http.statusCode == 200 else { throw PS3Error.github("GitHub answered \(http.statusCode) for \(repo).") }
    }

    /// The repo's README, parsed. Relative image paths resolve against the raw file's folder
    /// and relative links against the file's page on github.com.
    public static func readme(repo: String) async throws -> Readme {
        struct Payload: Decodable {
            let content: String
            let encoding: String
            let downloadURL: URL?
            let htmlURL: URL?

            enum CodingKeys: String, CodingKey {
                case content, encoding
                case downloadURL = "download_url"
                case htmlURL = "html_url"
            }
        }
        let url = URL(string: "https://api.github.com/repos/\(repo)/readme")!
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try validate(response, repo: repo, notFound: "\(repo) has no README.")
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.encoding == "base64",
              let decoded = Data(base64Encoded: payload.content, options: .ignoreUnknownCharacters) else {
            throw PS3Error.github("Could not read the README for \(repo).")
        }
        // A few older READMEs (IRISMAN's) are Latin-1.
        let markdown = String(data: decoded, encoding: .utf8) ?? String(String.UnicodeScalarView(decoded.map { Unicode.Scalar($0) }))
        return Readme(markdown: markdown, repo: repo,
                      rawBase: payload.downloadURL?.deletingLastPathComponent(),
                      htmlBase: payload.htmlURL?.deletingLastPathComponent(), htmlURL: payload.htmlURL)
    }

    /// Latest PS3HEN version from HEN_REV (e.g. 0x0360 -> "3.6.0") in the payload source.
    public static func latestHENVersion() async throws -> String {
        let url = URL(string: "https://raw.githubusercontent.com/PS3Xploit/PS3HEN/master/payload/main.c")!
        let (data, _) = try await URLSession.shared.data(for: request(url))
        let source = String(decoding: data, as: UTF8.self)
        guard let m = ConsoleSnapshot.firstMatch(#"#define\s+HEN_REV\s+0x0*([0-9a-fA-F]{3})\b"#, in: source) else {
            throw PS3Error.github("Found no HEN_REV in the PS3HEN source code.")
        }
        return m[1].map(String.init).joined(separator: ".")
    }

    public static func download(_ url: URL, to destination: URL) async throws {
        let (temp, response) = try await URLSession.shared.download(for: request(url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PS3Error.github("Downloading \(url.lastPathComponent) failed.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temp, to: destination)
    }

    /// Checks a downloaded release file against what GitHub says about it: the size, and the
    /// SHA-256 in the asset's `digest` when there is one. A file that does not match is removed,
    /// so a broken or swapped package never reaches the console. True when the SHA-256 was checked.
    @discardableResult
    public static func verify(_ file: URL, size: Int64, digest: String?) throws -> Bool {
        let fm = FileManager.default
        let actual = ((try? fm.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? -1
        guard actual == size else {
            try? fm.removeItem(at: file)
            throw PS3Error.github("\(file.lastPathComponent) came to \(Format.bytes(max(actual, 0))) but should be \(Format.bytes(size)). The file was deleted; try again.")
        }
        guard let digest, digest.lowercased().hasPrefix("sha256:") else { return false }
        guard try sha256(of: file) == digest.dropFirst("sha256:".count).lowercased() else {
            try? fm.removeItem(at: file)
            throw PS3Error.github("The checksum of \(file.lastPathComponent) does not match GitHub's. The file was deleted; try again.")
        }
        return true
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func data(_ url: URL) async throws -> Data {
        try await URLSession.shared.data(for: request(url)).0
    }
}
