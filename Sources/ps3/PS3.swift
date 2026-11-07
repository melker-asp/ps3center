import ArgumentParser
import Foundation
import PS3Kit

@main
struct PS3: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps3",
        abstract: "PS3 Center – control your PS3 (PS3HEN + webMAN MOD) from your Mac.",
        discussion: """
        Examples:
          ps3                          A menu of common commands (in a terminal)
          ps3 status                   Temperature, fan, free space and what is running
          ps3 send Game.dec.iso        Upload a game, refresh the list, show a popup
          ps3 games                    Games on the PS3, with title ID, size and version
          ps3 games play gran          Start a game from the Mac
          ps3 queue add gran && ps3 queue start   Send games from the Mac
          ps3 speedtest                How fast is the connection to the PS3?
          ps3 apps                     Installed apps and available updates
          ps3 apps info apollo         Version, whether it works on your PS3, README
          ps3 apps update              Review and install updates
          ps3 apps install X.pkg       Install a package without a USB stick
          ps3 backup                   Saves and system files to the Mac
          ps3 maintain                 Cleanup: leftover packages, partial transfers
          ps3 record / ps3 media pull  Record gameplay; fetch videos and photos
          ps3 verify Game.dec.iso      Check a disc copy against the original (IRD)
          ps3 iso make GameFolder      Make an ISO from a folder (also split/join/extract)
          ps3 ps2 classic Game.iso     Turn a PS2 game into a PS2 Classic for HEN
          ps3 mcp                      MCP server so Claude can troubleshoot the PS3
          ps3 guide                    How-to guides and the glossary, as Help in the app
        """,
        version: "0.1.0",
        subcommands: [Status.self, Send.self, Games.self, Queue.self, Apps.self, Speedtest.self, USB.self, ISO.self, PS2.self, Power.self, Disc.self, Fan.self, Pad.self, Screenshot.self, Record.self, Media.self, Beep.self, Music.self, Serve.self,
                      WatchFolders.self, Saves.self, Backup.self, Maintain.self, Analyze.self, Rip.self, Verify.self, ErrorCode.self, GuideCommand.self, MCP.self, Popup.self, Refresh.self, History.self, Discover.self, Config.self]
    )
}
