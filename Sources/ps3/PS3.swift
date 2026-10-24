import ArgumentParser
import Foundation
import PS3Kit

@main
struct PS3: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps3",
        abstract: "PS3 Center – styr din PS3 (PS3HEN + webMAN MOD) från Macen.",
        discussion: """
        Exempel:
          ps3 status                   Temperatur, fläkt, utrymme och vad som körs
          ps3 send Spel.dec.iso        Ladda upp ett spel, uppdatera spellistan, visa popup
          ps3 games                    Spelen på PS3:an, med title ID, storlek och version
          ps3 games play gran          Starta ett spel från Macen
          ps3 queue add gran && ps3 queue start   Skicka spel från Macens spelmappar
          ps3 speedtest                Hur fort går det till PS3:an?
          ps3 apps                     Installerade program och tillgängliga uppdateringar
          ps3 apps info apollo         Version, om det fungerar på din PS3, README
          ps3 apps update              Granska och installera uppdateringar
          ps3 apps install X.pkg       Installera ett paket utan USB-sticka
        """,
        version: "0.1.0",
        subcommands: [Status.self, Send.self, Games.self, Queue.self, Apps.self, Speedtest.self, USB.self, Power.self, Disc.self, Fan.self, Pad.self, Screenshot.self, Serve.self,
                      Popup.self, Refresh.self, History.self, Discover.self, Config.self]
    )
}
