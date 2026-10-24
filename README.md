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
make run-app            # genererar App/PS3Center.xcodeproj, bygger och öppnar appen
```

Appen har fyra flikar i Mole-stil:
- **Status:** hälsa, CPU, RSX, fläkt, ledigt utrymme, nätverk, vad som spelas och versioner, med
  löpande kurvor och historiken från `ps3 history`. Under korten: Fjärrkontroll (XMB:n som bild,
  styrkors och knappar, piltangenter och Retur/Esc), Avsluta spelet, Mata ut skivan, Starta om och
  Stäng av. I dynamiskt fläktläge flyttar − och + webMAN:s måltemperatur (60–75 °C).
- **Spel:** spelen på PS3:an som rutnät med fodral eller XMB-ikoner, filter per plattform och sök.
  Klicka på ett spel för title ID, region, storlek och version, och för att starta, montera, ta bort
  eller uppdatera det. "Sök uppdateringar" frågar Sony efter nya patchar. Dra en bild till spelets
  banderoll för att byta omslag. Under **Macen** visas spelen i dina kopplade spelmappar, med vad
  som redan finns på PS3:an; markera spel och tryck Skicka. Filer som dras till fönstret går samma väg.
  **Spelservern** (under Macen) låter PS3:an spela ISO:erna direkt från Macen utan att kopiera dem.
  "Ställ in webMAN åt mig" fyller i en ledig nätverksserver i webMAN och lämnar resten av
  inställningarna som de var (en kopia av dem sparas först).
- **Överföringar** (pilarna uppe till höger): kön med förlopp, Starta/Pausa, "När kön är klar"
  (popup eller stäng av PS3:an), MD5-kontroll och hastighetsmätning. Macen hålls vaken medan kön går,
  och kön pausas rent när Macen somnar och fortsätter när den vaknar.
- **Appar:** uppdateringar ("02.40 → 02.41", Uppdatera / Uppdatera alla) och en Hämta-lista.
  Ikonerna är programmens egna XMB-ikoner från konsolen. Klicka på ett program för en
  detaljsida med version, om det fungerar på din PS3 och README med bilder från GitHub.
- **Underhåll:** sparfilerna kopieras till Macen (själv en gång i veckan, eller med Kopiera nu) och
  kan läggas tillbaka; systemfilerna kopieras på begäran; Städning hittar kvarglömda paket,
  avbrutna överföringar, dubbletter, en stor cache och saknade plugins och tar bort det som går;
  Lagring visar vad som tar plats; Skivan kopierar PS3-skivan i spelaren till hårddisken.

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
| `ps3 status` | Hälsa, temperaturer, fläkt, ledigt utrymme och vad som körs. `--watch` uppdaterar löpande, `--json` ger JSON |
| `ps3 games` | Spelen på PS3:an per plattform: title ID, region, storlek, version och installerade uppdateringar (`--platform ps2`, `--json`) |
| `ps3 games info <namn>` | Allt om ett spel. Namnet kan vara en del av titeln, ett title ID eller sökvägen |
| `ps3 games play <namn>` | Startar spelet. Körs ett annat spel frågar den först om det ska avslutas (`-y`, `--dry-run`) |
| `ps3 games mount\|unmount\|exit` | Monterar ett spel som skiva, avmonterar det eller avslutar spelet som körs |
| `ps3 games delete <namn>` | Tar bort spelets filer från PS3:an efter en fråga (`--dry-run`, `-y`) |
| `ps3 games covers` | Hämtar omslag till Macen; `--to-ps3` lägger PS3-omslagen där webMAN letar |
| `ps3 games updates` | Officiella uppdateringar (patchar) från Sony för spelen |
| `ps3 games update <namn>` | Hämtar, kontrollerar och installerar ett spels patchar (`--all`, `--dry-run`, `-y`). Aldrig systemprogramvara |
| `ps3 games mac` | Spelen i Macens spelmappar och om de redan finns på PS3:an (`--missing`) |
| `ps3 config folder add PS3ISO ~/Spel/PS3` | Kopplar en spelmapp på Macen per typ (PS3ISO, GAMES, PS2ISO, PSXISO, PSPISO, BDISO, DVDISO) |
| `ps3 queue add <filer eller spel>` | Lägger spel i kön som appen också använder; `ps3 queue start` skickar ett i taget (`--when-done shutdown`, `--verify`) |
| `ps3 serve` | Spelservern: PS3:an spelar ISO:er direkt från Macens spelmappar via webMAN:s `/net0` (port 38008, bara läsning, bara PS3:an släpps in) |
| `ps3 speedtest` | Mäter hur fort det går till och från PS3:an; ger tidsberäkningar i kön |
| `ps3 usb prepare /Volumes/X <spel>` | Kopierar spel till en FAT32-disk i webMAN:s mappar, PS3-ISO:er över 4 GB delade |
| `ps3 power off\|restart` | Stänger av eller startar om PS3:an (på HEN måste HEN aktiveras igen efter omstart) |
| `ps3 disc eject\|insert` | Matar ut eller in skivan |
| `ps3 fan [70]` | Fläktens hastighet och läge; med ett tal flyttas målet i webMAN:s dynamiska läge (60–75 °C) |
| `ps3 pad down down ok` | Trycker på knappar med webMAN:s virtuella handkontroll (`ps3 pad off` kopplar bort den) |
| `ps3 screenshot [fil]` | Sparar en bild av XMB:n på Macen |
| `ps3 send <filer/mappar>` | Laddar upp till rätt mapp via `.part`-filer, fortsätter avbrutna uppladdningar, hoppar över spel som redan finns, uppdaterar spellistan och visar en popup. Håller Macen vaken; `--verify` jämför MD5, `--shutdown-when-done` stänger av PS3:an efteråt |
| `ps3 saves [backup\|local\|restore <namn>]` | Sparfilerna på PS3:an, kopiera dem till Macen, lägg tillbaka en (inte under spel; det som låg där sparas först) |
| `ps3 backup` | Sparfiler och systemfiler (xRegistry.sys, webMAN:s inställningar, boot_plugins) till Macen; läser bara konsolen |
| `ps3 maintain [--fix]` | Kvarglömda paket, avbrutna överföringar, dubbletter, cache, saknade plugins; `--fix` tar bort paket och `.part`-filer |
| `ps3 analyze` | Vad som tar plats på `/dev_hdd0`, räknat på konsolen |
| `ps3 rip` | Kopierar PS3-skivan i spelaren till `/dev_hdd0/GAMES` (`--abort` stoppar) |
| `ps3 apps` | Installerade program jämförda med senaste versionen på GitHub |
| `ps3 apps available` | Hela katalogen: vad du har (✓), vad som har uppdateringar (↑), vad som kan installeras (↓) och vad som inte fungerar på din PS3 (⊘) |
| `ps3 apps info <namn>` | Version, om programmet fungerar på din PS3 och README från GitHub (`--no-readme`, `--json`) |
| `ps3 apps install <namn…>` | Hämtar senaste versionen från GitHub och installerar, t.ex. `ps3 apps install ezremote` (`--reinstall`, `--dry-run`) |
| `ps3 apps install <pkg…>` | Installerar en egen .pkg-fil direkt och arkiverar den i `_Installerat/Paket` |
| `ps3 apps update [namn…]` | Granska och installera uppdateringar (`--dry-run`, `-y`) |
| `ps3 popup <text>` | Visar ett meddelande på TV:n |
| `ps3 refresh` | Uppdaterar spellistan (som SELECT + L3) |
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
