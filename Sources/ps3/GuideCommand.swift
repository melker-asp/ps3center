import ArgumentParser
import Foundation
import PS3Kit

/// The how-to guides and the glossary, the same texts as Help (⌘?) in the app.
struct GuideCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guide",
        abstract: "How-to guides and the glossary, the same as Help in the app.",
        discussion: """
        Examples:
          ps3 guide                    The guides
          ps3 guide getting-started    How to get going
          ps3 guide send               The first guide with "send" in its name
          ps3 guide glossary           HEN, webMAN MOD, title ID … explained
        """
    )

    @Argument(help: "A guide (its name or a word in its title), or \"glossary\". Nothing lists the guides.")
    var name: String?

    func run() throws {
        guard let name else {
            UI.header("Guides", detail: "ps3 guide <name>")
            for guide in Guides.all {
                print("  " + UI.paint(guide.id.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0), .bold) + " " + guide.summary)
            }
            print("  " + UI.paint("glossary".padding(toLength: 18, withPad: " ", startingAt: 0), .bold) + " Words like HEN, webMAN MOD and title ID, explained")
            return
        }
        if name.lowercased() == "glossary" {
            UI.header("Glossary")
            for term in Glossary.terms {
                print()
                print("  " + UI.paint(term.term, .bold))
                Apps.render(Readme(markdown: term.definition, repo: "glossary", rawBase: nil, htmlBase: nil))
                if let guide = term.guide.flatMap(Guides.guide) {
                    print("  " + UI.paint("More: ps3 guide \(guide.id.rawValue)", .gray))
                }
            }
            return
        }
        guard let guide = Guides.named(name) else {
            throw PS3Error.invalidFile("No guide called \(name). `ps3 guide` lists them.")
        }
        UI.header(guide.title, detail: guide.summary)
        // Links between guides are ps3center://guide/<id>, which only the app opens.
        let markdown = guide.markdown.replacingOccurrences(
            of: #"\[([^\]]+)\]\(ps3center://guide/([a-z0-9-]+)\)"#, with: "$1 (ps3 guide $2)", options: .regularExpression)
        Apps.render(Readme(markdown: markdown, repo: guide.id.rawValue, rawBase: nil, htmlBase: nil))
    }
}
