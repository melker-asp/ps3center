# PS3 Center – färdplan mot den kompletta kommandocentralen

Den här planen tar PS3 Center från "status och homebrew" till ett ställe där allt som rör PS3:an
görs från Macen: se och starta spelen, skicka spel från Macens mappar, spela direkt från Macen,
styra konsolen och ta säkerhetskopior. Principerna i [DESIGN.md](DESIGN.md) gäller för allt nytt.

## Var vi står (oktober 2026)

Klart:
- **CLI:** `status`, `send`, `apps` (19 program, säkerhetsspärr, detaljsida), `popup`, `refresh`,
  `history`, `discover`, `config`.
- **Appen:** flikarna Status och Appar i PS-utseende, skärmbilder från fixturer i CI.
- **Motorn:** webMAN-HTTP, FTP med `APPE`, ISO/SFO/PKG-läsning, `FileRouter` som vet var varje
  filtyp ska ligga, "varna och vänta", `OperationLog`.

Saknas för en kommandocentral:
1. Se vilka spel som finns på PS3:an, med omslag, och starta dem.
2. Koppla Macens spelmappar (PS3ISO, PS2ISO …) och skicka därifrån.
3. Överföringar som tål avbrott, en kö och besked om hur lång tid det tar.
4. Spela utan att kopiera (ps3netsrv).
5. Ström, avsluta spel, fjärrkontroll, menyraden och notiser.
6. Säkerhetskopior av sparfiler och underhåll av hårddisken.

## Målbild

| Var | Innehåll |
|---|---|
| **Status** | Som nu, plus strömknappar (Stäng av, Starta om, Avsluta spel) |
| **Spel** (ny, Nova Pink) | Omslagsrutnät som PS-appens bibliotek. Två lägen: *På PS3:an* och *På Macen*. Detaljsida med banderoll, Spela / Montera / Ta bort / Skicka |
| **Appar** | Som nu |
| **Underhåll** (ny, Cosmic Red) | Sparfiler, systemfiler, städning, lagringskarta |
| **Överföringar** | En låda som nås från alla flikar (badge i flikraden): kö, hastighet, tid kvar, "när kön är klar" |
| **Menyraden** | Status, kö-förlopp och snabbknappar; håller kön och spelservern igång när fönstret är stängt |

CLI:t får samma funktioner: `ps3 games`, `ps3 queue`, `ps3 speedtest`, `ps3 power`, `ps3 saves`,
`ps3 maintain`, `ps3 analyze`.

---

## FTP, väntetider och att låta PS3:an stå på

### Varför det tar så lång tid

- **Wi-Fi är den största bromsen.** PS3:an har bara 2,4 GHz-Wi-Fi, och enligt svaren från din
  konsol (fixturerna) sitter den på Wi-Fi ("WLAN"). Rapporter från forum (inte egna mätningar)
  spänner från under 1 till runt 15 MB/s över Wi-Fi och 10–40 MB/s med kabel; test 4 under
  Prova ger dina siffror. Exempel: Test Drive Unlimited 2 (9,6 GB) tar knappt en timme i 3 MB/s
  och runt 6–7 minuter i 25 MB/s.
- **webMAN klarar högst två överföringar samtidigt** (`MAX_FTP_TRANSFERS 2` i `include/ftp.h`), så
  det finns lite att vinna på att köra flera parallellt. Det provas ändå (test 5 under Prova).
- **Vår egen klient** skickar 256 KB åt gången och väntar på varje bit. Det kan kosta lite; det
  mäts i fas 5 innan något ändras.

### Tre sätt att få in spel

| | FTP till hårddisken (`send`) | USB-disk | Spela från Macen (ps3netsrv) |
|---|---|---|---|
| Hastighet | Wi-Fi: långsamt. Kabel: bra | Snabbast för många spel | Ingen kopiering alls |
| Macen måste vara på | Under överföringen | Nej | Hela tiden man spelar |
| Bäst för | Spel man behåller | Att fylla på många spel på en gång | Att prova spel, PS1/PSP, stora bibliotek |
| Begränsning | Avbrott kan kosta hela filen (se nedan) | FAT32: filer över 4 GB delas i `.iso.0`, `.iso.1` … | Kabel behövs för PS3-spel; PS2-ISO:er kopieras ändå till hårddisken när de monteras |

Planen bygger alla tre (fas 3–6), men **den enskilt största förbättringen kostar ingen kod: en
nätverkskabel till PS3:an.** Räcker inte routern fram går det att koppla en kabel direkt mellan
Macen (USB-C-adapter) och PS3:an, eller använda en enkel switch eller powerline-adaptrar.

### Ska PS3:an alltid stå på?

Fakta som avgör:
- **HEN måste aktiveras efter varje start.** Det enda PS3:an vinner på att stå på är att den
  alltid är redo. Även om den gick att väcka på distans skulle någon behöva trycka på HEN-ikonen.
- **PS3:an kan inte väckas från Macen.** Den har inget vanligt Wake-on-LAN. Fjärrstart i Remote
  Play-inställningarna är gjord för PSP och Vita.
- **webMAN stänger av "Stäng av automatiskt" under en FTP-session** och vid `/install.ps3` och
  `/download.ps3`, och slår på den igen efteråt (`include/init/autopoweroff.h`). En lång
  överföring stängs alltså inte av av konsolen själv.
- **Om Macen somnar mitt i en överföring raderar PS3:an den halvfärdiga filen.** webMAN väntar
  60 sekunder på data; sedan räknas överföringen som misslyckad och filen tas bort
  (`cellFsUnlink` i `include/ftp.h`). Bara när anslutningen stängs ordentligt (som med ctrl-C)
  ligger filen kvar så att `APPE` kan fortsätta.
- **Ström:** ingen mätning av Super Slim i viloläge hittades. Räknat på 50 W blir dygnet runt
  ungefär 440 kWh per år, alltså 400–900 kr beroende på elpris. Till det kommer fläkt, damm och en
  hårddisk som aldrig vilar. En energimätare i uttaget ger det riktiga värdet.

Rekommendation: **inte dygnet runt, utan i omgångar.** Starta PS3:an, aktivera HEN, lägg spelen i
kön och låt PS3 Center göra resten: Macen hålls vaken så länge kön går, PS3:an stängs av när kön
är klar och Macen får somna igen. Det blir "nattläget" i fas 4. Om PS3 Center någon gång ska vara
spelserver hela tiden (fas 6) är det i stället Macen som behöver stå på, och då är en Mac mini
eller en NAS bättre än en bärbar.

För Macen gäller:
- En bärbar Mac på batteri somnar när locket stängs, vad appen än gör. Med laddare och extern
  skärm går det bra.
- Appen och `ps3 send` ska själva hindra att Macen somnar medan kön går (som `caffeinate -i`).
  Skärmen får släckas.

---

## Faser

Varje fas blir en PR. Varje ny skärm läggs till i `Snapshot.run` med data i `Fixtures.swift`, så att
CI-artefakten `screenshots` visar den. Allt som ändrar konsolen loggas med `OperationLog.record`
och har `--dry-run` i CLI:t.

### Fas 1 – Spelbiblioteket på PS3:an

**Mål:** se alla spel på konsolen med ikon, titel, title ID, storlek och plats, och starta dem.

**Läge 24 okt 2026:** byggt utan tester på konsolen, med reservvägar där fakta saknas. Klart är
listningen (steg 2 nedan plus wmtmp-cachen), ikoner och bakgrunder, starta/montera/avsluta/ta bort,
`ps3 games` och Spel-fliken med detaljsida. Kvar: `mygames.xml` (väntar på test 1), läsning i ISO:n
via `REST` (väntar på test 2), sortering på storlek och datum, och att `send` sparar det den vet.

PS3Kit:
- `Game.swift`: `Game` (titel, title ID, plattform, region, storlek, sökväg) med `Game.Platform`
  (PS3, PSN, PS2, PS1, PSP, Blu-ray, DVD). Regionen läses ur title ID: `BLES`/`SLES` = Europa,
  `BLUS`/`SLUS` = USA osv. Platser på Macen kommer i fas 3.
- `GameLibrary.swift` (`GameLibraryService`) hittar spelen i tre steg, billigast först:
  1. **webMAN:s egen lista** `/dev_hdd0/xmlhost/game_plugin/mygames.xml` (titel, ikon och sökväg
     eller title ID per spel) och dess cache i `/dev_hdd0/tmp/wmtmp` (`<namn>.SFO`, `<namn>.PNG`).
     Formatet kontrolleras mot en riktig fil först (test 1 under Prova).
  2. **FTP-listning** av `PS3ISO`, `GAMES`, `GAMEZ`, `PS2ISO`, `PSXISO`, `PSPISO`, `BDISO`, `DVDISO`
     på `/dev_hdd0` och `/dev_usb00*`, med en nivå undermappar som webMAN. Ger storlek och `MDTM`.
  3. **Läs i ISO:n på konsolen** när inget annat finns: `ISOImage` får en `ByteSource` så att samma
     kod läser lokala filer och, via FTP `REST` + `RETR`, bara de sektorer som behövs
     (PVD, kataloger, `PARAM.SFO`, `ICON0.PNG`). webMAN har `REST` enligt källkoden.
- PSN-spel och speluppdateringar ur `/dev_hdd0/game/*/PARAM.SFO`: `CATEGORY` `HG` är ett spel,
  `GD` är data eller en uppdatering som kopplas till spelet med samma title ID ("uppdatering
  1.05 installerad"). Program från katalogen och homebrew-ID:n hålls utanför.
- Metadata per format: PS3 `PARAM.SFO`; PS2 `SYSTEM.CNF` (`BOOT2` → `SLES-12345`); PS1 `SYSTEM.CNF`
  i `.bin` med 2352-byte-sektorer (`ISOImage` behöver läget MODE2); PSP `UMD_DATA.BIN` och
  `PSP_GAME/PARAM.SFO`.
- Cache i `~/Library/Caches/ps3center/` (lista + ikoner), nyckel sökväg + storlek + `MDTM`. En ny
  läsning blir bara en listning.
- `send` sparar det den redan vet om spelen den skickar (title ID, titel, ikon), så att de spelen
  aldrig behöver läsas på konsolen.
- `GameLibraryService` styr också: montera (`/mount.ps3/<sökväg>`), starta (`/play.ps3/<sökväg>`,
  installerade spel med `/play.ps3?<title ID>`), avmontera (`/mount.ps3/unmount`), avsluta spelet
  (`/xmb.ps3$exit`), ta bort (FTP `DELE`/`RMD`). Installerade spel tas aldrig bort av PS3 Center.

CLI:
- `ps3 games` (gruppering per plattform, `--platform ps2`, `--json`), `ps3 games info <namn>`.
- `ps3 games play <namn>`: körs ett annat spel frågar den om det ska avslutas (`-y` hoppar
  över frågan). `ps3 games mount|unmount|exit`.
- `ps3 games delete <namn>` med fråga, `--dry-run` och logg.

Appen:
- `GamesStore` och `GamesView`: rutnät med XMB-ikonerna (320×176), filterpiller (Alla, PS3, PS2,
  PS1, PSP, Film), sök och sortering (namn, storlek, senast tillagt). Spelet som körs markeras.
- `GameDetailView` återanvänder `HeroBackdrop` med spelets `PIC1.PNG`. Vit huvudknapp "Spela",
  konturknappar Montera och Ta bort (med bekräftelse).
- Fixturer: en handfull spel av varje sort. Ikonerna ritas som färgade platshållare i appen, så att
  CI inte behöver nätet. Skärmar: `games`, `games-detail`.

Klart när: `ps3 games` visar samma spel som XMB:n, och ett spel kan startas från appen.

### Fas 2 – Omslag

**Mål:** riktiga fodral i rutnätet, inte bara XMB-ikoner.

**Läge 24 okt 2026:** byggt. `CoverService` (källorna nedan, egen bild genom att dra den till
banderollen, `ps3 games covers --to-ps3`) och speluppdateringar från Sony (`GameUpdateService`,
`ps3 games updates|update`, "Sök uppdateringar" och en ruta på spelets sida). Rutnätet visar
fodral eller XMB-ikoner. Kvar att prova hemma: att Sonys server svarar och att certifikatet godtas.

- `CoverStore` i PS3Kit med källor per plattform, alla nycklade på title ID och sparade för gott i
  `~/Library/Caches/ps3center/covers/`:
  - PS3: spelets egen `ICON0`/`PIC1` (finns alltid), och fodral från GameTDB eller webMAN:s
    onlinekälla (DeViL303). Exakt URL och villkor tas fram ur webMAN:s källkod och GameTDB innan
    koden skrivs.
  - PS2 och PS1: samlingarna `xlenore/ps2-covers` och `xlenore/psx-covers` (samma som PCSX2 och
    DuckStation använder), nycklade på serienummer. README och licens läses först.
  - PSP: `ICON0` ur ISO:n tills en fodralkälla är vald.
- Byta omslag själv: dra en bild till detaljsidan.
- Valfritt: "Visa omslagen på PS3:an också" lägger fodralen som `<TITLEID>.JPG` i
  `/dev_hdd0/tmp/wmtmp/covers`, där webMAN letar (loggas, `--dry-run`).
- Rutnätet får valet Ikoner / Fodral.

### Fas 3 – Macens spelmappar och skicka därifrån

**Mål:** koppla mappar per typ och skicka spel med ett klick eller genom att dra dem till fönstret.

**Läge 24 okt 2026:** byggt: `GameFolders`, `LocalLibrary` (läser PARAM.SFO, SYSTEM.CNF och ICON0 ur
ISO:er och råa .bin-avbilder), `LibraryMatch`, läget Macen i Spel-fliken med urval, granskningsvy,
Spelmappar och dra-och-släpp; `ps3 config folder` och `ps3 games mac`. Bevakade mappar är byggda
(25 okt): `FolderWatch`, reglaget Bevaka i Spelmappar, `ps3 config folder watch` och `ps3 watch`.

- `config.json` får `folders`, en lista med mappar per typ:
  `{"PS3ISO": ["~/Spel/PS3"], "PS2ISO": ["/Volumes/Extern/PS2"], …}`. Spegelmappens
  `dev_hdd0/PS3ISO` osv. räknas med automatiskt, så den som redan har en spegelmapp behöver inte
  göra något.
- CLI: `ps3 config folder add PS3ISO ~/Spel/PS3`, `folder list`, `folder remove`.
- Appen: Inställningar → Spelmappar, en rad per typ med "Välj mapp…" eller dra in en mapp. En
  extern disk som inte är ansluten visas som "inte ansluten", inte som borttagen.
- `LocalLibrary` läser mapparna med samma metadata som fas 1 (snabbt, filerna är lokala), och läser
  om när något ändras (FSEvents).
- Matchning Mac ↔ PS3 på title ID och plattform, sedan storlek: *Bara på Macen*, *På båda*,
  *Bara på PS3:an*, *Avbruten uppladdning* (mindre på konsolen).
- Spel-fliken får lägena *På PS3:an* och *På Macen*. Markera flera → vit knapp "Skicka 3 spel ·
  24,1 GB" → en granskningsvy som i DESIGN.md: kryssrutor, ledigt utrymme före och efter, beräknad
  tid från den senast uppmätta hastigheten och varningar ("Wi-Fi: cirka 55 minuter, med kabel
  cirka 7").
- Dra filer eller mappar var som helst i fönstret → samma granskningsvy.
- Bevakad mapp (av som standard, per mapp): nya spel köas när filen slutat växa.

### Fas 4 – Överföringar som tål avbrott

**Mål:** inget går förlorat när Macen somnar eller nätet hackar, och kön sköter sig själv.

**Läge 24 okt 2026:** byggt: `TransferQueue` med lås, `.part` + `RNTO`, ren stängning vid paus och
viloläge, `KeepAwake`, MD5 via `/md5.ps3`, "När kön är klar" och notiser; `ps3 queue` och
Överföringar i appen. Nya försök efter nätverksfel är byggda (25 okt): `RetryPolicy` väntar 15 s,
30 s, 1, 2 och 4 minuter och fortsätter från `.part`-filen; har webMAN tagit bort den sägs det.

- `TransferQueue` i PS3Kit, sparad i `~/Library/Application Support/ps3center/queue.json`: lägg
  till, pausa, fortsätt, ändra ordning, ta bort. En överföring åt gången. Ett lås ser till att
  appen och CLI:t aldrig skickar samtidigt. CLI: `ps3 queue` (`list`, `start`, `pause`, `clear`).
- **Ladda upp till `<namn>.part` och byt namn när filen är klar** (`RNFR`/`RNTO`, som webMAN har).
  Då syns aldrig ett halvt spel i XMB:n, och en ofullständig fil går inte att ta för en hel.
- **Stoppa ordentligt:** paus, avbryt, när appen avslutas och när Macen ska somna
  (`NSWorkspace.willSleepNotification`) stängs dataanslutningen med FIN (`NWConnection.cancel()`,
  inte `forceCancel()`), så att webMAN behåller filen och `APPE` kan fortsätta. Efter väckning
  hittas konsolen igen och kön fortsätter.
- **Håll Macen vaken** med `ProcessInfo.beginActivity(options: .idleSystemSleepDisabled, …)` så
  länge kön går, i både appen och CLI:t. Tips i appen när Macen går på batteri.
- **Verifiering:** storleken kontrolleras som nu. Valfritt MD5: räknas på Macen medan filen läses
  (gratis) och jämförs med `/md5.ps3/<sökväg>` på konsolen, som tar några minuter för ett stort
  spel. På i nattläget, av annars.
- **Bryts anslutningen ändå** försöker kön igen med paus emellan och fortsätter från `SIZE`. Har
  webMAN raderat filen sägs det rakt ut ("PS3:an tog bort den halvfärdiga filen, börjar om").
- **När kön är klar:** Ingenting / Popup på TV:n / Stäng av PS3:an (`/shutdown.ps3`, loggas), plus
  en notis på Macen. CLI: `ps3 send … --shutdown-when-done`.

### Fas 5 – Snabbare: mät, finjustera och USB

**Läge 24 okt 2026:** `ps3 speedtest` (och knappen i Överföringar) och `ps3 usb prepare` är byggda.
Finjusteringen är byggd (25 okt): 1 MB-bitar och två i luften, inställbart med `ftpChunkKB` och
`ftpWindow` i config.json för att jämföra med hastighetstestet (test 13). Två filer samtidigt är
inte byggt.

- `ps3 speedtest` (och en knapp i Överföringar): skickar 256 MB från minnet till `/dev_hdd0/tmp`,
  hämtar tillbaka och tar bort filen. Visar MB/s åt båda hållen och om det är Wi-Fi eller kabel.
  Resultatet sparas och ger tidsberäkningarna i granskningsvyn.
- Finjustera klienten mot `curl` som jämförelse: större bitar (1–4 MB) och ett par sändningar i
  luften samtidigt. Två parallella uppladdningar (webMAN:s max) provas också. Bara det som
  mäts som snabbare behålls.
- Föreslå kabel när konsolen är på Wi-Fi och kön är större än ett par GB, med tiden för båda.
- **USB-vägen:** `ps3 usb prepare /Volumes/<disk>` (och "Förbered USB-disk" i Spel-fliken)
  kontrollerar att disken är FAT32, skapar `PS3ISO`, `PS2ISO`, `PSXISO`, `PSPISO`, `GAMES` och
  kopierar spelen. PS3-ISO:er över 4 GB delas i `.iso.0`, `.iso.1` … (högst 4 GB, lika stora delar
  utom den sista, enligt webMAN:s wiki). Spelmappar med en fil över 4 GB fungerar inte på FAT32
  och stoppas med ett besked.

### Fas 6 – Spela direkt från Macen (inbyggd ps3netsrv)

**Mål:** spelen i Macens mappar syns och startar på PS3:an utan att kopieras.

**Läge 24 okt 2026:** byggt: `NetServer` (läsning bara, de kopplade mapparna som rot, `.SFO`/`.PNG`
ur PS3-ISO:erna, bara konsolens adress släpps in), `ps3 serve`, Spelservern i Spel-fliken med
stegen för webMAN, "Spela från Macen" och Macen hålls vaken medan ett nätverksspel är monterat.
Testat mot en egen klient i `swift test`, inte mot konsolen eller den riktiga ps3netsrv än (test 10).
Menyraden kommer i fas 7.

webMAN har en inbyggd klient för ps3netsrv (`/net0`–`/net4`, port 38008). Protokollet är litet:
16 byte långa kommandon i big-endian (`OPEN_FILE` = 0x1224, `READ_FILE`, `READ_CD_2048_CRITICAL`,
`STAT_FILE`, `OPEN_DIR`, `READ_DIR` …), definierade i `include/netiso.h` i aldostools/ps3netsrv.

- `NetServer` i PS3Kit på `NWListener`, med bara läsande kommandon. Skrivande kommandon får fel,
  så konsolen kan aldrig ändra något på Macen.
- **Den virtuella roten är de kopplade mapparna från fas 3**, ihopslagna till `/PS3ISO`,
  `/PS2ISO` osv. Bredvid varje PS3-ISO skapas `<namn>.SFO` och `<namn>.PNG` i farten, eftersom
  webMAN hämtar dem från servern för titel och ikon. Med den vanliga ps3netsrv måste man ta fram
  dem själv.
- Bara konsolens IP-adress släpps in.
- Tester: inspelade paket, och en jämförelse mot den riktiga ps3netsrv byggd från källkod.
- Inställning på PS3:an: webMAN:s `/setup.ps3` → nätverksserver 1 = Macens IP och 38008. Appen
  visar stegen och kontrollerar att det fungerar. Macen behöver en fast IP (reservera adressen i
  routern).
- Appen: märket "Från Macen" på spelen, Spela → `/play.ps3/net0/PS3ISO/<fil>`. Macen hålls vaken
  medan ett nätverksspel är monterat. Menyraden håller servern igång när fönstret är stängt.
- Begränsningar att visa: PS3-spel bör gå över kabel, och PS2-ISO:er kopieras till hårddisken när
  de monteras (webMAN:s wiki).

### Fas 7 – Styr konsolen

**Läge 24 okt 2026:** byggt: strömraden i Status-fliken och `ps3 power`/`ps3 disc`, "På men HEN är
av" (ping eller TCP-svar utan webMAN), fjärrkontrollen med XMB-bild och `ps3 pad`/`ps3 screenshot`,
fläktmålet (`ps3 fan`), menyraden med inloggningsobjekt, notiser (kön, värme, programuppdateringar),
"Skicka till PS3" i Finder, Genvägar och speltid. Kvar att prova hemma: test 7, 8 och 11.

- **Ström:** Stäng av (`/shutdown.ps3`), Starta om (`/restart.ps3`) med varningen "HEN måste
  aktiveras igen efter omstarten", Avsluta spel, Mata ut/Mata in skiva. CLI `ps3 power off|restart`.
  Loggas, `--dry-run`.
- **"På men HEN är av":** svarar konsolen på ping men inte webMAN säger anslutningsskärmen just det
  och visar hur HEN aktiveras (förutsatt att PS3:an svarar på ping, test 7 under Prova).
- **Fjärrkontroll:** `/pad.ps3?<knappar>` på skärmen och med tangentbordet (piltangenter, Retur = ✕,
  Esc = ◯), med XMB:n som bild via `/xmb.ps3$screenshot?show?fast` med några sekunders mellanrum. Räcker för att
  aktivera saker och navigera XMB:n från soffan.
- **Fläkt:** visa webMAN:s läge och måltemperatur. Ändring bara i dynamiskt läge med mål mellan
  60 och 75 °C (`/cpursx.ps3?max=`), aldrig fast låg hastighet. Loggas.
- **Menyraden** (`MenuBarExtra`) och inloggningsobjekt (`SMAppService`): hälsa, temperaturer, vad
  som spelas, kö-förlopp; Skicka fil…, Uppdatera spellistan, Avsluta spel, Stäng av.
- **Notiser:** kön klar eller misslyckad, hög temperatur, nya programuppdateringar.
- **Finder och Genvägar:** "Skicka till PS3" som snabbåtgärd, och App Intents: Skicka till PS3,
  Starta spel, Stäng av PS3, Status.
- **Speltid:** `ConsoleStore` ser redan vilket spel som är monterat var tredje sekund. Sessionerna
  sparas lokalt och ger "Senast spelat" och total speltid på detaljsidan.

### Fas 8 – Säkerhetskopior och underhåll (Underhåll-fliken)

**Läge 24 okt 2026:** byggt: `ps3 saves`/`ps3 backup` och sparfiler varje vecka i appen (med
den förra kopian sparad och det som låg på konsolen sparat före en återställning), systemfiler,
`ps3 maintain` med Städning, `ps3 analyze` med Lagring (via `/stat.ps3`) och `ps3 rip` med Skivan.
Kvar att prova hemma: test 12.

- **Sparfiler:** `ps3 saves list|backup|restore`. Kopierar `/dev_hdd0/home/<användare>/savedata`
  till `~/Library/Application Support/ps3center/Sparfiler/` (eller `_Säkerhetskopior` i
  spegelmappen), bara det som ändrats (storlek + `MDTM`). Återställning bara när inget spel körs,
  med fråga och logg. Automatiskt en gång i veckan när konsolen syns (bara läsning).
- **Systemfiler:** kopia av `/dev_flash2/etc/xRegistry.sys` (systeminställningarna),
  `/dev_hdd0/tmp/wm_config.bin` och `boot_plugins.txt`. Bara läsning.
- **`ps3 maintain`:** kvarglömda `.pkg` i `/dev_hdd0/packages`, `.part` från avbrutna
  överföringar, samma spel både i `PS3ISO` och `GAMES`, stor `wmtmp`, rader i `boot_plugins.txt`
  som pekar på filer som saknas, `hen_updater.off`. Rapport med Klart / Hoppade över och skälet.
- **`ps3 analyze`:** lagringskarta över `/dev_hdd0`.
- **`ps3 rip`:** kopiera skivan i spelaren med `/copy.ps3/dev_bdvd` (redan planerat).

### Fas 9 – Det som aldostools/Resources gav idéer till

**Läge 25 okt 2026:** byggt, oprovat på konsolen: test 14.

- **Ladda om XMB** (`ps3 refresh --xmb`, Fjärrkontroll → Ladda om XMB), och av sig själv efter en
  avinstallation när webMAN kan göra det med Reload XMB.
- **Fler program i Appar:** mohasis File Manager, Yo! Player, Cell Stream, Thermal Bench och
  Ren'Py Player (`mohasi/ps3-dev`), samt Movian, JellyFin, Simple File Manager MOD, TEE Remote
  Play och TEE Vanced (aldostools Addons). Inte Swarm (torrentklient) eller multiMAN (delar mapp
  med webMAN:s omslagspaket).
- **Omslag** för PSP-spel, och aldostools PS1/PS2-omslag när xlenores saknas.
- **Inspelning och bilder:** `ps3 record` och Spela in i Status-fliken; `ps3 media` och Filmer och
  bilder i Underhåll hämtar filmer och skärmbilder till `~/Pictures/PS3 Center`; Skärmbilder i
  spel slår på XMB:ns skärmbilder.
- **PS1 och PS2:** spelsidan och `ps3 games info` säger när en PS2-ISO inte startar på HEN (bara
  PS2 Classics gör det), om PS2 CONFIG har en rättning, och när ett PAL-PS1-spel behöver
  LibCrypt-data (`ps3 games libcrypt`). Granskningsvyn varnar innan en PS2-ISO skickas till HEN.
  `.lsd`/`.sbi` bredvid en PS1-avbild skickas med.
- **Kontroll mot IRD:** `ps3 verify` och Kontrollera mot IRD på spelsidan för en spelmapp i GAMES.
- **Teman:** en `.p3t` som skickas installeras av XMB:n.
- **Småsaker:** `ps3 beep`, `ps3 music on|off`, `ps3 error <kod>` och förklarade felkoder i
  appen, namn ur aldostools titellista när PARAM.SFO saknas, och `ps3 maintain block-updates` med
  Blockera i Städning.
- **Byggdes inte:** att ställa klockan (webMAN skriver den säkra klockan) och säker utmatning av
  USB (webMAN:s är en låtsad händelse).

## Ordning och storlek

| Fas | Storlek | Bygger på | Varför i den ordningen |
|---|---|---|---|
| 1 Spelbiblioteket | L | – | Det du bad om först; allt annat i Spel-fliken bygger på `Game` |
| 2 Omslag | M | 1 | Gör fliken till ett bibliotek |
| 3 Mac-mappar | L | 1 | Det andra du bad om |
| 4 Avbrottssäkert | M | 3 | Behövs innan stora köer körs på natten |
| 5 Snabbare och USB | M | 4 | Mät först, ändra sen |
| 6 ps3netsrv | L | 3 | Löser väntetiden på ett annat sätt |
| 7 Styr konsolen | M | 1 | Små delar som kan tas i valfri ordning |
| 8 Underhåll | M | – | Kan göras när som helst |
| 9 Idéer från aldostools | L | 1–8 | Byggt när resten fungerade |

## Prova på konsolen

Det här går bara att göra hemma, och svaren styr fas 1, 4 och 7. Kör på Macen och klistra in vad
som kommer ut (inget av det innehåller PSID/IDPS). Byt mellanslag i filnamn mot `%20`.

```bash
PS3=10.0.1.35   # din PS3:as adress (ps3 config visar den)

# 1. webMAN:s egen spellista och cache (fas 1)
curl -s "ftp://$PS3/dev_hdd0/xmlhost/game_plugin/mygames.xml" -o mygames.xml && head -c 3000 mygames.xml
curl -s "ftp://$PS3/dev_hdd0/tmp/wmtmp/" | head -40

# 2. Läsa en bit av en ISO på konsolen utan att hämta hela (REST). Väntat: "01 43 44 30 30 31" (CD001)
curl -s -r 32768-32773 "ftp://$PS3/dev_hdd0/PS3ISO/<filnamn>.iso" | xxd

# 3. Starta och avsluta ett spel från Macen
curl "http://$PS3/play.ps3/dev_hdd0/PS3ISO/<filnamn>.iso"
curl "http://$PS3/xmb.ps3\$exit"

# 4. Hastighet, först över Wi-Fi och sedan med kabel; MD5 på konsolen; städa
dd if=/dev/zero bs=1m count=300 2>/dev/null | curl -s -T - "ftp://$PS3/dev_hdd0/tmp/speedtest.bin" -o /dev/null -w '%{speed_upload}\n' | awk '{printf "%.1f MB/s\n", $1/1e6}'
time curl -s "http://$PS3/md5.ps3/dev_hdd0/tmp/speedtest.bin" | grep -io '[0-9a-f]\{32\}'
curl -s "ftp://$PS3/" -Q "DELE /dev_hdd0/tmp/speedtest.bin" -o /dev/null

# 5. Två uppladdningar samtidigt: går det fortare totalt?
for i in 1 2; do (dd if=/dev/zero bs=1m count=150 2>/dev/null | curl -s -T - "ftp://$PS3/dev_hdd0/tmp/speed$i.bin" -o /dev/null -w "$i: %{speed_upload}\n") & done; wait
curl -s "ftp://$PS3/" -Q "DELE /dev_hdd0/tmp/speed1.bin" -Q "DELE /dev_hdd0/tmp/speed2.bin" -o /dev/null

# 6. Vad händer med en halvfärdig fil? Starta test 4 med count=3000, avbryt med ctrl-C och kolla
#    storleken (filen ska finnas kvar). Gör om, men stäng av Macens Wi-Fi i två minuter i stället
#    (enligt källkoden ska filen vara borta).
curl -sI "ftp://$PS3/dev_hdd0/tmp/speedtest.bin"

# 7. Svarar PS3:an på ping när HEN inte är aktiverat? (direkt efter en omstart)
ping -c 3 $PS3

# 8. Virtuell handkontroll (◯ är ofarligt i XMB:n) och skärmbild av XMB:n
curl "http://$PS3/pad.ps3?cancel"
open "http://$PS3/xmb.ps3\$screenshot?show?fast"
```

9. Mät strömmen med en energimätare i uttaget: i XMB:n, under ett spel och under en överföring.
10. Spelservern (fas 6): öppna Spelservern i appen och tryck "Ställ in webMAN åt mig" (eller
    ställ in nätverksserver 1 själv i `http://$PS3/setup.ps3` med Macens adress och port 38008
    och kör `ps3 serve`). Kolla efteråt i webMAN:s inställningar att inget annat ändrats. Syns spelen i Macens PS3ISO-mapp med titel och ikon? Starta ett och spela
    en stund, gärna både över Wi-Fi och med kabel. Säg vad `ps3 serve` skrev och om något hackade.
11. Fas 7 i appen: Fjärrkontroll i Status-fliken (rör sig XMB:n på TV:n när du trycker på
    piltangenterna?), − och + på fläktkortet (bara om webMAN kör dynamiskt läge), menyraden
    med fönstret stängt, "Skicka till PS3" i Finder (högerklick → Snabbåtgärder eller Tjänster;
    kan kräva att appen ligger i Program och har startats en gång) och Genvägar → PS3-status.
    Stäng av HEN genom en omstart och se om appen säger "HEN är inte aktiverat".
12. Fas 8: `ps3 saves` (syns dina sparfiler med namn?), `ps3 backup`, och `ps3 saves restore` på
    en sparfil du har en kopia av på annat håll. `ps3 maintain` och `ps3 analyze` (hur lång tid tog
    det?). Om du har en PS3-skiva: `ps3 rip` och se om mappen i GAMES startar. Kolla också vad
    `curl "http://$PS3/stat.ps3/dev_hdd0/game"` skriver, så att tolkningen stämmer.
13. Det sista: bevaka en mapp i Spelmappar och kopiera in ett spel (kommer det i kön en minut efter
    att kopieringen är klar?), dra ur nätverkskabeln mitt i en överföring och sätt i den igen
    (fortsätter kön själv?), avinstallera ett program du kan installera igen, ta bort en sparfil
    och lägg tillbaka den. Kör hastighetstestet med `"ftpWindow": 1` och sedan `4` i
    config.json och säg vilket som gick fortast.
14. Fas 9:
    - Avinstallera ett program med Reload XMB installerat: försvinner ikonen av sig själv?
    - Spela in en halv minut av ett spel (Spela in i Status-fliken) och hämta filmen under
      Underhåll → Filmer och bilder. Slå på Skärmbilder i spel, ta en bild med PS-knappen →
      Spara skärmbild, och se om den också kommer med. Säg var på PS3:an den hamnade.
    - Öppna ett PS2-spel i Spel-fliken: stämmer varningen om HEN?
    - Har du ett PAL-PS1-spel med LibCrypt (t.ex. Ape Escape): visar spelsidan det?
    - `ps3 verify` på en mapp från `ps3 rip`, och om du har en dekrypterad ISO på Macen.
    - Skicka ett tema (.p3t) och se om XMB:n installerar det.
    - `ps3 beep`, `ps3 music on` under ett spel med musik i XMB:n, och
      `ps3 maintain block-updates` följt av en omstart: säger Inställningar → Systemuppdatering
      att ingen uppdatering finns?

## Beslut (24 okt 2026)

1. **Speluppdateringar (patchar): ja**, så länge inget kan uppdatera konsolen eller leda till
   ban. Patcharna hämtas från Sonys öppna server
   (`a0.ww.np.dl.playstation.net/tpl/np/<ID>/<ID>-ver.xml`), som RPCS3 gör, på Macen och utan
   inloggning. De installeras som vanliga paket i `/dev_hdd0/game/<ID>`, vilket inte rör
   systemprogramvaran. Aldrig firmware (`PS3UPDAT.PUP`), konsolen går aldrig ut på PSN för det, och
   en patch som kräver nyare systemprogramvara än konsolens (`ps3_system_ver` i XML:en) blockeras
   som i säkerhetsspärren. Kommer i fas 2 som "Uppdateringar" i Spel-fliken.
2. **ps3netsrv:** egen implementation i Swift (fas 6): läsning bara, de kopplade mapparna som rot
   och ikoner i farten.
3. **Ordningen** står fast: biblioteket, omslag, Mac-mapparna och sedan överföringarna.
