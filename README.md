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

Version 0.1 har två flikar i Mole-stil:
- **Status:** hälsa, CPU, RSX, fläkt, ledigt utrymme, nätverk, vad som spelas och versioner, med
  löpande kurvor och historiken från `ps3 history`.
- **Appar:** uppdateringar ("02.40 → 02.41", Uppdatera / Uppdatera alla) och en Hämta-lista.
  Ikonerna är programmens egna XMB-ikoner från konsolen. Klicka på ett program för en
  detaljsida med version, om det fungerar på din PS3 och README med bilder från GitHub.

`make snapshot DIR=/tmp/shots` renderar flikarna till PNG utan att något fönster öppnas.

## Kommandon

| Kommando | Gör |
|---|---|
| `ps3 status` | Hälsa, temperaturer, fläkt, ledigt utrymme och vad som körs. `--watch` uppdaterar löpande, `--json` ger JSON |
| `ps3 send <filer/mappar>` | Laddar upp till rätt mapp, fortsätter avbrutna uppladdningar, hoppar över spel som redan finns, uppdaterar spellistan och visar en popup |
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
