import Foundation
import Testing
@testable import PS3Kit

// The guides and the glossary that Help (⌘?) and `ps3 guide` show, and a check that every icon
// button in the app says what it does.

@Test func everyGuideIsWrittenAndParses() {
    #expect(Guides.all.map(\.id) == GuideID.allCases)
    for guide in Guides.all {
        #expect(!guide.title.isEmpty, "\(guide.id) has no title")
        #expect(guide.summary.count <= 90, "\(guide.id)'s summary is too long for the list")
        #expect(!guide.symbol.isEmpty)
        // The title is shown above the text, so the text starts below it.
        #expect(!guide.markdown.hasPrefix("# "), "\(guide.id) repeats its title as a heading")
        #expect(guide.readme.blocks.count >= 3, "\(guide.id) is almost empty")
    }
}

@Test func linksBetweenGuidesLeadSomewhere() throws {
    let pattern = try NSRegularExpression(pattern: #"ps3center://guide/([a-z0-9-]+)"#)
    for guide in Guides.all {
        let text = guide.markdown
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let id = String(text[Range(match.range(at: 1), in: text)!])
            #expect(GuideID(rawValue: id) != nil, "\(guide.id) links to a guide that doesn't exist: \(id)")
        }
    }
    #expect(Guide.id(from: URL(string: "ps3center://guide/send-games")!) == .sendGames)
    #expect(Guide.id(from: URL(string: "https://github.com/x")!) == nil)
}

@Test func everyTermIsExplained() {
    #expect(Glossary.terms.map(\.id) == Glossary.TermID.allCases)
    for term in Glossary.terms {
        #expect(!term.term.isEmpty && term.definition.count > 20, "\(term.id) has no real definition")
        if let guide = term.guide { #expect(Guides.guide(guide) != nil) }
    }
}

@Test func theGuidesKeepTheRules() {
    // CLAUDE.md: nothing from ps3.aldostools.org, psdevwiki or Brewology, and never PSID/IDPS.
    let forbidden = ["aldostools.org", "psdevwiki", "brewology.com", "PSID", "IDPS"]
    let texts = Guides.all.map { ($0.id.rawValue, $0.markdown) } + Glossary.terms.map { ($0.id.rawValue, $0.definition) }
    for (id, text) in texts {
        for word in forbidden {
            #expect(!text.contains(word), "\(id) mentions \(word)")
        }
    }
}

@Test func guidesAreFoundByNameOrWord() {
    #expect(Guides.named("send-games")?.id == .sendGames)
    #expect(Guides.named("Troubleshooting")?.id == .troubleshooting)
    #expect(Guides.named("usb")?.id == .usbDrive)
    #expect(Guides.named("nothing like this") == nil)
    #expect(Guides.search("").count == Guides.all.count)
    #expect(Guides.search("PS2 Classic").first?.id == .ps2Classic)
}

/// DESIGN.md: an icon-only button has a tooltip and a VoiceOver label (`iconLabel`). Reads the
/// app's sources, since the app target has no tests of its own.
@Test func everyIconButtonSaysWhatItDoes() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Sources")
    let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    #expect(!files.isEmpty)
    let iconButton = try NSRegularExpression(pattern: #"CircleIconButtonStyle\(|label:\s*\{\s*Image\(systemName|Button\([^)"]*\)\s*\{\s*Image\(systemName"#)
    var missing: [String] = []
    for file in files {
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where !line.contains("struct CircleIconButtonStyle") {
            guard iconButton.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
            // The label may come before the style (a button's modifiers) or after it.
            let window = lines[max(0, index - 12)..<min(lines.count, index + 10)].joined(separator: "\n")
            if !(window.contains(".iconLabel(") || window.contains(".help(") || window.contains("accessibilityLabel")) {
                missing.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
    }
    #expect(missing.isEmpty, "Icon buttons without a label: \(missing.joined(separator: ", "))")
}
