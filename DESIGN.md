# PS3 Center – design och arkitektur

Förebild: [Mole](https://github.com/tw93/mole). Mole är ett öppet CLI (`mo`) som gör jobbet,
plus en separat Mac-app som visar samma funktioner som flikar. PS3 Center följer samma idé,
men med **en** gemensam motor i stället för två kodbaser.

```
PS3Kit (Swift-bibliotek)   ← all logik: webMAN, FTP, ISO/SFO/PKG, uppdateringar
 ├── ps3   (CLI)           ← det här, version 0.1
 └── PS3 Center.app        ← SwiftUI, kommer sen – länkar PS3Kit direkt
```

CLI:t skriver också JSON (`--json`, och automatiskt när utdata skickas vidare), och
`ps3 status --watch --json` strömmar NDJSON. Det gör att widgets, Raycast eller Claude kan
läsa samma data utan appen.

## Principer från Mole

| Mole | PS3 Center |
|---|---|
| `mo status` är skrivskyddat | `ps3 status` läser bara |
| `--dry-run` före allt som ändrar något | `send`, `apps update` och `apps install` har `--dry-run` |
| Frågar innan ändringar, `--yes` hoppar över frågan | `apps update` frågar per program, `-y` svarar ja |
| Skyddade sökvägar rörs aldrig | HEN och plugins installeras aldrig automatiskt, bara råd |
| `~/Library/Logs/mole/operations.log` + `mo history` | `~/Library/Logs/ps3center/operations.log` + `ps3 history` |
| `~/.config/mole/` | `~/.config/ps3center/config.json` (delas med appen) |
| JSON automatiskt när utdata skickas vidare | Samma sak för `status`, `apps` och `history` |
| ➤ rubriker, ✓ ◎ → markörer, hälsopoäng 0–100 | Samma stil |

Egen regel: **säkerhetsspärren**. Varje program i katalogen kan ha krav (`Requirements`: HEN
eller CFW, CEX eller DEX, lägsta och högsta firmware). Innan något installeras läses konsolens
firmware och program som inte fungerar blockeras, i appen, i `apps install` och `apps update`,
och för egna .pkg-filer vars title ID finns i katalogen. Kan firmwaren inte läsas blockeras
program som har krav; program utan krav påverkas aldrig. "Otestad" (t.ex. PS3 Health på CFW)
varnar men blockerar inte. Kraven skrivs in från programmets README eller releaseanteckningar.

Egen regel: **"varna och vänta"**. Det som påverkar konsolen (installera, uppdatera spellistan)
väntar tills inget spel körs. Uppladdningar börjar direkt. `--force` kör ändå.

## Kommandon ↔ flikar i appen

| Flik | CLI | Innehåll |
|---|---|---|
| **Status** | `ps3 status` | Kort: Hälsa, CPU, RSX, Fläkt, Ledigt, Nätverk, Spelar nu, versioner (FW/HEN/webMAN) |
| **Spel** | `ps3 games`, `ps3 send` | Bibliotek Mac ↔ PS3, dra och släpp för att skicka, montera/starta, ta bort |
| **Appar** | `ps3 apps`, `apps available`, `apps info`, `apps update`, `apps install` | Som Moles Apps → Updates: "02.40 → 02.41", Uppdatera / Ignorera / Uppdatera alla. Fliken "Hämta" visar `apps available`, grupperad som System, Program och webMAN-tillägg. Ett klick på en rad öppnar detaljsidan (`apps info`): version, kompatibilitet med konsolen och README med bilder |
| **Underhåll** | senare `ps3 maintain` | Kontroller som Moles Optimize: boot_plugins.txt, hen_updater.off, kvarglömda pkg, webMAN-cache – en rapport med Klart/Hoppade över och skälet |
| **Analys** | senare `ps3 analyze` | Trädkarta över /dev_hdd0 (som Moles Analyze) |
| **Menyraden** | `ps3 status --watch` | Kompakt status + snabbknappar (Skicka fil, Uppdatera spellista, Stäng av) |

## Utseende (Moles struktur, PS-appens färger)

Från Mole: layouten. Från PlayStation-appen: färger, knappar och känsla. Alla värden finns i
`Theme.swift`.

- **Bas:** blåsvart som PS-appens mörka läge, med startskärmens snedställda ljusytor
  (`FacetBackground`). Varje flik tonas med ett av PS-appens teman: Status Starlight Blue,
  Spel Nova Pink, Appar Galactic Purple, och senare Underhåll Cosmic Red.
- **Färger:** PlayStation-blått för det man kan agera på (ikoner, länkar, förlopp), PS-appens
  gröna för närvaro, badges och "bra", gult och rött för varningar.
- **Flikar** som piller centrerade högst upp, som PS-appens segmentkontroll: mörk kapsel, ljusare
  vald kapsel, gröna sifferbadges. Logotypen på en PS-blå skiva med grön prick när konsolen svarar.
- **Knappar:** vit med svart text för huvudåtgärden ("Installera", som "Köp nu"), kontur för
  sekundära, runda konturknappar för ikoner.
- **Etiketter** som PS-appens "PS5": fet text på en liten svart platta.
- **Typsnitt:** stora tal, sidrubriker och programnamn i tunn vikt (PS-appens SST finns inte på
  Macen, så det är SF Pro).
- **Kort:** liten versal rubrik med ikon, chip i hörnet (t.ex. "Wi-Fi", "Normal"), stort tal med
  enhet, en sparkline eller stapel och en grå fotnot.
- **Laddning och förlopp:** tunn ring (`Spinner`) och PS-appens lagringsstapel (`PSProgressBar`),
  inte `ProgressView`, som inte går att rendera till skärmbilder.
- **Startskärm:** anslutningsskärmen är PS-appens blå startskärm med vit logga (`SplashBackground`).
- **Bilder:** Spelar nu visar spelets ICON0/PIC1 från `/dev_bdvd/PS3_GAME` (`GameArt`), och
  detaljsidan har en banderoll som PS Store med programmets PIC1.PNG eller README:ns första bild.
  Hämta är ett rutnät av kort som PS-appens bibliotek.
- **Utseende** (kugghjulet uppe till höger): PS-appens teman. "Följ fliken" (standard) ger varje
  flik sin färg; Starlight Blue, Nova Pink, Cosmic Red, Galactic Purple och Midnight Black färgar
  alla flikar lika. Sparas som `theme` i `config.json`.
- Hjältebild som speglar hälsan. Mole använder en planet; här kan det vara konsolen eller en
  skiva som lyser i hälsofärgen.
- Granskningsvy före ändringar: grupper med kryssrutor och storlek, och en vit huvudknapp som
  säger exakt vad som händer ("Installera 2 uppdateringar").
- Detaljrapport efteråt: Klart / Hoppade över, med skälet högerställt i grått.

## Fakta om konsolen som koden bygger på

- **webMAN hänger sig på återanvända HTTP-anslutningar.** Varje anrop skickar `Connection: close`
  och körs ett i taget. Parallella anrop tar 4+ sekunder styck medan ett spel körs.
- **Spel som körs** läses via PS3MAPI `PROCESS GETCURRENTPID` + `GETNAME` (`…_EBOOT.BIN` = spel,
  `vsh.self` = XMB). `GETALLPID` skickar trasig JSON.
- **FTP:** `SIZE` fungerar. Avbrutna uppladdningar fortsätter med `APPE`. När PS3:an stänger en
  dataanslutning kommer det som ENODATA i stället för filslut.
- **FTP enligt webMAN:s källkod** (`include/ftp.h`, läst 24 okt 2026, inte provat på konsolen än):
  bryts dataanslutningen med ett fel, eller kommer inget data på 60 sekunder (eller den tidsgräns
  som är inställd), räknas uppladdningen som misslyckad och filen tas bort. Bara en ren stängning
  (FIN, som vid ctrl-C) lämnar den halvfärdiga filen kvar så att `APPE` kan fortsätta. Högst två
  överföringar åt gången (`MAX_FTP_TRANSFERS`). `REST`, `RNFR`/`RNTO`, `MDTM`, `MFMT` och
  `SITE SHUTDOWN` finns.
- **Automatisk avstängning:** under en FTP-session, `/install.ps3` och `/download.ps3` stänger
  webMAN tillfälligt av konsolens "Stäng av automatiskt" och slår på den igen efteråt
  (`include/init/autopoweroff.h`).
- **`/md5.ps3/<sökväg>`** visar en fils MD5 på konsolen. **`/play.ps3/<sökväg>`** monterar och
  startar, **`/play.ps3?<title ID>`** startar ett installerat spel från dess ikon, **`/xmb.ps3$exit`**
  avslutar spelet, **`/shutdown.ps3`** stänger av (webMAN:s wiki). RMD tar bort mappar rekursivt i
  bygget med filhanteraren (`COPY_PS3`).
- **Omslag:** PS3 och PSN från `aldostools/Resources/COV/<ID>.JPG` (webMAN:s onlineomslag, 260×300)
  och GameTDB `art.gametdb.com/ps3/coverM/<EN|US|JA>/<ID>.jpg` (350×408). PS2 och PS1 från
  `xlenore/ps2-covers` och `psx-covers` (`covers/default/<SLES-12345>.jpg`), som deras README
  föreslår för PCSX2:s omslagshämtare. Inga källor för PSP. Alla svarade 24 okt 2026.
- **Speluppdateringar:** listan per spel är `https://a0.ww.np.dl.playstation.net/tpl/np/<ID>/<ID>-ver.xml`
  (`<package version size sha1sum url ps3_system_ver>`), paketen ligger på `http://b0.ww.np…` och
  servern svarar 403 på HTTP för listan. Servrarna har certifikat från Sonys egen CA ("SCEI"), som
  macOS inte litar på, så `SonyTrust` godtar för just de värdarna en kedja från Sonys CA och sparar
  dess fingeravtryck första gången. Varje paket kontrolleras mot SHA-1 i listan. Inte provat från
  en Mac än; från molnsessionen gick servern inte att nå.
- **Överföringar (PS3 Center):** filer laddas upp till `<namn>.part` och döps om med `RNFR`/`RNTO`
  när storleken stämmer, så webMAN aldrig listar ett halvt spel. En fil med det riktiga namnet som är
  mindre (från före `.part`) fortsätter med `APPE` som förut. Paus och viloläge stänger
  dataanslutningen med FIN (`NWConnection.cancel()`), som webMAN behandlar som ett rent slut och
  behåller filen. FTP-sessionen stängs innan något långt väntande (ett spel som körs, MD5), eftersom
  webMAN släpper en session som är tyst i en minut.
- **Spellistan och cachen:** webMAN skriver XMB:ns spellista till
  `/dev_hdd0/xmlhost/game_plugin/mygames.xml` och sparar titel och ikon för ISO:er som
  `<namn>.SFO`/`<namn>.PNG` i `/dev_hdd0/tmp/wmtmp` (`include/scan/`, bekräftas med test 1 i
  PLAN.md). För nätverksspel hämtar den `<namn>.SFO` bredvid ISO:n från ps3netsrv-servern.
- **`/cpursx.ps3` visar PSID/IDPS.** De sparas och visas aldrig.
- **Paketinstallation:** `/install.ps3/<sökväg>` installerar, men tar *inte* bort .pkg-filen
  som wikin påstår (provat 24 okt 2026). Verktyget vet att installationen är klar när
  `PARAM.SFO` i `/dev_hdd0/game/<title ID>/` fått en ny `MDTM`-tidsstämpel och mappen sedan
  inte ändrats på två kontroller i rad. Därefter tar verktyget bort sin kopia av paketet.
  Ominstallation av Apollo tog 11 sekunder.
- **`/refresh.ps3` och `/popup.ps3`** svarar OK direkt, även med åäö i texten (provat 24 okt 2026).
- **Brewology** ligger bakom ett Cloudflare-skydd mot automatiska anrop och kringgås inte.
  Program som bara finns där får en länk.
- **Firmwareraden** i PS3MAPI `PS3 GETSYSINFO` kommer från webMAN:s `get_cobra_version`
  (`include/cpursx.h`): `Firmware : 4.93 CEX PS3HEN 3.5.0` på HEN och `4.92 CEX Cobra 8.4`,
  `4.92 DEX Mamba 8.4` eller `qCFW` på CFW. Typen är `CEX`, `DEX` eller `DECR`; på Evilnats
  PEX/D-PEX byts första bokstaven mot P, så `PEX` kan vara båda. Saknas `PS3HEN` är det CFW,
  eftersom webMAN bara körs på HEN eller CFW.
- **README** hämtas med GitHubs `/repos/<repo>/readme` (base64). Relativa bilder pekas om till
  `raw.githubusercontent.com`, badges (SVG, shields.io) tas bort och den HTML som många
  PS3-repon skrivs i (`<p align="center"><img …>`, `<h1>`, `<br>`) görs om till Markdown.
  IRISMAN:s README är Latin-1.
- **PS3HEN** har inga GitHub-releaser. Senaste versionen läses från `HEN_REV` i
  `payload/main.c` (0x0360 → 3.6.0).

## Färdplan

Planen framåt, fas för fas, finns i [PLAN.md](PLAN.md).

- **CLI 0.1 (klart):** `status`, `send`, `apps` (list/available/update/install via namn eller
  fil), `popup`, `refresh`, `history`, `discover`, `config`. Katalogen har 19 program. Nya
  kandidater granskas mot hur väletablerade de är; repon som är några veckor gamla med 1–2
  stjärnor tas inte med automatiskt.
- **Spel:** bara egna filer via `send`. Ingen inbyggd nedladdning från ROM-/ISO-arkiv.
  Planerat i stället: `ps3 rip` (kopiera skivan i spelaren med `/copy.ps3/dev_bdvd`),
  Finder-åtgärden "Skicka till PS3" och en bevakad mapp.
- **Spelbiblioteket (fas 1, påbörjad):** `ps3 games` (lista, info, starta, montera, avsluta, ta
  bort) och Spel-fliken med rutnät och detaljsida. Se PLAN.md för vad som återstår.
- **CLI härnäst:** `maintain`, `analyze`,
  `backup-saves`, `plugin add/remove` (säker ändring av boot_plugins.txt), en interaktiv meny
  när `ps3` körs utan argument, och Finder-åtgärden "Skicka till PS3".
- **App 0.1 (klar):** Xcode-projekt genererat från `App/project.yml` som länkar PS3Kit, Swift 6
  strikt läge, flikarna Status och Appar, och skärmbildsläget (`PS3CENTER_SNAPSHOT_DIR`).
- **Skärmbilder utan PS3 (klart):** `PS3CENTER_FIXTURES=1` ger appen data från PS3Kit:s
  `Fixtures`; CI renderar varje skärm och laddar upp PNG:erna som artefakten `screenshots`.
- **PS-utseende (klart):** se avsnittet Utseende ovan.
- **App härnäst:** omslag och Macens spelmappar med dra-och-släpp i Spel-fliken (fas 2 och 3),
  menyraden och en appikon.
