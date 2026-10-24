# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projektet

PS3 Center styr en PS3 (Super Slim, HFW 4.93, PS3HEN, webMAN MOD) från en Mac: status, uppladdning av
spel, installation och uppdatering av homebrew. Användaren skriver svenska; all text i CLI, app och
dokumentation är på svenska. Kod, identifierare och kommentarer skrivs på engelska.

Inspirationen är Mole (ett CLI med en separat Mac-app). Här delar CLI och app samma motor. Läs
`DESIGN.md` innan du lägger till funktioner: den har principerna, flikarna och fakta om konsolen som
koden bygger på. `PLAN.md` har färdplanen fas för fas och vad som ska provas på konsolen.

```
Sources/PS3Kit/   bibliotek med all logik (webMAN-HTTP, FTP, ISO/SFO/PKG, katalog, uppdateringar)
Sources/ps3/      CLI:t (swift-argument-parser), tunt lager ovanpå PS3Kit
App/              SwiftUI-appen; App/project.yml → xcodegen → App/PS3Center.xcodeproj (inte incheckad)
Tests/            swift-testing, fixturer från riktiga svar från konsolen
```

## Kommandon

```bash
swift build                     # PS3Kit + CLI
swift test                      # alla tester
swift test --filter parsesSysInfoAndStatusPage   # ett test
make install                    # release-CLI → ~/.local/bin/ps3
make app                        # xcodegen + xcodebuild (kräver `brew install xcodegen`)
make run-app                    # bygg och öppna appen
make snapshot DIR=/tmp/shots    # rendera varje flik till PNG och avsluta (kräver nåbar PS3)
make snapshot-fixtures DIR=/tmp/shots   # samma sak från PS3Kit:s Fixtures, utan PS3
```

Lägger du till en fil i `App/Sources` måste projektet genereras om (`make project`), annars hittar
xcodebuild den inte.

## I en molnsession (Linux)

- **Bara macOS kan bygga.** PS3Kit använder Network.framework och CryptoKit, och appen är SwiftUI,
  så varken `swift build` eller `swift test` fungerar på Linux.
- **CI kontrollerar varje push.** GitHub Actions (`.github/workflows/ci.yml`, macos-15) kör
  `swift test`, bygger CLI:t och bygger appen. Pusha och läs CI-resultatet i stället för att bygga
  lokalt.
- **Skärmbilder:** CI renderar varje skärm från `Fixtures` (`PS3CENTER_FIXTURES=1`) och laddar upp
  dem som artefakten `screenshots`. Granska designändringar där. Nya skärmar läggs till i
  `Snapshot.run`, och data som behövs för dem i `Fixtures.swift`.
- **Konsolen finns bara på användarens hemnätverk.** Allt som kräver en riktig PS3 (snapshot,
  installationer, `ps3 status`) får användaren köra på sin Mac. Beskriv vad som ska provas.
- **CI kan ha en äldre Xcode** än användarens (Xcode 27 / Swift 6.4). Undvik helt nya API:er utan
  `if #available`.

## Arkitektur som kräver flera filer för att förstå

- **Hitta konsolen:** `ConsoleLocator` provar `--host`, sedan `PS3_HOST`, sedan sparad config och
  till sist en nätverkssökning (`Discovery`). En ny adress sparas i `~/.config/ps3center/config.json`,
  samma fil som appen läser.
- **webMAN:s egenheter** hanteras i `WebMAN.swift` och `FTPClient.swift`:
  - varje HTTP-anrop skickar `Connection: close` och körs ett i taget
  - ENODATA på dataanslutningen betyder filslut
  - `APPE` fortsätter en avbruten uppladdning

  Ändra inget av detta utan att läsa avsnittet om fakta i DESIGN.md.
- **Spel som körs** känns av via PS3MAPI `PROCESS GETCURRENTPID` + `GETNAME`. Det driver
  "varna och vänta" (`TransferService.waitUntilIdle`): installation och uppdatering av spellistan
  väntar tills inget spel körs.
- **Installationen är klar** när `PARAM.SFO` i `/dev_hdd0/game/<titleID>` fått ny `MDTM` och mappen
  slutat ändras. webMAN tar *inte* bort paketet, trots vad wikin säger.
- **Katalogen** (`Catalog.swift`): varje program har ett title ID, läst ur pkg-huvudet vid offset
  0x30. `AppsService` jämför installerad `APP_VER` med GitHub-releasen. Har PS3 Center själv
  installerat programmet används kopplingen tagg ↔ `APP_VER` i `installed.json` i stället för
  `VersionStyle`.
- **Säkerhetsspärren** (`Compatibility.swift`): `ConsoleProfile` läses ur snapshoten (HEN/CFW,
  CEX/DEX, firmware) och jämförs med `CatalogEntry.requirements`. `AppsService.status` sätter
  `compatibility`/`blocked` och nollar `canInstall`/`installable`; `AppsService.install` och CLI:ts
  `apps install` (även egna .pkg via title ID) stoppar före nedladdning. Okänd firmware blockerar
  program med krav.
- **Detaljsidan:** `AppsStore.selectedID` öppnar `AppDetailView` i Appar-fliken. README hämtas med
  `GitHub.readme` och tolkas av `Readme` (block + inline-Markdown som `AttributedString` ritar).
  Samma data visar `ps3 apps info`.
- **Förlopp:** `TransferEvent` går via `@Sendable`-callbacks. CLI:t skriver ut dem (`TransferPrinter`),
  appen lägger dem i `AppsStore.operations` på MainActor.
- **Appen:** `ConsoleStore` hämtar status var 3:e sekund, `AppsStore` har en installationskö som tar
  ett program i taget eftersom webMAN:s FTP inte klarar parallella överföringar. Designtokens finns i
  `Theme.swift` (Mole-stil).

## Regler

- **Krav i katalogen ska ha en källa** (README, releaseanteckningar). Gissa inte att något kräver
  CFW; ett felaktigt krav blockerar ett program som fungerar.
- **HEN och plugins (ds45pad) installeras aldrig automatiskt.** De får bara `notifyOnly` med råd.
  En trasig sprx kan få konsolen att frysa vid start.
- **Spara eller visa aldrig PSID/IDPS.** `/cpursx.ps3` innehåller dem.
- **Ingen inbyggd nedladdning av spel från ROM- eller ISO-arkiv.** `send` tar användarens egna filer.
- **Brewology** ligger bakom ett Cloudflare-skydd och ska inte kringgås. Program som bara finns där
  får en länk.
- **Allt som ändrar konsolen loggas** med `OperationLog.record`, som visas med `ps3 history` och i
  appens historiktabell, och har `--dry-run` i CLI:t.
