# PS3 Center (`ps3`)

Styr PS3:an (PS3HEN + webMAN MOD) från Macen: ladda upp spel, installera och uppdatera
homebrew och se status, utan menyer på konsolen och utan USB-sticka.
Arkitektur och planerna för Mac-appen finns i [DESIGN.md](DESIGN.md).

## Installera

```bash
make install    # bygger och länkar ~/.local/bin/ps3
```

Kräver Xcode (Swift 6). `make build` uppdaterar en redan installerad version.
`make test` kör testerna.

## Mac-appen

```bash
brew install xcodegen   # en gång
make install-app        # bygger en Release-version och lägger den i /Program
```

Sedan öppnas PS3 Center som vilken app som helst: från Launchpad, Spotlight eller Dock. Kör
`make install-app` igen för att uppdatera (en öppen app avslutas först). `make run-app` bygger en
Debug-version och öppnar den direkt från `.build`, utan att installera.

Appen har fyra flikar i Mole-stil:
- **Status:** hälsa, CPU, RSX, fläkt, ledigt utrymme, nätverk, vad som spelas och versioner, med
  löpande kurvor och historiken från `ps3 history`. Under korten: Fjärrkontroll (styrkors och
  knappar, piltangenter och Retur/Esc; titta på TV:n; där finns också Ladda om XMB, Pip,
  Skärmbilder i spel och Musik i spel), Avsluta spelet och Spela in medan ett spel körs, Mata ut
  skivan, Starta om och Stäng av. I dynamiskt fläktläge flyttar − och + webMAN:s måltemperatur
  (60–75 °C).
- **Spel:** spelen på PS3:an som rutnät med fodral eller XMB-ikoner, filter per plattform, sök och
  sortering på namn, storlek eller senast tillagt.
  Klicka på ett spel för title ID, region, storlek och version, och för att starta, montera, ta bort,
  avinstallera (installerade spel; sparfilerna ligger kvar) eller uppdatera det. "Sök uppdateringar" frågar Sony efter nya patchar. Dra en bild till spelets
  banderoll för att byta omslag. PS1- och PS2-spel säger om något hindrar dem: en PS2-ISO startar
  inte på HEN (bara PS2 Classics gör det), och ett PAL-PS1-spel med LibCrypt får sin data på en
  knapptryckning. En spelmapp i GAMES kan kontrolleras mot originalskivans IRD. Under **Macen** visas spelen i dina kopplade spelmappar, med vad
  som redan finns på PS3:an; markera spel och tryck Skicka. Filer som dras till fönstret går samma väg.
  **Spelservern** (under Macen) låter PS3:an spela ISO:erna direkt från Macen utan att kopiera dem.
  "Ställ in webMAN åt mig" fyller i en ledig nätverksserver i webMAN och lämnar resten av
  inställningarna som de var (en kopia av dem sparas först).
- **Överföringar** (pilarna uppe till höger): kön med förlopp, Starta/Pausa, "När kön är klar"
  (popup eller stäng av PS3:an), MD5-kontroll och hastighetsmätning. Macen hålls vaken medan kön går,
  och kön pausas rent när Macen somnar och fortsätter när den vaknar. Bryts anslutningen försöker
  kön igen (efter 15 s, 30 s, 1, 2 och 4 minuter) och fortsätter där filen slutade. I Spelmappar
  kan en mapp **bevakas**: nya spel i den läggs i kön och skickas när de har kopierats klart.
  Är PS3:an på Wi-Fi visar granskningen hur lång tid det skulle ta med kabel, och går Macen på
  batteri sägs det att kön stannar om locket stängs. Spel som skickas från Macen behåller sin
  titel, sitt title ID och sin ikon på PS3:an direkt, innan webMAN har läst dem.
- **Appar:** uppdateringar ("02.40 → 02.41", Uppdatera / Uppdatera alla) och en Hämta-lista.
  Ett installerat program kan avinstalleras från sin sida. Under Från Macen visas .pkg-filerna i
  dina paketmappar (knappen Paketmappar), med om de redan är installerade; de installeras med ett
  klick och ligger kvar på Macen.
  Ikonerna är programmens egna XMB-ikoner från konsolen. Klicka på ett program för en
  detaljsida med version, om det fungerar på din PS3 och README med bilder från GitHub.
- **Underhåll:** sparfilerna kopieras till Macen (själv en gång i veckan, eller med Kopiera nu) och
  kan läggas tillbaka, och en sparfil kan tas bort från PS3:an (en kopia sparas först); systemfilerna kopieras på begäran; Städning hittar kvarglömda paket,
  avbrutna överföringar, dubbletter, en stor cache och saknade plugins och tar bort det som går;
  Lagring visar vad som tar plats; Skivan kopierar PS3-skivan i spelaren till hårddisken; Filmer
  och bilder hämtar inspelningar och skärmbilder till `~/Pictures/PS3 Center`. Städning säger
  också om systemuppdateringar blockeras, med en knapp som blockerar dem.

**Menyraden** visar temperaturer, vad som spelas, kön och spelservern, med Skicka filer…,
Uppdatera spellistan, Avsluta spelet och Stäng av; appen fortsätter där när fönstret är stängt
(Starta vid inloggning finns i samma meny). I Finder finns **Skicka till PS3** under Tjänster och
Snabbåtgärder, och i Genvägar finns PS3-status, Starta spel på PS3:an, Stäng av PS3:an och Skicka
till PS3. Är PS3:an på men HEN inte aktiverat säger anslutningsskärmen det. Spelsidan visar hur
länge du har spelat ett spel och när du spelade senast. Notiser kommer när kön är klar, när
konsolen blir varm och när ett program har en ny version.

Utseendet följer PlayStation-appen: blå startskärm, mörk bas med färg per flik, vita knappar och
spelens egna bilder. Kugghjulet uppe till höger öppnar Utseende med PS-appens teman.

`make snapshot DIR=/tmp/shots` renderar flikarna till PNG utan att något fönster öppnas, och
`make snapshot-fixtures DIR=/tmp/shots` gör samma sak utan PS3.

## Kommandon

| Kommando | Gör |
|---|---|
| `ps3` | En meny med de vanligaste kommandona när det körs i en terminal; skriv en siffra eller ett kommando. I ett skript visas hjälpen |
| `ps3 status` | Hälsa, temperaturer, fläkt, ledigt utrymme och vad som körs. `--watch` uppdaterar löpande, `--json` ger JSON |
| `ps3 games` | Spelen på PS3:an per plattform: title ID, region, storlek, version och installerade uppdateringar (`--platform ps2`, `--sort storlek\|tillagt`, `--json`) |
| `ps3 games info <namn>` | Allt om ett spel. Namnet kan vara en del av titeln, ett title ID eller sökvägen |
| `ps3 games play <namn>` | Startar spelet. Körs ett annat spel frågar den först om det ska avslutas (`-y`, `--dry-run`) |
| `ps3 games mount\|unmount\|exit` | Monterar ett spel som skiva, avmonterar det eller avslutar spelet som körs |
| `ps3 games delete <namn>` | Tar bort spelets filer från PS3:an efter en fråga, eller avinstallerar ett installerat spel (`--dry-run`, `-y`) |
| `ps3 games covers` | Hämtar omslag till Macen; `--to-ps3` lägger PS3-omslagen där webMAN letar |
| `ps3 games updates` | Officiella uppdateringar (patchar) från Sony för spelen |
| `ps3 games update <namn>` | Hämtar, kontrollerar och installerar ett spels patchar (`--all`, `--dry-run`, `-y`). Aldrig systemprogramvara |
| `ps3 games mac` | Spelen i Macens spelmappar och om de redan finns på PS3:an (`--missing`) |
| `ps3 games libcrypt <namn>` | Lägger LibCrypt-datan som ett PAL-PS1-spel behöver i `/dev_hdd0/tmp/lsd` (från webMAN MOD, `--dry-run`) |
| `ps3 config folder add PS3ISO ~/Spel/PS3` | Kopplar en spelmapp på Macen per typ (PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO, DVDISO) |
| `ps3 config folder add PKG ~/Paket` | Kopplar en paketmapp med .pkg-filer (se `ps3 apps mac`) |
| `ps3 config folder watch ~/Spel/PS3` | Bevakar en kopplad mapp; `ps3 watch` (eller appen) lägger nya spel i kön (`--send` skickar direkt) |
| `ps3 queue add <filer eller spel>` | Lägger spel i kön som appen också använder; `ps3 queue start` skickar ett i taget (`--when-done shutdown`, `--verify`) |
| `ps3 serve` | Spelservern: PS3:an spelar ISO:er direkt från Macens spelmappar via webMAN:s `/net0` (port 38008, bara läsning, bara PS3:an släpps in) |
| `ps3 speedtest` | Mäter hur fort det går till och från PS3:an; ger tidsberäkningar i kön |
| `ps3 usb prepare /Volumes/X <spel>` | Kopierar spel till en FAT32-disk i webMAN:s mappar. ISO:er över 4 GB delas, och en spelmapp med en fil över 4 GB blir en ISO |
| `ps3 iso make <mapp> [mål]` | Gör en PS3-ISO av en spelmapp, som PS3 ISO Tools och makeps3iso (delad på en FAT32-disk) |
| `ps3 iso split\|join\|extract <fil>` | Delar en ISO för FAT32, fogar ihop `.iso.0` …, packar upp en ISO till en spelmapp |
| `ps3 ps2 keys --fetch` | Hämtar nycklarna för PS2 Classics ur webMAN MOD:s repo till Macen (`--import` tar egna filer) |
| `ps3 ps2 classic <iso, cue>` | Gör ett PS2-spel till en PS2 Classic (`.BIN.ENC`), det enda sätt PS2-spel startar på HEN |
| `ps3 power off\|restart` | Stänger av eller startar om PS3:an (på HEN måste HEN aktiveras igen efter omstart) |
| `ps3 disc eject\|insert` | Matar ut eller in skivan |
| `ps3 fan [70]` | Fläktens hastighet och läge; med ett tal flyttas målet i webMAN:s dynamiska läge (60–75 °C) |
| `ps3 pad down down ok` | Trycker på knappar med webMAN:s virtuella handkontroll (`ps3 pad off` kopplar bort den) |
| `ps3 screenshot [fil]` | Sparar en bild av XMB:n på Macen |
| `ps3 record` | Startar eller stoppar inspelning av spelet som körs (720p MP4 i `/dev_hdd0/VIDEO`) |
| `ps3 media [pull\|screenshots]` | Nya filmer och skärmbilder på PS3:an; `pull` kopierar dem till `~/Pictures/PS3 Center`, `screenshots` tillåter skärmbilder i alla spel |
| `ps3 beep [1–3]` | PS3:an piper, så att du hittar den |
| `ps3 music on\|off` | Låter musik från XMB:n spela under spel, eller inte (till nästa omstart, `--dry-run`) |
| `ps3 send <filer/mappar>` | Laddar upp till rätt mapp via `.part`-filer, fortsätter avbrutna uppladdningar, hoppar över spel som redan finns, uppdaterar spellistan och visar en popup. Håller Macen vaken; `--verify` jämför MD5, `--shutdown-when-done` stänger av PS3:an efteråt |
| `ps3 saves [backup\|local\|restore <namn>]` | Sparfilerna på PS3:an, kopiera dem till Macen, lägg tillbaka en (inte under spel; det som låg där sparas först) |
| `ps3 saves delete <namn>` | Tar bort en sparfil från PS3:an efter att den kopierats till Macen (`--dry-run`, `-y`) |
| `ps3 backup` | Sparfiler och systemfiler (xRegistry.sys, webMAN:s inställningar, boot_plugins) till Macen; läser bara konsolen |
| `ps3 maintain [--fix]` | Kvarglömda paket, avbrutna överföringar, dubbletter, cache, saknade plugins och om systemuppdateringar blockeras; `--fix` tar bort paket och `.part`-filer |
| `ps3 maintain block-updates` | Lägger webMAN MOD:s `ps3-updatelist.txt` på PS3:an, så att ingen systemuppdatering hämtas av misstag (`--off`, `--dry-run`) |
| `ps3 verify <iso, mapp eller spel>` | Kontrollerar en skivkopia fil för fil mot originalets IRD (från FlexBy420:s databas, eller `--ird fil`) |
| `ps3 analyze` | Vad som tar plats på `/dev_hdd0`, räknat på konsolen |
| `ps3 rip` | Kopierar PS3-skivan i spelaren till `/dev_hdd0/GAMES` (`--abort` stoppar) |
| `ps3 apps` | Installerade program jämförda med senaste versionen på GitHub |
| `ps3 apps available` | Hela katalogen: vad du har (✓), vad som har uppdateringar (↑), vad som kan installeras (↓) och vad som inte fungerar på din PS3 (⊘) |
| `ps3 apps info <namn>` | Version, om programmet fungerar på din PS3 och README från GitHub (`--no-readme`, `--json`) |
| `ps3 apps install <namn…>` | Hämtar senaste versionen från GitHub och installerar, t.ex. `ps3 apps install ezremote` (`--reinstall`, `--dry-run`) |
| `ps3 apps install <pkg…>` | Installerar en egen .pkg-fil direkt och arkiverar den i `_Installerat/Paket`; ett paket i paketmapparna (filnamn eller title ID räcker) ligger kvar |
| `ps3 apps mac` | Paketen i Macens paketmappar och om de är installerade (`--missing`, `--offline`, `--json`) |
| `ps3 apps uninstall <namn>` | Avinstallerar ett program (mappen i /dev_hdd0/game); inte HEN, webMAN eller plugins (`--dry-run`, `-y`) |
| `ps3 apps update [namn…]` | Granska och installera uppdateringar (`--dry-run`, `-y`) |
| `ps3 popup <text>` | Visar ett meddelande på TV:n |
| `ps3 refresh [--xmb]` | Uppdaterar spellistan (som SELECT + L3); `--xmb` laddar om XMB:n också |
| `ps3 error <kod>` | Förklarar en felkod som 80010006 |
| `ps3 history` | Vad verktyget har ändrat (`~/Library/Logs/ps3center/operations.log`) |
| `ps3 discover` | Letar upp PS3:an på nätverket och sparar adressen |
| `ps3 config [set host/root …]` | Inställningar i `~/.config/ps3center/config.json` |

- **HEN måste vara aktiverat,** annars svarar inte webMAN.
- **Om PS3:ans IP-adress ändras** hittar verktyget den automatiskt och sparar den nya.
- **Medan ett spel körs** börjar uppladdningar direkt, men installation och uppdatering av
  spellistan väntar tills du har avslutat spelet (`--force` kör ändå).
- **HEN och ds45pad uppdateras aldrig automatiskt.** De visas bara med råd.
- **Säkerhetsspärr:** innan något installeras läser verktyget konsolens firmware (HEN eller CFW,
  CEX eller DEX, version). Program som inte fungerar på den blockeras, både via namn och som egen
  .pkg-fil med ett känt title ID. Går firmwaren inte att läsa blockeras program som har krav.

## Felsökning

`PS3_DEBUG=1 ps3 …` skriver ut FTP-trafiken. `PS3_HOST=<ip>` tvingar fram en viss adress.
`GITHUB_TOKEN` höjer GitHubs gräns för antal anrop.

## Lägga till ett program i katalogen

Lägg till en `CatalogEntry` i `Sources/PS3Kit/Catalog.swift` med:
- programmets title ID: tecken 8–16 i paketets content ID vid offset 0x30, samma som mappnamnet
  under `/dev_hdd0/game/`
- GitHub-repot
- ett reguljärt uttryck för release-filen
- hur taggarna skrivs (`VersionStyle`)

Paket som följer med någon annans release får `tracksUpdates: false`.

Om programmet bara fungerar på vissa konsoler får det `requirements`, t.ex. `.cfwOnly`,
`.dexOnly`, `Requirements(minFirmware: "4.80")` eller `Requirements(untestedOn: [.cfw])` (varnar
men blockerar inte). Skriv in vad README:n eller releaseanteckningarna säger, inte gissningar.

När PS3 Center installerar ett program sparas kopplingen mellan tagg och `APP_VER` i
`~/.config/ps3center/installed.json`. Därefter jämförs taggarna direkt, så `VersionStyle`
behövs bara för program som installerats på annat sätt.
