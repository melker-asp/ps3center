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
- **CI kontrollerar varje commit** i en pull request och på main. GitHub Actions
  (`.github/workflows/ci.yml`, macos-15) kör `swift test`, bygger CLI:t och bygger appen. Pusha
  och läs CI-resultatet i stället för att bygga lokalt. Med repo-variabeln `CI_RUNNER=self-hosted`
  går jobbet på användarens egen Mac i stället för GitHubs, och då kostar det inga Actions-minuter.
- **Skärmbilder:** CI renderar varje skärm från `Fixtures` (`PS3CENTER_FIXTURES=1`) och laddar upp
  dem som artefakten `screenshots`. Granska designändringar där. Nya skärmar läggs till i
  `Snapshot.run`, och data som behövs för dem i `Fixtures.swift`.
- **Rapportera med skärmbilder.** Är en fas eller en ändring som syns i appen klar, hämta
  artefakten `screenshots` från CI-körningen för den commiten. Skicka sedan de skärmar som är nya
  eller har ändrats tillsammans med rapporten (användarens önskan 24 okt 2026). Går CI inte att
  köra, säg det, och skicka inga gamla bilder som om de vore nya.
- **Konsolen finns bara på användarens hemnätverk.** Allt som kräver en riktig PS3 (snapshot,
  installationer, `ps3 status`) får användaren köra på sin Mac. Beskriv vad som ska provas.
- **CI kan ha en äldre Xcode** än användarens (Xcode 27 / Swift 6.4). Undvik helt nya API:er utan
  `if #available`.

## Arkitektur som kräver flera filer för att förstå

- **Hitta konsolen:** `ConsoleLocator` provar `--host`, sedan `PS3_HOST`, sedan sparad config och
  till sist en nätverkssökning (`Discovery`). En ny adress sparas i `~/.config/ps3center/config.json`,
  samma fil som appen läser.
- **webMAN:s egenheter** hanteras i `WebMAN.swift` och `FTPClient.swift`:
  - varje HTTP-anrop skickar `Connection: close` och körs ett i taget, utom kommandon som kan ta
    minuter (`/install.ps3`, `/stat.ps3`): de går via `WebMAN.long` på en egen anslutning och
    sätter `WebMAN.isBusy`, så att appen inte tar långsamma statussvar för att konsolen är borta
  - ENODATA på dataanslutningen betyder filslut
  - `APPE` fortsätter en avbruten uppladdning

  Ändra inget av detta utan att läsa avsnittet om fakta i DESIGN.md.
- **Spel som körs** känns av via PS3MAPI `PROCESS GETCURRENTPID` + `GETNAME`. Det driver
  "varna och vänta" (`TransferService.waitUntilIdle`): installation och uppdatering av spellistan
  väntar tills inget spel körs.
- **Installationen är klar** när `PARAM.SFO` i `/dev_hdd0/game/<titleID>` fått ny `MDTM` och mappen
  slutat ändras. webMAN tar *inte* bort paketet, trots vad wikin säger. Börjar inget hända skickas
  `/install.ps3` en gång till, sedan ett fel med råd. `ConsoleStore` går offline först efter tre
  missade statusanrop i rad.
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
- **Spelen** (`GameLibrary.swift`): `GameLibraryService.scan` listar webMAN:s spelmappar (PS3ISO,
  GAMES, PS2ISO …) på hdd0 och USB plus `/dev_hdd0/game`. Titel och title ID kommer ur PARAM.SFO,
  för ISO:er webMAN:s kopia i `/dev_hdd0/tmp/wmtmp`, och cachas i `~/Library/Caches/ps3center/`.
  `GameListing` är den nätverksfria delen som testerna matar med listningar. Installerade spel i
  `/dev_hdd0/game` startas via title ID och avinstalleras bara på begäran (`delete`, efter en
  fråga; `UninstallGuard` skyddar det HEN behöver). `GamesStore` och `GamesView` är Spel-fliken.
- **Macens spel och kön:** `GameFolders` (mappar per typ i config.json plus spegelmappen),
  `LocalLibrary` (samma `GameListing`-regler som konsolen, metadata ur avbilderna) och
  `LibraryMatch`. `TransferQueue` (queue.json) delas av `ps3 queue` och appens `TransferStore`;
  `QueueLock` ser till att bara en process skickar. Allt skickas via `TransferService.send`, som
  laddar upp till `.part` och döper om. `QueueRunner.send` och `ps3 send` försöker igen efter
  nätverksfel (`RetryPolicy`). `FolderWatch` (watch.json) hittar nya spel i bevakade mappar;
  appens `TransferStore` och `ps3 watch` lägger dem i kön. `FTPClient.Tuning` styr bitstorlek och
  antal bitar i luften (config.json `ftpChunkKB`/`ftpWindow`).
- **Spelservern** (`NetServer.swift`): en egen ps3netsrv som bara läser. Roten är de kopplade
  mapparna ihopslagna per typ (`/PS3ISO` …); `<namn>.SFO`/`.PNG` bredvid en PS3-ISO läses ur
  avbilden. Skrivande kommandon stänger anslutningen och bara konsolens adress släpps in. Ett
  Mac-spel har `netPath`, och appen startar det som `/net<slot>` + `netPath`. `NetServerStore`
  håller Macen vaken medan en `/net`-sökväg är monterad och ställer in webMAN med `WebMANSetup`
  (en ledig nätverksserver; numret sparas som `netServerSlot` i config.json).
- **Styrning** (`Control.swift`): `PadButton` (fasta namn till `/pad.ps3`), skiva, skärmbild,
  `FanControl` (bara mål i dynamiskt läge), `Reachability` (ping/TCP när webMAN inte svarar = HEN
  av) och `PlayLog`/`PlayTracker` (speltid ur statusen, `playtime.json`). Appen: `ConsoleStore`
  har knapparna, `RemoteView` fjärrkontrollen, `MenuBarView` menyraden. Filer utifrån (Finder-
  tjänsten, menyraden, Genvägar i `Intents.swift`) går via `Inbox` till granskningsvyn.
- **Underhåll** (`Maintenance.swift`): `SaveBackupService` (sparfiler till `Sparfiler/<användare>/
  <mapp>` med en manifest per mapp, förra kopian i `.tidigare`), `SystemFiles`, `MaintenanceService`
  (rapport + `fix` som bara tar bort paket och `.part`), `StorageAnalyzer` (`/stat.ps3`) och
  `DiscRipper` (`/copy.ps3`, förlopp över FTP). Appen: `MaintenanceStore` och `MaintenanceView`.
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
- **Speluppdateringar** får hämtas från Sonys officiella uppdateringsserver, som RPCS3 gör: bara
  spelpatchar, aldrig firmware (PUP), utan PSN-inloggning, och en patch som kräver nyare
  systemprogramvara än konsolens blockeras. Inget får kunna uppdatera konsolen eller leda till ban
  (användarens beslut 24 okt 2026).
- **Brewology** ligger bakom ett Cloudflare-skydd och ska inte kringgås. Program som bara finns där
  får en länk.
- **Ur sparfilernas PARAM.SFO visas bara TITLE och SUB_TITLE,** aldrig konto-fälten.
- **boot_plugins.txt ändras aldrig av PS3 Center;** saknade plugins rapporteras bara.
- **Fläkten ändras bara som mål i webMAN:s dynamiska läge, 60–75 °C,** aldrig som fast hastighet.
- **Ingen fri text till `/pad.ps3`:** "cross=" byter OK-knapp och startar om konsolen.
- **Avinstallation och radering:** bara en mapp direkt i `/dev_hdd0/game`, aldrig det HEN behöver
  (`UninstallGuard`), aldrig medan ett spel körs, alltid efter en fråga. En sparfil kopieras till
  Macen innan den tas bort från konsolen.
- **webMAN:s inställningar ändras bara via `WebMANSetup`:** hela formuläret som Safari skulle
  skicka, en kopia av inställningarna först och en kontroll efteråt. Ett ofullständigt anrop till
  `/setup.ps3` nollställer alla andra inställningar.
- **Allt som ändrar konsolen loggas** med `OperationLog.record`, som visas med `ps3 history` och i
  appens historiktabell, och har `--dry-run` i CLI:t.
