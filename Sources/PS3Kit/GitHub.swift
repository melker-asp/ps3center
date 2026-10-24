import Foundation

public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let size: Int64
        public let browserDownloadURL: URL
        public let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case name, size
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
        guard let http = response as? HTTPURLResponse else { throw PS3Error.github("Inget svar från GitHub.") }
        if http.statusCode == 403 || http.statusCode == 429 {
            throw PS3Error.github("GitHub begränsar antalet anrop just nu. Vänta en stund eller sätt GITHUB_TOKEN.")
        }
        if http.statusCode == 404, let notFound { throw PS3Error.github(notFound) }
        guard http.statusCode == 200 else { throw PS3Error.github("GitHub svarade \(http.statusCode) för \(repo).") }
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
        try validate(response, repo: repo, notFound: "\(repo) har ingen README.")
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.encoding == "base64",
              let decoded = Data(base64Encoded: payload.content, options: .ignoreUnknownCharacters) else {
            throw PS3Error.github("Kunde inte läsa README för \(repo).")
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
            throw PS3Error.github("Hittade ingen HEN_REV i PS3HEN-källkoden.")
        }
        return m[1].map(String.init).joined(separator: ".")
    }

    public static func download(_ url: URL, to destination: URL) async throws {
        let (temp, response) = try await URLSession.shared.download(for: request(url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PS3Error.github("Nedladdningen av \(url.lastPathComponent) misslyckades.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temp, to: destination)
    }

    public static func data(_ url: URL) async throws -> Data {
        try await URLSession.shared.data(for: request(url)).0
    }
}
