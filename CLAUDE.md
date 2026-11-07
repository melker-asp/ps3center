# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## The project

PS3 Center controls a PS3 (Super Slim, HFW 4.93, PS3HEN, webMAN MOD) from a Mac: status, uploading
games, installing and updating homebrew. The user writes Swedish; all text in the CLI, app and
documentation is English, while code, identifiers and comments are English as before (decision Nov 7, 2026).

The inspiration is Mole (a CLI with a separate Mac app). Here the CLI and the app share the same engine. Read
`DESIGN.md` before adding features: it has the principles, the tabs and facts about the console that the
code builds on. `PLAN.md` has the roadmap phase by phase and what to try on the console.

```
Sources/PS3Kit/   library with all logic (webMAN HTTP, FTP, ISO/SFO/PKG, catalog, updates)
Sources/ps3/      the CLI (swift-argument-parser), a thin layer on top of PS3Kit
App/              the SwiftUI app; App/project.yml → xcodegen → App/PS3Center.xcodeproj (not checked in)
Tests/            swift-testing, fixtures from real responses from the console
```

## Commands

```bash
swift build                     # PS3Kit + CLI
swift test                      # all tests
swift test --filter parsesSysInfoAndStatusPage   # one test
make install                    # release CLI → ~/.local/bin/ps3
make app                        # xcodegen + xcodebuild (requires `brew install xcodegen`)
make run-app                    # build and open the app
make install-app                # Release build → /Applications/PS3 Center.app (updates an existing one)
make icon                       # render the app icon again from scripts/make_icon.swift
make snapshot DIR=/tmp/shots    # render every tab to PNG and exit (requires a reachable PS3)
make snapshot-fixtures DIR=/tmp/shots   # the same from PS3Kit's Fixtures, without a PS3
```

If you add a file to `App/Sources` the project must be regenerated (`make project`), otherwise
xcodebuild won't find it.

## In a cloud session (Linux)

- **Only macOS can build.** PS3Kit uses Network.framework and CryptoKit, and the app is SwiftUI,
  so neither `swift build` nor `swift test` works on Linux.
- **CI checks every commit** in a pull request and on main. GitHub Actions
  (`.github/workflows/ci.yml`, macos-15) runs `swift test`, builds the CLI and builds the app. Push
  and read the CI result instead of building locally. If the repo is public, GitHub's runners cost
  nothing. If it is private, the repo variable `CI_RUNNER=self-hosted` can run the job on the user's own
  Mac, but never in a public repo (a pull request from a fork could run code there).
  The repo contains nothing that can't be public: no PSID/IDPS, no keys or
  passwords. Keep it that way.
- **Screenshots:** CI renders every screen from `Fixtures` (`PS3CENTER_FIXTURES=1`) and uploads
  them as the artifact `screenshots`. Review design changes there. New screens are added to
  `Snapshot.run`, and the data they need to `Fixtures.swift`.
- **Report with screenshots.** When a phase or a change that shows in the app is done, fetch the
  artifact `screenshots` from the CI run for that commit. Then send the screens that are new
  or have changed together with the report (the user's request, Oct 24, 2026). If CI can't be
  run, say so, and don't send old images as if they were new.
- **The console is only on the user's home network.** Anything that needs a real PS3 (snapshot,
  installations, `ps3 status`) the user has to run on their Mac. Describe what to try.
- **CI may have an older Xcode** than the user's (Xcode 27 / Swift 6.4). Avoid brand-new APIs without
  `if #available`.

## Architecture that takes several files to understand

- **Finding the console:** `ConsoleLocator` tries `--host`, then `PS3_HOST`, then the saved config and
  finally a network search (`Discovery`). A new address is saved in `~/.config/ps3center/config.json`,
  the same file the app reads.
- **webMAN's quirks** are handled in `WebMAN.swift` and `FTPClient.swift`:
  - every HTTP request sends `Connection: close` and runs one at a time, except commands that can take minutes
    (`/install.ps3`, `/stat.ps3`): they go through `WebMAN.long` on a connection of their own and
    set `WebMAN.isBusy`, so that the app doesn't mistake slow status responses for the console being gone
  - ENODATA on the data connection means end of file
  - `APPE` continues an interrupted upload

  Don't change any of this without reading the section on facts in DESIGN.md.
- **A running game** is detected via PS3MAPI `PROCESS GETCURRENTPID` + `GETNAME`. It drives
  "warn and wait" (`TransferService.waitUntilIdle`): installation and refreshing the game list
  wait until no game is running.
- **The installation is done** when `PARAM.SFO` in `/dev_hdd0/game/<titleID>` has a new `MDTM` and the folder
  has stopped changing. webMAN does *not* delete the package, despite what the wiki says. If nothing starts to happen,
  `/install.ps3` is sent once more, then an error with advice. `ConsoleStore` goes offline only after three
  missed status calls in a row.
- **The catalog** (`Catalog.swift`): each app has a title ID, read from the pkg header at offset
  0x30. `AppsService` compares the installed `APP_VER` with the GitHub release. If PS3 Center itself
  installed the app, the link tag ↔ `APP_VER` in `installed.json` is used instead of
  `VersionStyle`.
- **The compatibility check** (`Compatibility.swift`): `ConsoleProfile` is read from the snapshot (HEN/CFW,
  CEX/DEX, firmware) and compared with `CatalogEntry.requirements`. `AppsService.status` sets
  `compatibility`/`blocked` and zeroes `canInstall`/`installable`; `AppsService.install` and the CLI's
  `apps install` (also custom .pkg files via title ID) stop before download. Unknown firmware blocks
  apps that have requirements.
- **The detail page:** `AppsStore.selectedID` opens `AppDetailView` in the Apps tab. The README is fetched with
  `GitHub.readme` and parsed by `Readme` (blocks + inline Markdown that `AttributedString` draws).
  The same data is shown by `ps3 apps info`.
- **The games** (`GameLibrary.swift`): `GameLibraryService.scan` lists webMAN's game folders
  (PS3ISO, GAMES, PS2ISO …) on hdd0 and USB plus `/dev_hdd0/game`. Title and title ID come from PARAM.SFO,
  for ISOs webMAN's copy in `/dev_hdd0/tmp/wmtmp`, and are cached in `~/Library/Caches/ps3center/`.
  `GameListing` is the network-free part that the tests feed with listings. Installed games in
  `/dev_hdd0/game` are started via title ID and uninstalled only on request (`delete`, after a
  question; `UninstallGuard` protects what HEN needs). `GamesStore` and `GamesView` are the Games tab.
- **The Mac's packages** (`PackageFolders.swift`): `PackageFolders` (`packageFolders` in config.json,
  the type PKG in `ps3 config folder`) and `PackageLibrary.scan` (.pkg in the folder and one level down,
  name from the catalog via title ID). `AppsService.installOwnPackage` runs the compatibility check and
  leaves the file in place; `AppsStore` takes the packages in the same queue as the catalog ("From Mac", `ps3 apps mac`).
- **The Mac's games and the queue:** `GameFolders` (folders per type in config.json plus the mirror folder),
  `LocalLibrary` (the same `GameListing` rules as the console, metadata from the images) and
  `LibraryMatch`. `TransferQueue` (queue.json) is shared by `ps3 queue` and the app's `TransferStore`:
  all changes go through `TransferQueue.edit`, which rereads the file under a lock, and
  `QueueLock` makes sure only one process sends. Everything is sent via `TransferService.send`, which
  uploads to `.part` and renames. `QueueRunner.send` and `ps3 send` retry after network errors
  (`RetryPolicy`). `FolderWatch` (watch.json) finds new games in watched folders;
  the app's `TransferStore` and `ps3 watch` put them in the queue. `FTPClient.Tuning` controls chunk size and
  the number of chunks in flight (config.json `ftpChunkKB`/`ftpWindow`).
- **The game server** (`NetServer.swift`): a custom read-only ps3netsrv. The root is the connected
  folders merged per type (`/PS3ISO` …); `<name>.SFO`/`.PNG` next to a PS3 ISO are read from the
  image. Write commands close the connection and only the console's address is let in. A
  Mac game has `netPath`, and the app starts it as `/net<slot>` + `netPath`. `NetServerStore`
  keeps the Mac awake while a `/net` path is mounted and sets up webMAN with `WebMANSetup`
  (a free network server; the number is saved as `netServerSlot` in config.json).
- **Control** (`Control.swift`): `PadButton` (fixed names for `/pad.ps3`), disc, screenshot,
  `FanControl` (targets only in dynamic mode), `Reachability` (ping/TCP when webMAN doesn't respond = HEN
  off) and `PlayLog`/`PlayTracker` (play time from the status, `playtime.json`). The app: `ConsoleStore`
  has the buttons, `RemoteView` the remote, `MenuBarView` the menu bar. Files from outside (the Finder
  service, the menu bar, Shortcuts in `Intents.swift`) go via `Inbox` to the review view.
- **Maintenance** (`Maintenance.swift`): `SaveBackupService` (saves to `Saves/<user>/
  <folder>` with a manifest per folder, the previous copy in `.previous`), `SystemFiles`, `MaintenanceService`
  (report + `fix` which only removes packages and `.part`), `StorageAnalyzer` (`/stat.ps3`) and
  `DiscRipper` (`/copy.ps3`, progress over FTP). The app: `MaintenanceStore` and `MaintenanceView`.
- **Phase 9** (ideas from aldostools/Resources):
  - `ConsoleExtras.swift`: XMB reload, recording, in-game screenshots, beep, in-game music,
    `UpdateBlock` and `MediaImport` (videos and photos to the Mac, `imported.json`).
  - `PlayCompatibility.swift`: `PlayCheck`, `LibCrypt` (225 IDs from webMAN MOD) and `PS2Classic`
    (only `.BIN.ENC` on HEN).
  - `IRD.swift`: `IRD`, `DiscVerifier` and `IRDLibrary` (FlexBy420 on GitHub). `ISOImage` reads
    Joliet for that.
  - `ErrorCodes.swift`: 0x8001xxxx from RPCS3. `TitleDatabase.swift`: aldostools' titleid.txt.
  - In the app the buttons are in the Status tab (Record), Remote (Reload XMB, Beep,
    In-Game Screenshots, In-Game Music), on the game page and in Maintenance.
- **Phase 10** (the ISO tools from the PC, `ISOTools.swift`): `PS3ISOBuilder` makes an ISO of a
  game folder with makeps3iso's layout (see DESIGN.md), `PS3ISO.split`/`join`/`extract`, and
  `PartWriter` writes everything as `.part` and renames when it is complete. `USBDrive.plan` splits ISOs over
  4 GB and turns a game folder with a file over 4 GB into an ISO in parts. CLI: `ps3 iso`. The app:
  Copy to USB Drive… in the Games tab (Mac) opens `USBCopyView` with `USBCopyModel`.
- **PS2 Classics** (`PS2Classics.swift`): `PS2ClassicMaker` encrypts a PS2 ISO (or .cue/.bin)
  to `<name> [ID].BIN.ENC` as ps2classic does, for the placeholder `PS2U10000` (PS3HEN makes its
  license itself). `PS2ClassicKeys` downloads, imports and checks the keys. CLI: `ps3 ps2`.
  The app: Convert to PS2 Classic… in the right-click menu on a PS2 game under Mac (`PS2ClassicView`).
- **Progress:** `TransferEvent` goes via `@Sendable` callbacks. The CLI prints them (`TransferPrinter`),
  the app puts them in `AppsStore.operations` on the MainActor.
- **The app:** `ConsoleStore` fetches status every 3 seconds, `AppsStore` has an installation queue that takes
  one app at a time because webMAN's FTP can't handle parallel transfers. Design tokens are in
  `Theme.swift` (Mole style), and the rules for using them (one white button per screen,
  `destructive` for removals, `DoneButton` on sheets, `.font(.ui(…))` sizes, English dates via
  `Theme.locale`/`Format`) are under Appearance in DESIGN.md. Never compare a display string in
  code (a status text, a label): keep a flag or an enum, so text can change freely.

## Rules

- **Requirements in the catalog must have a source** (README, release notes). Don't guess that something requires
  CFW; a wrong requirement blocks an app that works.
- **HEN and plugins (ds45pad) are never installed automatically.** They only get `notifyOnly` with advice.
  A broken sprx can make the console freeze at startup.
- **Never save or show PSID/IDPS.** `/cpursx.ps3` contains them.
- **No built-in downloading of games from ROM or ISO archives.** `send` takes the user's own files.
- **The keys for PS2 Classics are never in the repo** (the user's decision Nov 7, 2026): the code has
  only their SHA-256. They are fetched on request from webMAN MOD's repo on GitHub (or imported) to
  `~/.config/ps3center/ps2classic-keys.json` with permissions 0600, and are never printed, logged
  or put in tests or Fixtures.
- **Game updates** may be fetched from Sony's official update server, as RPCS3 does: only game
  patches, never firmware (PUP), without PSN sign-in, and a patch that requires newer
  system software than the console's is blocked. Nothing may be able to update the console or lead to a ban
  (the user's decision Oct 24, 2026).
- **Brewology** is behind a Cloudflare protection and must not be circumvented. Apps that are only found there
  get a link.
- **From the saves' PARAM.SFO only TITLE and SUB_TITLE are shown,** never the account fields.
- **boot_plugins.txt is never changed by PS3 Center;** missing plugins are only reported.
- **The fan is only changed as a target in webMAN's dynamic mode, 60–75 °C,** never as a fixed speed.
- **No free text to `/pad.ps3`:** "cross=" switches the OK button and restarts the console.
- **Uninstall and delete:** only a folder directly in `/dev_hdd0/game`, never what HEN needs
  (`UninstallGuard`), never while a game is running, always after a question. A save is copied to
  the Mac before it is removed from the console.
- **webMAN's settings are only changed via `WebMANSetup`:** the whole form that Safari would
  send, a copy of the settings first and a check afterwards. An incomplete call to `/setup.ps3`
  resets all the other settings.
- **The clock is never set by PS3 Center:** webMAN's `/fixclock.ps3` writes the secure clock.
  USB drives are not "ejected" via webMAN; it is only a faked event.
- **System updates are only blocked via `UpdateBlock`,** on request: webMAN MOD's own file
  in `/dev_hdd0`, never anything in dev_flash.
- **Nothing is fetched from ps3.aldostools.org** (self-signed certificate, HTTP only) or psdevwiki
  (Cloudflare). Use the copies on GitHub.
- **Everything that changes the console is logged** with `OperationLog.record`, which is shown with `ps3 history` and in
  the app's history table, and has `--dry-run` in the CLI.
