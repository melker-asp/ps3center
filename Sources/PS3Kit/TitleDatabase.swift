import Foundation

/// Names for title IDs, from aldostools/Resources/titleid.txt ("BLES01614 007™ Legends", about
/// 17,000 PS3, PSN, PSP and PS1 Classics titles). Kept in ~/Library/Caches/ps3center and fetched
/// again after a month. Only used when a game's own PARAM.SFO gives no name.
public struct TitleDatabase: Sendable {
    public let titles: [String: String]

    public init(titles: [String: String]) { self.titles = titles }

    static let source = URL(string: "https://raw.githubusercontent.com/aldostools/Resources/master/titleid.txt")!
    static var cacheFile: URL { GameLibraryService.cacheDirectory("titles").appendingPathComponent("titleid.txt") }

    /// The cached list, fetched when missing or older than 30 days; empty when neither works.
    public static func load(maxAge: TimeInterval = 30 * 86_400) async -> TitleDatabase {
        let file = cacheFile
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) }
        if let age, age < maxAge, let text = try? String(contentsOf: file, encoding: .utf8) {
            return TitleDatabase(titles: parse(text))
        }
        var request = URLRequest(url: source)
        request.timeoutInterval = 20
        if let answer = try? await URLSession.shared.data(for: request),
           (answer.1 as? HTTPURLResponse)?.statusCode == 200, let text = String(data: answer.0, encoding: .utf8) {
            try? answer.0.write(to: file, options: .atomic)
            return TitleDatabase(titles: parse(text))
        }
        let stale = (try? String(contentsOf: file, encoding: .utf8)).map(parse) ?? [:]
        return TitleDatabase(titles: stale)
    }

    /// "NPUB31857 #KillAllZombies" per line; " [PSOne]" and " [PSP]" tags are dropped.
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let space = line.firstIndex(of: " ") else { continue }
            let id = normalized(String(line[..<space]))
            var title = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            for tag in [" [PSOne]", " [PSP]", " [PS2]"] where title.hasSuffix(tag) { title.removeLast(tag.count) }
            guard id.count == 9, !title.isEmpty, result[id] == nil else { continue }
            result[id] = title
        }
        return result
    }

    static func normalized(_ id: String) -> String {
        id.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    public func title(for titleID: String) -> String? {
        titles[Self.normalized(titleID)]
    }

    /// True when the game carries no name of its own, only its title ID.
    public static func needsName(_ game: Game) -> Bool {
        guard let id = game.titleID else { return false }
        return normalized(game.title) == normalized(id)
    }

    /// The games, with a name from the list where they had only their title ID.
    public func named(_ games: [Game]) -> [Game] {
        games.map { game in
            guard Self.needsName(game), let id = game.titleID, let title = title(for: id) else { return game }
            var named = game
            named.title = title
            return named
        }
    }
}
