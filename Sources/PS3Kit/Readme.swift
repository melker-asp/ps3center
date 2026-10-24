import Foundation

/// A GitHub README turned into simple blocks the app and CLI can draw. Not a full Markdown
/// implementation: it covers what PS3 homebrew READMEs use (headings, lists, tables, fenced
/// code, quotes and GitHub alerts, images, and the inline HTML many of them are written in).
/// Inline text keeps Markdown's inline syntax (bold, code, links) with every link made absolute.
public struct Readme: Codable, Equatable, Sendable {
    public struct ListItem: Codable, Equatable, Sendable {
        public let text: String
        public let depth: Int
    }

    public struct Image: Codable, Equatable, Sendable {
        public let url: URL
        public let alt: String
        /// Where the image links to, e.g. a video for a thumbnail.
        public var link: URL?
    }

    public enum Block: Codable, Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list(items: [ListItem], ordered: Bool)
        case quote(String)
        case code(String)
        case image(Image)
        /// The first row is the header.
        case table(rows: [[String]])
        case rule
    }

    public let repo: String
    public let htmlURL: URL?
    public let blocks: [Block]

    public init(repo: String, htmlURL: URL?, blocks: [Block]) {
        self.repo = repo
        self.htmlURL = htmlURL
        self.blocks = blocks
    }

    /// `rawBase` resolves relative image paths (raw.githubusercontent.com/<repo>/<branch>/<dir>/),
    /// `htmlBase` relative links (github.com/<repo>/blob/<branch>/<dir>/).
    public init(markdown: String, repo: String, rawBase: URL?, htmlBase: URL?, htmlURL: URL? = nil) {
        var parser = Parser(rawBase: rawBase, htmlBase: htmlBase)
        self.init(repo: repo, htmlURL: htmlURL, blocks: parser.parse(markdown))
    }

    /// Inline Markdown as terminal text: links become "text (url)", emphasis markers go.
    public static func plainText(_ inline: String) -> String {
        var text = Parser.rewriteLinks(inline) { isImage, label, url in
            if isImage { return label.isEmpty ? "" : "[\(label)]" }
            return label.isEmpty || label == url ? url : "\(label) (\(url))"
        }
        for marker in ["**", "__", "`"] { text = text.replacingOccurrences(of: marker, with: "") }
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"~~(.+?)~~"#, with: "$1", options: .regularExpression)
        return text
    }

    // MARK: Parser

    struct Parser {
        let rawBase: URL?
        let htmlBase: URL?

        private var blocks: [Block] = []
        private var paragraph: [String] = []
        private var listItems: [ListItem] = []
        private var listOrdered = false
        private var quote: [String] = []
        private var table: [[String]] = []
        /// Images found inline in the current block, drawn after it.
        private var pendingImages: [Image] = []

        init(rawBase: URL?, htmlBase: URL?) {
            self.rawBase = rawBase
            self.htmlBase = htmlBase
        }

        mutating func parse(_ markdown: String) -> [Block] {
            let lines = Self.prepare(markdown).components(separatedBy: "\n")
            var index = 0
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                index += 1

                if let fence = Self.fence(trimmed) {
                    flush()
                    var code: [String] = []
                    while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        code.append(lines[index])
                        index += 1
                    }
                    index += 1
                    blocks.append(.code(Self.dedent(code).joined(separator: "\n")))
                    continue
                }
                if trimmed.isEmpty {
                    // A blank line ends a paragraph, quote or table; a list may continue after it.
                    if listItems.isEmpty || !Self.isListItem(lines.dropFirst(index).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "") {
                        flush()
                    }
                    continue
                }
                if let heading = Self.match(#"^#{1,6}(?=\s|$)"#, trimmed) {
                    flush()
                    let text = trimmed.dropFirst(heading.count)
                        .replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    emitHeading(level: heading.count, text: text)
                    continue
                }
                if !paragraph.isEmpty, quote.isEmpty, Self.match(#"^=+$"#, trimmed) != nil {
                    let text = paragraph.joined(separator: " ")
                    paragraph = []
                    emitHeading(level: 1, text: text)
                    continue
                }
                if Self.match(#"^([-*_])( *\1){2,}$"#, trimmed) != nil {
                    if !paragraph.isEmpty, quote.isEmpty, trimmed.hasPrefix("-") {
                        let text = paragraph.joined(separator: " ")
                        paragraph = []
                        emitHeading(level: 2, text: text)
                    } else {
                        flush()
                        blocks.append(.rule)
                    }
                    continue
                }
                if trimmed.hasPrefix(">") {
                    if quote.isEmpty { flush() }
                    var content = String(trimmed.dropFirst())
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quote.append(content)
                    continue
                }
                if trimmed.hasPrefix("|") {
                    if table.isEmpty { flush() }
                    if Self.match(#"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$"#, trimmed) == nil {
                        table.append(Self.cells(trimmed))
                    }
                    continue
                }
                if let item = Self.listItem(line) {
                    if listItems.isEmpty { flush(); listOrdered = item.ordered }
                    listItems.append(ListItem(text: item.text, depth: item.depth))
                    continue
                }
                if !listItems.isEmpty, line.hasPrefix(" ") || line.hasPrefix("\t") {
                    // Continuation of the last list item.
                    let last = listItems.removeLast()
                    listItems.append(ListItem(text: last.text + " " + trimmed, depth: last.depth))
                    continue
                }
                if !quote.isEmpty {
                    quote.append(trimmed)  // lazy continuation
                    continue
                }
                if !listItems.isEmpty || !table.isEmpty { flush() }
                paragraph.append(line.hasSuffix("  ") || line.hasSuffix("\\") ? Self.hardBreak(trimmed) : trimmed)
            }
            flush()
            return blocks
        }

        // MARK: Blocks

        private mutating func emitHeading(level: Int, text: String) {
            let processed = inline(text)
            if !processed.isEmpty { blocks.append(.heading(level: level, text: processed)) }
            emitImages()
        }

        private mutating func flush() {
            if !paragraph.isEmpty {
                let text = inline(paragraph.joined(separator: " ")
                    .replacingOccurrences(of: "\u{2028} ", with: "\u{2028}"))
                paragraph = []
                if !text.isEmpty { blocks.append(.paragraph(text)) }
                emitImages()
            }
            if !listItems.isEmpty {
                let minimum = listItems.map(\.depth).min() ?? 0
                var items: [ListItem] = []
                for item in listItems {
                    let text = inline(item.text)
                    if !text.isEmpty { items.append(ListItem(text: text, depth: item.depth - minimum)) }
                }
                listItems = []
                if !items.isEmpty { blocks.append(.list(items: items, ordered: listOrdered)) }
                emitImages()
            }
            if !quote.isEmpty {
                var lines = quote
                quote = []
                // GitHub alerts: "> [!WARNING]" on the first line.
                var label: String?
                if let first = lines.first, let kind = Self.match(#"^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$"#, first.trimmingCharacters(in: .whitespaces)) {
                    label = ["[!NOTE]": "Obs", "[!TIP]": "Tips", "[!IMPORTANT]": "Viktigt", "[!WARNING]": "Varning", "[!CAUTION]": "Varning"][kind]
                    lines.removeFirst()
                }
                // Quotes keep their line breaks; headings inside them become bold lines.
                var bodyLines: [String] = []
                for line in lines {
                    let text = inline(line.replacingOccurrences(of: #"^#{1,6}\s+(.*)$"#, with: "**$1**", options: .regularExpression))
                    if !text.isEmpty { bodyLines.append(text) }
                }
                let body = bodyLines.joined(separator: "\n")
                let text = [label.map { "**\($0)**" }, body.isEmpty ? nil : body].compactMap { $0 }.joined(separator: "\n")
                if !text.isEmpty { blocks.append(.quote(text)) }
                emitImages()
            }
            if !table.isEmpty {
                var rows: [[String]] = []
                for row in table {
                    var cells: [String] = []
                    for cell in row { cells.append(inline(cell)) }
                    rows.append(cells)
                }
                table = []
                if rows.contains(where: { $0.contains { !$0.isEmpty } }) { blocks.append(.table(rows: rows)) }
                emitImages()
            }
        }

        private mutating func emitImages() {
            blocks.append(contentsOf: pendingImages.map(Block.image))
            pendingImages = []
        }

        // MARK: Inline

        /// Stands in for an image while the link around it is processed.
        private static let imageMarker = "\u{1}\\d+\u{1}"

        /// Makes links absolute, moves images out to `pendingImages` (dropping badges) and
        /// turns the line-separator placeholder back into a newline.
        private mutating func inline(_ text: String) -> String {
            var found: [Image] = []
            let rawBase = rawBase, htmlBase = htmlBase
            var output = Self.rewriteLinks(text) { isImage, label, target in
                if isImage {
                    guard let url = Self.resolve(target, base: rawBase, image: true), !Self.isBadge(url) else { return "" }
                    found.append(Image(url: url, alt: label, link: nil))
                    return "\u{1}\(found.count - 1)\u{1}"
                }
                // A link around images only: attach the link to them.
                let marked = label.replacingOccurrences(of: Self.imageMarker, with: "", options: .regularExpression)
                if marked.trimmingCharacters(in: .whitespaces).isEmpty {
                    let link = Self.resolve(target, base: htmlBase, image: false)
                    for match in label.matches(of: #/\x{1}(\d+)\x{1}/#) {
                        if let i = Int(match.1), i < found.count { found[i].link = link }
                    }
                    return label
                }
                guard !target.hasPrefix("#"), let url = Self.resolve(target, base: htmlBase, image: false) else { return label }
                return "[\(label)](\(url.absoluteString))"
            }
            output = output.replacingOccurrences(of: Self.imageMarker, with: "", options: .regularExpression)
            pendingImages.append(contentsOf: found)
            return output
                .replacingOccurrences(of: #"[ \t]*\x{2028}[ \t]*"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Walks `[label](url)` and `![alt](url)`, innermost first, so a linked image
        /// `[![alt](img)](link)` reaches `transform` as the image, then the link around it.
        static func rewriteLinks(_ text: String, _ transform: (_ isImage: Bool, _ label: String, _ url: String) -> String) -> String {
            let chars = Array(text)
            var out = ""
            var i = 0
            while i < chars.count {
                let isImage = chars[i] == "!" && i + 1 < chars.count && chars[i + 1] == "["
                guard chars[i] == "[" || isImage else { out.append(chars[i]); i += 1; continue }
                let open = isImage ? i + 1 : i
                guard let close = matching(chars, from: open, open: "[", close: "]"),
                      close + 1 < chars.count, chars[close + 1] == "(",
                      let end = matching(chars, from: close + 1, open: "(", close: ")") else {
                    out.append(chars[i]); i += 1; continue
                }
                let label = rewriteLinks(String(chars[(open + 1)..<close]), transform)
                var target = String(chars[(close + 2)..<end]).trimmingCharacters(in: .whitespaces)
                if let space = target.firstIndex(where: { $0 == " " }) { target = String(target[..<space]) }  // drop "title"
                target = target.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                out += transform(isImage, label, target)
                i = end + 1
            }
            return out
        }

        private static func matching(_ chars: [Character], from start: Int, open: Character, close: Character) -> Int? {
            var depth = 0
            var i = start
            while i < chars.count {
                if chars[i] == "\\" { i += 2; continue }
                if chars[i] == open { depth += 1 }
                if chars[i] == close { depth -= 1; if depth == 0 { return i } }
                i += 1
            }
            return nil
        }

        static func resolve(_ target: String, base: URL?, image: Bool) -> URL? {
            guard !target.isEmpty else { return nil }
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(["%", "#"])) ?? target
            if encoded.hasPrefix("/"), !encoded.hasPrefix("//"), let root = base.flatMap(repoRoot) {
                // "/docs/x.png" means the repo's root, not the host's.
                return URL(string: String(encoded.dropFirst()), relativeTo: root)?.absoluteURL
            }
            guard var url = URL(string: encoded, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return nil }
            // github.com/<owner>/<repo>/blob/<branch>/x.png is an HTML page; the image is on raw.
            if image, url.host == "github.com" {
                let parts = url.path.split(separator: "/")
                if parts.count > 4, parts[2] == "blob",
                   let raw = URL(string: "https://raw.githubusercontent.com/" + ([parts[0], parts[1]] + parts[3...]).joined(separator: "/")) {
                    url = raw
                }
            }
            return url
        }

        /// raw.githubusercontent.com/<owner>/<repo>/<branch>/ or github.com/<owner>/<repo>/blob/<branch>/.
        private static func repoRoot(_ base: URL) -> URL? {
            let parts = base.path.split(separator: "/")
            let depth = base.host == "raw.githubusercontent.com" ? 3 : 4
            guard parts.count >= depth, let host = base.host else { return nil }
            return URL(string: "https://\(host)/" + parts.prefix(depth).joined(separator: "/") + "/")
        }

        /// Status badges (shields.io, CI, donate buttons) add nothing in the app, and are SVG.
        static func isBadge(_ url: URL) -> Bool {
            let text = url.absoluteString.lowercased()
            return url.pathExtension.lowercased() == "svg" || text.contains("shields.io") || text.contains("badge")
        }

        // MARK: Lines

        private static func fence(_ trimmed: String) -> String? {
            if trimmed.hasPrefix("```") { return "```" }
            if trimmed.hasPrefix("~~~") { return "~~~" }
            return nil
        }

        private static func isListItem(_ line: String) -> Bool { listItem(line) != nil }

        private static func listItem(_ line: String) -> (text: String, depth: Int, ordered: Bool)? {
            guard let m = line.firstMatch(of: #/^(\s*)([-*+]|\d{1,3}[.)])\s+(.*)$/#) else { return nil }
            let indent = m.1.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            var text = String(m.3)
            if text.hasPrefix("[ ] ") { text = "☐ " + text.dropFirst(4) }
            if text.lowercased().hasPrefix("[x] ") { text = "☑ " + text.dropFirst(4) }
            return (text, min(indent / 2, 4), m.2.first?.isNumber == true)
        }

        private static func cells(_ row: String) -> [String] {
            var parts = row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.first == "" { parts.removeFirst() }
            if parts.last == "" { parts.removeLast() }
            return parts
        }

        private static func dedent(_ lines: [String]) -> [String] {
            let indents = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.prefix { $0 == " " }.count }
            let common = indents.min() ?? 0
            return lines.map { String($0.dropFirst(min(common, $0.prefix { $0 == " " }.count))) }
        }

        private static func hardBreak(_ trimmed: String) -> String {
            (trimmed.hasSuffix("\\") ? String(trimmed.dropLast()) : trimmed) + "\u{2028}"
        }

        private static func match(_ pattern: String, _ text: String) -> String? {
            text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
        }

        // MARK: HTML and references

        /// Rewrites the HTML and reference-style links READMEs use into plain Markdown,
        /// leaving fenced code alone.
        static func prepare(_ markdown: String) -> String {
            var text = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            text = text.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)

            var segments: [(code: Bool, text: String)] = []
            var current: [String] = []
            var inCode = false
            var fenceMarker = ""
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !inCode, let marker = fence(trimmed) {
                    segments.append((false, current.joined(separator: "\n")))
                    current = [line]
                    inCode = true
                    fenceMarker = marker
                } else if inCode, trimmed.hasPrefix(fenceMarker) {
                    current.append(line)
                    segments.append((true, current.joined(separator: "\n")))
                    current = []
                    inCode = false
                } else {
                    current.append(line)
                }
            }
            segments.append((inCode, current.joined(separator: "\n")))

            let references = collectReferences(segments.filter { !$0.code }.map(\.text).joined(separator: "\n"))
            return segments.map { $0.code ? $0.text : html(applyReferences(references, to: $0.text)) }.joined(separator: "\n")
        }

        /// "[label]: https://…" definitions, removed from the text by applyReferences.
        private static func collectReferences(_ text: String) -> [String: String] {
            var result: [String: String] = [:]
            for m in text.matches(of: #/(?m)^ {0,3}\[([^\]]+)\]:\s*<?(\S+?)>?(?:\s+["'(].*["')])?\s*$/#) {
                result[m.1.lowercased()] = String(m.2)
            }
            return result
        }

        private static func applyReferences(_ references: [String: String], to text: String) -> String {
            guard !references.isEmpty else { return text }
            var text = text.replacingOccurrences(of: #"(?m)^ {0,3}\[[^\]]+\]:\s*\S+.*$\n?"#, with: "", options: .regularExpression)
            // [text][ref] and [text][] (implicit: the text is the ref). A second round resolves
            // the image inside a linked badge, [![alt][img]][link].
            for _ in 0..<2 {
                text = text.replacing(#/\[((?:[^\[\]]|\[[^\[\]]*\](?:\([^)]*\))?)*)\]\[([^\]]*)\]/#) { m in
                    let key = (m.2.isEmpty ? m.1 : m.2).lowercased()
                    guard let url = references[key] else { return String(m.0) }
                    return "[\(m.1)](\(url))"
                }
            }
            return text
        }

        /// Turns the HTML READMEs are written in into Markdown: images, links, headings and line
        /// breaks are kept, layout tags (p, div, span, center, details) go.
        static func html(_ input: String) -> String {
            // Inline code is shown as written, so keep it away from the tag stripping below.
            var spans: [String] = []
            var text = input.replacing(#/`[^`\n]+`/#) { m in
                spans.append(String(m.0))
                return "\u{3}\(spans.count - 1)\u{3}"
            }
            func attribute(_ name: String, in tag: Substring) -> String? {
                let pattern = name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
                guard let range = tag.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
                let part = tag[range]
                guard let eq = part.firstIndex(of: "=") else { return nil }
                return part[part.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
            text = text.replacing(#/(?i)<img\b[^>]*>/#) { m in
                guard let src = attribute("src", in: m.0) else { return "" }
                return " ![\(attribute("alt", in: m.0) ?? "")](\(src.replacingOccurrences(of: " ", with: "%20"))) "
            }
            text = text.replacing(#/(?is)<a\b([^>]*)>(.*?)</a>/#) { m in
                guard let href = attribute("href", in: m.1) else { return String(m.2) }
                return "[\(m.2.trimmingCharacters(in: .whitespacesAndNewlines))](\(href.replacingOccurrences(of: " ", with: "%20")))"
            }
            text = text.replacing(#/(?is)<h([1-6])\b[^>]*>(.*?)</h\1\s*>/#) { m in
                let inner = m.2.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                return "\n\n" + String(repeating: "#", count: Int(m.1) ?? 2) + " " + inner + "\n\n"
            }
            text = text.replacing(#/(?is)<summary\b[^>]*>(.*?)</summary>/#) { m in "\n\n**\(m.1.trimmingCharacters(in: .whitespacesAndNewlines))**\n\n" }
            // A <br> that ends a line is Markdown's hard break; one inside a line breaks it there.
            text = text.replacingOccurrences(of: #"(?i)<br\s*/?>[ \t]*(?=\n|$)"#, with: "  ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\u{2028}", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?i)</?(b|strong)>"#, with: "**", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?i)</?(i|em)>"#, with: "*", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?i)</?code>"#, with: "`", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?i)</?(p|div|center|details|table|tr|ul|ol|hr)\b[^>]*>"#, with: "\n\n", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?i)<li\b[^>]*>"#, with: "\n- ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?i)</?(td|th)\b[^>]*>"#, with: " ", options: .regularExpression)
            // Autolinks <https://…> before the remaining tags are stripped.
            text = text.replacingOccurrences(of: #"<(https?://[^>\s]+)>"#, with: "[$1]($1)", options: .regularExpression)
            text = text.replacingOccurrences(of: #"</?[a-zA-Z][a-zA-Z0-9-]*(\s[^<>]*)?/?>"#, with: "", options: .regularExpression)
            // Inline math GitHub renders, as in "$\rightarrow$": keep the symbol.
            text = text.replacing(#/\$([^$\n]*\\[^$\n]*)\$/#) { m in
                var math = String(m.1)
                for (command, symbol) in [("\\rightarrow", "→"), ("\\leftarrow", "←"), ("\\geq", "≥"), ("\\ge", "≥"),
                                          ("\\leq", "≤"), ("\\le", "≤"), ("\\times", "×"), ("\\bigcirc", "○")] {
                    math = math.replacingOccurrences(of: command, with: symbol)
                }
                return math.replacingOccurrences(of: #"\\text\{([^}]*)\}"#, with: "$1", options: .regularExpression)
            }
            for (entity, value) in ["&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&copy;": "©", "&amp;": "&"] {
                text = text.replacingOccurrences(of: entity, with: value)
            }
            for (index, span) in spans.enumerated() {
                text = text.replacingOccurrences(of: "\u{3}\(index)\u{3}", with: span)
            }
            return text
        }
    }
}
