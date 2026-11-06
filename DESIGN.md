# PS3 Center – design och arkitektur

Förebild: [Mole](https://github.com/tw93/mole). Mole är ett öppet CLI (`mo`) som gör jobbet,
plus en separat Mac-app som visar samma funktioner som flikar. PS3 Center följer samma idé,
men med **en** gemensam motor i stället för två kodbaser.

```
PS3Kit (Swift-bibliotek)   ← all logik: webMAN, FTP, ISO/SFO/PKG, uppdateringar
 ├── ps3   (CLI)           ← `ps3` utan argument är en meny i terminalen
 └── PS3 Center.app        ← SwiftUI, länkar PS3Kit direkt
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
| **Spel** | `ps3 games`, `ps3 send`, `ps3 serve`, `ps3 usb`, `ps3 iso` | Bibliotek Mac ↔ PS3, dra och släpp för att skicka, montera/starta, ta bort |
| **Appar** | `ps3 apps`, `apps available`, `apps info`, `apps update`, `apps install` | Som Moles Apps → Updates: "02.40 → 02.41", Uppdatera / Ignorera / Uppdatera alla. Fliken "Hämta" visar `apps available`, grupperad som System, Program och webMAN-tillägg. "Från Macen" (`apps mac`) visar .pkg-filerna i paketmapparna per mapp, som Macens spel i Spel-fliken; de installeras där de ligger, med samma säkerhetsspärr när title ID:t finns i katalogen. Ett klick på en rad öppnar detaljsidan (`apps info`): version, kompatibilitet med konsolen och README med bilder |
| **Underhåll** | `ps3 saves`, `ps3 backup`, `ps3 maintain`, `ps3 analyze`, `ps3 rip` | Sparfiler och systemfiler till Macen, Städning som Moles Optimize (en rapport med Klart och det som återstår, med skälet), Lagring som Moles Analyze (en stapel över /dev_hdd0) och Skivan |
| **Menyraden** | `ps3 status --watch` | Kompakt status + snabbknappar (Skicka filer, Uppdatera spellistan, Avsluta spelet, Stäng av), Starta vid inloggning |

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
- **Senast tillagt** bygger på datumet i FTP-listningen, som i svaren från konsolen saknar år
  ("Jun 05 18:33"). Det tolkas som det senaste sådana datumet som inte ligger i framtiden, så ett
  spel som är äldre än ett år kan hamna fel. På Macen används Finders "Lades till", eftersom en
  kopierad fil behåller originalets ändringsdatum.
- **Det `send` vet (6 nov):** efter uppladdningen listas målmappen en gång, och titel, title ID och
  version ur avbilden på Macen sparas under samma nyckel (sökväg, storlek och listningens datum)
  som nästa läsning av konsolen använder. ICON0 sparas per sökväg på konsolen och visas tills
  webMAN har gjort sin egen kopia i wmtmp. "Läs om spelen" behåller det för spel utan PARAM.SFO
  på konsolen (PS1, PS2, PSP), eftersom det inte finns något att läsa om där.
- **ps3netsrv** (aldostools/ps3netsrv, `include/netiso.h` och `src/main.cpp`, läst 24 okt 2026):
  kommandon på 16 byte i big-endian från `OPEN_FILE` = 0x1224 till `READ_DIR` = 0x1232, svar med
  fast storlek. `READ_DIR` ger ett antal och sedan poster på 529 byte (storlek, tid, mapp, namn på
  512 byte). `//` i sökvägen betyder att filerna i undermappar ska med, som "mapp/fil". CD-avbilder
  på 2–848 MB får sin sektorstorlek gissad ur var volymbeskrivningen ligger. Bygget READ_ONLY
  stänger anslutningen vid skrivande kommandon, och så gör PS3 Centers `NetServer` också.
  webMAN når servern som `/net0` … `/net4` (nätverksserver 1–5 i `/setup.ps3`).
- **Handkontrollen** (`/pad.ps3?<knapp>`, `include/feat/vpad.h`, läst 24 okt 2026): knapparna
  är up, down, left, right, cross, circle, square, triangle, l1–l3, r1–r3, start, select, psbtn,
  och accept/cancel trycker konsolens egen OK och Tillbaka. `/pad.ps3?off` kopplar bort den
  virtuella handkontrollen. **Ett "=" efter cross eller circle byter konsolens OK-knapp och startar
  om den**, så PS3 Center skickar bara de fasta namnen i `PadButton`, aldrig fri text.
- **Fläkten** (`include/cpursx.h`): `/cpursx.ps3?max=<°C>` flyttar målet i det dynamiska läget
  (webMAN varvar upp fläkten för att hålla konsolen under målet). `?fan=`, `?man` och `?sys` byter
  läge eller sätter fast hastighet; dem använder PS3 Center inte. GETSYSINFO visar `MAX: 68°C` bara
  i dynamiskt läge, och bara då går målet att ändra, inom 60–75 °C.
- **Skivan och skärmen:** `/eject.ps3` och `/insert.ps3` matar ut och in skivan.
  `/xmb.ps3$screenshot?show?fast` visar XMB:n som bild (inte under spel); PS3 Center tar både en
  bild och en sida med `<img>` (test 8 i PLAN.md avgör vilket).
- **HEN av:** webMAN startar först när HEN är aktiverat. Svarar adressen på ping, eller vägrar en
  TCP-anslutning till port 80 (bara en påslagen dator svarar med RST), men webMAN inte, säger appen
  och `ps3 status` att HEN behöver aktiveras.
- **Sparfiler:** en mapp per sparfil i `/dev_hdd0/home/<användare>/savedata/` (användaren är åtta
  siffror, 00000001). PARAM.SFO i den har TITLE och SUB_TITLE, men också kontouppgifter
  (ACCOUNT_ID, PARAMS); PS3 Center läser bara de två första. En sparfil läggs bara tillbaka hos
  samma användare.
- **`/stat.ps3<sökväg>`** (`include/cmd/stat_chmod.h`) räknar en mapps storlek på konsolen och
  svarar `Size: 12.3 GB (13,207,024,640 bytes)<br>Dir(s): …<br>File(s): …`. Med `&id=` länkar den
  filer i stället, så det används aldrig.
- **`/copy.ps3/<sökväg>&to=<mål>`** kopierar på konsolen, `/copy.ps3$abort` stoppar. Om svaret
  kommer först när kopian är klar är inte känt, så PS3 Center skickar det i en egen anslutning
  och följer målmappen över FTP (test 12 i PLAN.md).
- **HEN:s inställningar** är tomma filer i `/dev_hdd0/hen/toggles/` (`hotkey_polling.off`,
  `remap_files.off` i `payload/main.c`). `ps3 maintain` visar dem bara.
- **webMAN:s inställningar** (`/setup.ps3`, `include/setup.h`): när formuläret skickas nollställs
  *alla* inställningar och läses sedan in ur anropet, så ett fält som saknas stängs av. Några fält
  (ikontyp, informationstaggar, väntetider för USB) får dessutom sitt värde av JavaScript i
  sidan (`wm_res/setup/setup*.dat`). PS3 Center laddar därför sidan i en dold `WKWebView`, ändrar
  bara nätverksservern och skickar `new URLSearchParams(new FormData(form))`, alltså exakt det
  Safari skulle skicka. Först sparas en kopia av inställningarna (Systemfiler), och efteråt läses
  sidan igen och jämförs fält för fält. Nätverksservrarna heter `nd<n>`, `neth<n>` och `netp<n>`
  (n = 0–4, `/net0`–`/net4`).
- **Uppladdningar (25 okt):** filen skickas i bitar om 1 MB, och nästa bit lämnas till
  nätverket innan den förra är skickad (två i luften), i samma ordning. Bryts anslutningen
  försöker kön igen med paus emellan och fortsätter från `.part`-filens storlek. Har webMAN tagit
  bort filen (anslutningen bröts med ett fel) börjar den om och säger det.
- **Avinstallera:** ett installerat spel eller program är en mapp i `/dev_hdd0/game/<title ID>`
  som tas bort med FTP (RMD är rekursiv i webMAN). Sparfiler och troféer rörs inte. XMB:n visar
  ikonen tills den laddas om (se Ladda om XMB nedan).
- **`/cpursx.ps3` visar PSID/IDPS.** De sparas och visas aldrig.
- **Paketinstallation:** `/install.ps3/<sökväg>` installerar, men tar *inte* bort .pkg-filen
  som wikin påstår (provat 24 okt 2026). Verktyget vet att installationen är klar när
  `PARAM.SFO` i `/dev_hdd0/game/<title ID>/` fått en ny `MDTM`-tidsstämpel och mappen sedan
  inte ändrats på två kontroller i rad. Därefter tar verktyget bort sin kopia av paketet.
  Ominstallation av Apollo tog 11 sekunder. Svaret på `/install.ps3` kan dröja tills XMB:n är
  klar, så det skickas på en egen anslutning och statusen fortsätter under tiden. Varje kontroll
  öppnar en egen FTP-session (webMAN släpper en som är tyst i en minut). Ändras ingenting i
  mappen på 75 sekunder skickas `/install.ps3` en gång till, och sedan ger verktyget upp med råd
  om att installera från XMB:n (ett avbrott fick appen att vänta på en installation som aldrig
  startade, 25 okt 2026).
- **Appen tål några missade statusanrop:** webMAN är långsam ibland, så konsolen räknas som borta
  först efter tre anrop i rad utan svar. Under tiden är pricken vid PS-loggan gul. Medan ett långt
  kommando går (en installation, `/stat.ps3` som räknar en stor mapp, kopiering av skivan) räknas
  den inte som borta alls; det kommandots egen tidsgräns avgör (att räkna lagring tappade
  kontakten, 25 okt 2026).
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

### Fas 9: ur webMAN:s, PS3HEN:s och aldostools källor (25 okt 2026)

- **PS2 på HEN:** webMAN monterar inte vanliga PS2-ISO:er på HEN ("HEN does not support PS2 ISO",
  `include/mount/mount_cobra.h`). Bara PS2 Classics (krypterade `.BIN.ENC`) startar, genom PS2
  Classics Launcher. Rättningar läses ur `/dev_hdd0/game/PS2CONFIG/USRDIR`: för en PS2 Classic
  `CONFIG/ENC/<SLES_123.45>.ENC`, för en ISO på CFW `<ID>.CONFIG` i `CUSTOM`, `NET`, `GX` eller
  `SOFT` (`include/mount/ps2_classic.h`).
- **LibCrypt (PAL-PS1):** PS3HEN läser skyddsdatan i `payload/storage_ext.c`: först
  `<spårets namn>.lsd`/`.sbi` bredvid datafilen (`.bin` byts mot `.lsd`), sedan
  `/dev_hdd0/tmp/lsd/<EXE>.lsd` och `/dev_hdd0/tmp/sbi/<EXE>.sbi`, där EXE är startfilen i
  SYSTEM.CNF (`SCES_014.31`). webMAN MOD:s installerare lägger 225 LSD-filer i `/dev_hdd0/tmp/lsd`
  (`_Projects_/updater/pkgfiles/USRDIR/lsd`); en post är 15 byte.
- **Ladda om XMB:** `/refresh.ps3?xmb` läser om spellistan och laddar om XMB:n, bara när XMB:n
  visas. Med en användare och Reload XMB (`/dev_hdd0/game/RELOADXMB`, som webMAN:s installerare
  också lägger dit) startar webMAN den appen, annars loggar den ut och in med virtuella
  knapptryck (`reload_xmb`, `include/init/vsh.h`). PS3 Center laddar bara om av sig själv efter en
  avinstallation när det första gäller.
- **Inspelning:** `/videorec.ps3` startar eller stoppar inspelning, bara under ett spel, som 720p
  MP4 i `/dev_hdd0/VIDEO/<title ID>_<datum>.mp4`. Svaret säger `Video recording: Enabled` eller
  `Disabled` (`include/feat/video_rec.h`).
- **Skärmbilder i spel:** `/xmb.ps3$ingame_screenshot` slår på XMB:ns Spara skärmbild i alla spel,
  till nästa omstart. Foton ligger under `/dev_hdd0/photo`.
- **Musik i spel:** `/sysbgm.ps3?1` och `?0` sätter bakgrundsmusiken. webMAN kan inte läsa av
  läget: `?` och `?status` ändrar det (`include/cmd/sysbgm.h`), så de används inte.
- **Pip:** `/beep.ps3?1`–`3` är summerns pip (`play_sound_id`, `include/notify/vsh_notify.h`).
- **Teman:** `/install.ps3/<sökväg>.p3t` anropar XMB:ns temainstallerare
  (`include/feat/pkg_handler.h`). PS3 Center laddar upp temat till `/dev_hdd0/packages`.
- **Systemuppdateringar:** finns `/dev_hdd0/ps3-updatelist.txt` pekar webMAN XMB:ns
  uppdateringskoll på den vid varje start (`include/www/www_start.h`). webMAN MOD:s egen fil
  skickar alla regioners uppdatering till 127.0.0.1. Inget i dev_flash ändras.
- **Används inte:** `/fixclock.ps3` skriver konsolens säkra klocka (`sys_ss_secure_rtc`,
  `include/feat/clock.h`), och XMB:n ställer klockan via Internet själv. USB-"utmatningen"
  (`/xmb.ps3$eject/dev_usb000`) är en låtsad händelse till XMB:n, ingen säker avmontering.
  Överklockning, LV1/LV2-minne, IDPS/PSID-dumpar och nätverksinställningar används aldrig.
- **IRD:** formatet följer 13xforever:s ps3-disc-dumper (`IrdLibraryClient/IrdFormat`):
  little-endian, hela filen ofta gzip, `header` är skivans första block (gzip) med filsystemet,
  och filernas MD5 (på dekrypterad data) är nycklade på blocket filen börjar i. Namnen läses ur
  Joliet-trädet. IRD-filerna hämtas från FlexBy420:s databas på GitHub
  (`flexby420.github.io/playstation_3_ird_database/all.json`).
- **ps3.aldostools.org** har ett självsignerat HTTPS-certifikat och fungerar bara över HTTP, så
  PS3 Center hämtar inget därifrån. Samma data finns på GitHub (titleid.txt, omslag, LSD-filer).
  psdevwiki ligger bakom ett Cloudflare-skydd; felkoderna (0x8001xxxx) kommer i stället från
  RPCS3:s `rpcs3/Emu/Cell/ErrorCodes.h`.
- **Omslag:** PSP från `aldostools/Resources/PSP/<UCES00995>.PNG`, och PS1/PS2 därifrån som
  reserv (`PSX/<SCES_014.38>_COV.JPG`).

### Fas 10: ISO-verktygen från PC:n (7 nov 2026)

- **Delade filer på USB** (webMAN MOD `include/file/file_copy.h`): när webMAN kopierar en fil över
  0xFFFFFFFF byte till `/dev_usb` blir en `.iso` `.iso.0`, `.iso.1` … och andra filer `.66600`,
  `.66601` …, i delar om 0xFFFF0000 byte (4 GB − 64 KB). Kopieras en `.66600` från USB till hdd0
  slår webMAN ihop delarna igen. Bara ISO:er startas i delar: `.iso.0` monteras med de delar som
  följer för PS3-spel, PS2 (CFW), Blu-ray och DVD (`include/mount/mount_cobra.h`). En spelmapp med
  `.666`-delar startar inte från USB, så PS3 Center gör den till en ISO i stället.
- **PS3-ISO:n** (Estwalds makeps3iso, bucanero/ps3iso-utils): sektor 0 har antalet okrypterade
  regioner och deras första och sista sektor (en region, hela avbilden, när den är dekrypterad),
  sektor 1 "PlayStation3" och title ID som `BLES-00932`. Primär volymbeskrivning i 16, Joliet
  (UCS-2, `%/@`) i 17, slut i 18, vägtabeller från 20, kataloger från 32, sedan filerna: en mapps
  egna filer före undermapparnas. En fil över 4 GB får en post per bit om 0xFFFFF800 byte, med
  flaggan 0x80 på alla utom den sista (flera extents). Namnen i det primära trädet är versaler.
  makeps3iso lämnar filerna i `PS3_UPDATE` utanför, och det gör PS3 Center också: ingen firmware
  följer med.
- **Krypterade avbilder:** Redump-avbilder har flera regioner i sektor 0, och de krypterade är
  luckorna mellan dem. Även dekrypterade (ps3dec) behåller tabellen; att `EBOOT.BIN` börjar med
  `SCE` i en lucka visar att avbilden är dekrypterad. webMAN MOD:s källkod har inget stöd för
  disknycklar (`.dkey`), så en krypterad avbild måste dekrypteras innan den kan startas på HEN.
- **Provat på Macen (7 nov):** en ISO från en testmapp monteras av macOS (`hdiutil`) med både
  Joliet och det primära trädet, och innehållet är identiskt med mappen. En fil på 4 GB + 4 KB
  fick två poster med rätt start och samma MD5 som källan (kontrollerat med en egen parser,
  eftersom macOS `cd9660` bara läser den sista biten av en sådan fil). Dela, foga ihop och packa
  upp gav samma filer. `bsdtar` tar regionstabellen i sektor 0 för LZMA och kan inte läsa ISO:n.
  Inte provat på konsolen (test 15 i PLAN.md).
- **PS2 Classics på HEN** (byggt 7 nov, `PS2Classics.swift`; källorna nedan):
  - webMAN (`include/mount/mount_misc.h`, `ps2_classic.h`) startar `<namn>.BIN.ENC` i PS2ISO genom
    att länka den som `/dev_hdd0/game/PS2U10000/USRDIR/ISO.BIN.ENC` i PS2 Classics Launcher (som
    måste vara installerad) och kopiera dit CONFIG och minneskort. CONFIG letas upp av sig själv i
    PS2CONFIG (`CONFIG/ENC/<SLES_123.45>.ENC`, redan krypterade), så de behöver inte göras här.
  - PS3HEN (`payload/make_rif.c`) gör licensen för just `2P0001-PS2U10000_00-0000111122223333`
    av sig själv, med en inbyggd RAP, och skapar `act.dat` om den saknas. Ingen licens behövs från
    användaren.
  - Krypteringen (`ps2classic.c`, GPLv3, i webMAN MOD:s `_Projects_/tools/ps2classic_*.7z`):
    avbilden fylls ut till 16 KB och får ett LIMG-block (`"LIMG"`, 1, sektorer, 0x800). Data- och
    metanyckeln är `klicensee` krypterad med två fasta CEX-nycklar och en fast IV. Data krypteras
    med AES-128-CBC i segment om 0x4000, 0x200 segment per block, och före varje block kommer en
    tabell med SHA-1 och segmentnummer, krypterad med metanyckeln. Huvudet (`PS2\0`, NPD-typ 2,
    content ID, namnet `ISO.BIN.ENC`) signeras med AES-CMAC och tre NPD-nycklar.
  - Det som behövs utöver koden är sju värden på 16 byte: två CEX-nycklar, IV:n, tre NPD-nycklar
    och platshållarens `klicensee` (`…3333.rifkey`, framtagen ur samma RAP som PS3HEN har inbyggd;
    kontrollerat med SHA-256). IV:n är sexton nollor. `aes128cbc_enc` i ps2classic kopierar IV:n,
    så varje segment börjar om med den; nyckelhärledningen är därför AES(nyckel, klicensee).
  - Nycklarna finns i webMAN MOD:s publika repo men inte i PS3 Center (beslut 7 nov): Hämta laddar
    ner de två arkiven, packar ut `src/ps2classic.c` och `.rifkey` med macOS `bsdtar` till minnet,
    jämför med SHA-256 i koden och sparar i `~/.config/ps3center/ps2classic-keys.json` (0600).
  - Provat på Macen 7 nov: CMAC mot RFC 4493, kryptering och dekryptering med påhittade nycklar
    (huvud, LIMG, tabeller över blockgränsen, råa CD-sektorer), och Hämta plus en PS2 Classic av en
    egen test-ISO med de riktiga nycklarna. Om spelet startar visar test 16.

## Färdplan

Planen fas för fas, med vad som är byggt, vad som återstår och vad som ska provas på konsolen,
finns i [PLAN.md](PLAN.md). Några beslut som gäller framåt:

- **Katalogen:** nya program granskas mot hur väletablerade de är; repon som är några veckor
  gamla med 1–2 stjärnor tas inte med automatiskt.
- **Spel:** bara egna filer via `send`, `ps3 rip` och bevakade mappar. Ingen inbyggd nedladdning
  från ROM- eller ISO-arkiv.
- **Plugins:** PS3 Center ändrar aldrig `boot_plugins.txt`, så det blir inget `plugin add/remove`.
  Saknade plugins rapporteras av `ps3 maintain`.
- **Skärmbilder utan PS3:** `PS3CENTER_FIXTURES=1` ger appen data från PS3Kit:s `Fixtures`; CI
  renderar varje skärm och laddar upp PNG:erna som artefakten `screenshots`, och
  `make snapshot-fixtures` gör samma sak på Macen.
