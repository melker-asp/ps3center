# PS3 Center – roadmap to the complete command center

This plan takes PS3 Center from "status and homebrew" to a single place where everything about the PS3
is done from the Mac: see and start the games, send games from the Mac's folders, play straight from the Mac,
control the console and take backups. The principles in [DESIGN.md](DESIGN.md) apply to everything new.

## Where we stand (November 7, 2026)

All ten phases below are built and have tests in `swift test`, but most of it has not been tried on
the console yet (see Try on the console). The app has the tabs Status, Games, Apps and Maintenance,
Transfers, the menu bar and an icon of its own. `ps3` with no arguments opens a menu.

Left to build, and what it is waiting for:
- `mygames.xml` as a source for the game list: test 1.
- Reading title and icon straight from an ISO on the console (`REST`, a `ByteSource` for `ISOImage`): test 2.
- Two uploads at the same time: test 5. Only if it measures as faster.

Left outside the code:
- CI hasn't been able to run since October 24: GitHub doesn't start the macOS jobs until payment
  is sorted out (the repo is private). The alternatives are in CLAUDE.md: the repo variable
  `CI_RUNNER=self-hosted` or a public repo. Until then `swift test` and `make app` are run on
  the Mac before every commit.
- Tests 1–16 under Try on the console.

Built last (Nov 7, night): phase 11, easier for new users: Settings in one place, a setup guide on
the first launch, Help with eleven guides and a glossary (also `ps3 guide`), ⓘ on the status cards and
tooltips on every button that changes the console, a tour and tips, and more to adjust (the status
cards, the tabs, the menu bar's buttons, °F, the text size). Test 20.

Before that (Nov 7, evening): `ps3 mcp`, a read-only MCP server, and three ideas from ps3.world:
packages from GitHub are checked against size and SHA-256, New in Browse and more error codes with advice
(test 16).

Built Nov 7: Ignore in Apps and `ps3 apps ignore`/`unignore`, and a review before
and a report after Update All (test 15). The same day: phase 10, the ISO tools from the PC
(`ps3 iso`, Copy to USB Drive… in the Games tab) and PS2 Classics (`ps3 ps2`, Convert to PS2 Classic…
on a PS2 game under Mac), tests 17 and 18.

Built Nov 6: sorting by name, size and recently added (the Games tab and
`ps3 games --sort`), `send` saving title, title ID and icon for the games it sends, the time with
a cable in the review, a tip when the Mac is on battery and the menu in `ps3`.

## Target picture

| Where | Contents |
|---|---|
| **Status** | As now, plus power buttons (Shut Down, Restart, Quit Game) |
| **Games** (new, Nova Pink) | Cover grid like the PS app's library. Two modes: *PS3* and *Mac*. Detail page with banner, Play / Mount / Delete / Send |
| **Apps** | As now |
| **Maintenance** (new, Cosmic Red) | Saves, system files, cleanup, storage map |
| **Transfers** | A drawer reachable from all tabs (badge in the tab bar): queue, speed, time remaining, "when the queue finishes" |
| **Menu bar** | Status, queue progress and quick buttons; keeps the queue and the game server going when the window is closed |

The CLI gets the same features: `ps3 games`, `ps3 queue`, `ps3 speedtest`, `ps3 power`, `ps3 saves`,
`ps3 maintain`, `ps3 analyze`.

---

## FTP, wait times and leaving the PS3 on

### Why it takes so long

- **Wi-Fi is the biggest brake.** The PS3 only has 2.4 GHz Wi-Fi, and according to the responses from your
  console (the fixtures) it is on Wi-Fi ("WLAN"). Reports from forums (not our own measurements)
  range from under 1 to around 15 MB/s over Wi-Fi and 10–40 MB/s with a cable; test 4 under
  Try gives your numbers. Example: Test Drive Unlimited 2 (9.6 GB) takes just under an hour at 3 MB/s
  and around 6–7 minutes at 25 MB/s.
- **webMAN handles at most two transfers at the same time** (`MAX_FTP_TRANSFERS 2` in `include/ftp.h`), so
  there is little to gain from running several in parallel. It is tried anyway (test 5 under Try).
- **Our own client** sends 256 KB at a time and waits for each chunk. That can cost a bit; it is
  measured in phase 5 before anything is changed.

### Three ways to get games in

| | FTP to the hard drive (`send`) | USB drive | Play from the Mac (ps3netsrv) |
|---|---|---|---|
| Speed | Wi-Fi: slow. Cable: good | Fastest for many games | No copying at all |
| The Mac must be on | During the transfer | No | All the time while playing |
| Best for | Games you keep | Loading many games at once | Trying games, PS1/PSP, large libraries |
| Limitation | An interruption can cost the whole file (see below) | FAT32: files over 4 GB are split into `.iso.0`, `.iso.1` … | A cable is needed for PS3 games; PS2 ISOs are copied to the hard drive anyway when mounted |

The plan builds all three (phases 3–6), but **the single biggest improvement costs no code: a
network cable to the PS3.** If the router doesn't reach, a cable can be run directly between
the Mac (USB-C adapter) and the PS3, or a simple switch or powerline adapters can be used.

### Should the PS3 always be on?

Facts that decide it:
- **HEN must be enabled after every start.** The only thing the PS3 gains from being on is that it is
  always ready. Even if it could be woken remotely, someone would have to press the HEN icon.
- **The PS3 can't be woken from the Mac.** It has no regular Wake-on-LAN. Remote start in the Remote
  Play settings is made for PSP and Vita.
- **webMAN turns off "Auto Power Off" during an FTP session** and during `/install.ps3` and
  `/download.ps3`, and turns it back on afterwards (`include/init/autopoweroff.h`). A long
  transfer is therefore not shut off by the console itself.
- **If the Mac goes to sleep in the middle of a transfer, the PS3 deletes the half-finished file.** webMAN waits
  60 seconds for data; after that the transfer counts as failed and the file is deleted
  (`cellFsUnlink` in `include/ftp.h`). Only when the connection is closed properly (as with ctrl-C)
  does the file stay so that `APPE` can continue.
- **Power:** no measurement of the Super Slim in standby was found. Calculated at 50 W, around the clock is
  roughly 440 kWh per year, that is 400–900 SEK depending on the electricity price. On top of that come fan, dust and a
  hard drive that never rests. An energy meter in the outlet gives the real value.

Recommendation: **not around the clock, but in batches.** Start the PS3, enable HEN, put the games in
the queue and let PS3 Center do the rest: the Mac is kept awake as long as the queue runs, the PS3 is shut down when the queue
finishes and the Mac is allowed to sleep again. That becomes the "night mode" in phase 4. If PS3 Center is ever to be
a game server all the time (phase 6) it is the Mac that needs to be on instead, and then a Mac mini
or a NAS is better than a laptop.

For the Mac:
- A laptop Mac on battery goes to sleep when the lid is closed, whatever the app does. With a charger and an external
  display it works fine.
- The app and `ps3 send` should themselves prevent the Mac from sleeping while the queue runs (like `caffeinate -i`).
  The display may turn off.

---

## Phases

Each phase becomes a PR. Each new screen is added to `Snapshot.run` with data in `Fixtures.swift`, so that
the CI artifact `screenshots` shows it. Everything that changes the console is logged with `OperationLog.record`
and has `--dry-run` in the CLI.

### Phase 1 – The game library on the PS3

**Goal:** see all games on the console with icon, title, title ID, size and location, and start them.

**Status Oct 24, 2026:** built without tests on the console, with fallbacks where facts are missing. Done
are the listing (step 2 below plus the wmtmp cache), icons and backgrounds, start/mount/quit/delete,
`ps3 games` and the Games tab with a detail page. Sorting by size and date and `send` saving what
it knows are built (Nov 6). Left: `mygames.xml` (waiting for test 1) and reading in the ISO via `REST`
(waiting for test 2).

PS3Kit:
- `Game.swift`: `Game` (title, title ID, platform, region, size, path) with `Game.Platform`
  (PS3, PSN, PS2, PS1, PSP, Blu-ray, DVD). The region is read from the title ID: `BLES`/`SLES` = Europe,
  `BLUS`/`SLUS` = USA etc. Locations on the Mac come in phase 3.
- `GameLibrary.swift` (`GameLibraryService`) finds the games in three steps, cheapest first:
  1. **webMAN's own list** `/dev_hdd0/xmlhost/game_plugin/mygames.xml` (title, icon and path
     or title ID per game) and its cache in `/dev_hdd0/tmp/wmtmp` (`<name>.SFO`, `<name>.PNG`).
     The format is checked against a real file first (test 1 under Try).
  2. **FTP listing** of `PS3ISO`, `GAMES`, `GAMEZ`, `PS2ISO`, `PSXISO`, `PSPISO`, `BDISO`, `DVDISO`
     on `/dev_hdd0` and `/dev_usb00*`, with one level of subfolders like webMAN. Gives size and `MDTM`.
  3. **Read in the ISO on the console** when nothing else is available: `ISOImage` gets a `ByteSource` so that the same
     code reads local files and, via FTP `REST` + `RETR`, only the sectors that are needed
     (PVD, directories, `PARAM.SFO`, `ICON0.PNG`). webMAN has `REST` according to the source code.
- PSN games and game updates from `/dev_hdd0/game/*/PARAM.SFO`: `CATEGORY` `HG` is a game,
  `GD` is data or an update that is tied to the game with the same title ID ("update
  1.05 installed"). Apps from the catalog and homebrew IDs are kept out.
- Metadata per format: PS3 `PARAM.SFO`; PS2 `SYSTEM.CNF` (`BOOT2` → `SLES-12345`); PS1 `SYSTEM.CNF`
  in `.bin` with 2352-byte sectors (`ISOImage` needs the MODE2 mode); PSP `UMD_DATA.BIN` and
  `PSP_GAME/PARAM.SFO`.
- Cache in `~/Library/Caches/ps3center/` (list + icons), key path + size + `MDTM`. A new
  read becomes just a listing.
- `send` saves what it already knows about the games it sends (title ID, title, icon), so that those games
  never need to be read on the console.
- `GameLibraryService` also controls: mount (`/mount.ps3/<path>`), start (`/play.ps3/<path>`,
  installed games with `/play.ps3?<title ID>`), unmount (`/mount.ps3/unmount`), quit the game
  (`/xmb.ps3$exit`), delete (FTP `DELE`/`RMD`). Installed games are never deleted by PS3 Center.

CLI:
- `ps3 games` (grouping per platform, `--platform ps2`, `--json`), `ps3 games info <name>`.
- `ps3 games play <name>`: if another game is running it asks whether to quit it (`-y` skips
  the question). `ps3 games mount|unmount|exit`.
- `ps3 games delete <name>` with a question, `--dry-run` and log.

The app:
- `GamesStore` and `GamesView`: grid with the XMB icons (320×176), filter pills (All, PS3, PS2,
  PS1, PSP, Movies), search and sorting (name, size, recently added). The running game is highlighted.
- `GameDetailView` reuses `HeroBackdrop` with the game's `PIC1.PNG`. White main button "Play",
  outline buttons Mount and Delete (with confirmation).
- Fixtures: a handful of games of each kind. The icons are drawn as colored placeholders in the app, so that
  CI doesn't need the network. Screens: `games`, `games-detail`.

Done when: `ps3 games` shows the same games as the XMB, and a game can be started from the app.

### Phase 2 – Covers

**Goal:** real cases in the grid, not just XMB icons.

**Status Oct 24, 2026:** built. `CoverService` (the sources below, your own image by dragging it onto the
banner, `ps3 games covers --to-ps3`) and game updates from Sony (`GameUpdateService`,
`ps3 games updates|update`, "Check for Updates" and a box on the game's page). The grid shows
cases or XMB icons. Left to try at home: that Sony's server answers and that the certificate is accepted.

- `CoverStore` in PS3Kit with sources per platform, all keyed on title ID and saved permanently in
  `~/Library/Caches/ps3center/covers/`:
  - PS3: the game's own `ICON0`/`PIC1` (always available), and cases from GameTDB or webMAN's
    online source (DeViL303). The exact URL and terms are worked out from webMAN's source code and GameTDB before
    the code is written.
  - PS2 and PS1: the collections `xlenore/ps2-covers` and `xlenore/psx-covers` (the same ones PCSX2 and
    DuckStation use), keyed on serial number. README and license are read first.
  - PSP: `ICON0` from the ISO until a case source is chosen.
- Changing the cover yourself: drag an image onto the detail page.
- Optional: "Show covers on the PS3 too" puts the cases as `<TITLEID>.JPG` in
  `/dev_hdd0/tmp/wmtmp/covers`, where webMAN looks (logged, `--dry-run`).
- The grid gets the choice Icons / Cases.

### Phase 3 – The Mac's game folders and sending from there

**Goal:** connect folders per type and send games with one click or by dragging them onto the window.

**Status Oct 24, 2026:** built: `GameFolders`, `LocalLibrary` (reads PARAM.SFO, SYSTEM.CNF and ICON0 from
ISOs and raw .bin images), `LibraryMatch`, the Mac mode in the Games tab with selection, review view,
Game Folders and drag and drop; `ps3 config folder` and `ps3 games mac`. Watched folders are built
(Oct 25): `FolderWatch`, the Watch toggle in Game Folders, `ps3 config folder watch` and `ps3 watch`.

- `config.json` gets `folders`, a list of folders per type:
  `{"PS3ISO": ["~/Games/PS3"], "PS2ISO": ["/Volumes/External/PS2"], …}`. The mirror folder's
  `dev_hdd0/PS3ISO` etc. is counted automatically, so anyone who already has a mirror folder doesn't need to
  do anything.
- CLI: `ps3 config folder add PS3ISO ~/Games/PS3`, `folder list`, `folder remove`.
- The app: Settings → Game Folders, one row per type with "Choose Folder…" or drag in a folder. An
  external drive that isn't connected is shown as "not connected", not as removed.
- `LocalLibrary` reads the folders with the same metadata as phase 1 (fast, the files are local), and rereads
  when something changes (FSEvents).
- Matching Mac ↔ PS3 on title ID and platform, then size: *Mac only*, *On both*,
  *PS3 only*, *Interrupted upload* (smaller on the console).
- The Games tab gets the modes *PS3* and *Mac*. Select several → white button "Send 3 games ·
  24.1 GB" → a review view as in DESIGN.md: checkboxes, free space before and after, estimated
  time from the most recently measured speed and warnings ("Wi-Fi: about 55 minutes, with a cable
  about 7").
- Drag files or folders anywhere in the window → the same review view.
- Watched folder (off by default, per folder): new games are queued when the file has stopped growing.

### Phase 4 – Transfers that survive interruptions

**Goal:** nothing is lost when the Mac goes to sleep or the network hiccups, and the queue takes care of itself.

**Status Oct 24, 2026:** built: `TransferQueue` with lock, `.part` + `RNTO`, clean close on pause and
sleep, `KeepAwake`, MD5 via `/md5.ps3`, "When the Queue Finishes" and notifications; `ps3 queue` and
Transfers in the app. Retries after network errors are built (Oct 25): `RetryPolicy` waits 15 s,
30 s, 1, 2 and 4 minutes and continues from the `.part` file; if webMAN has deleted it, that is said.

- `TransferQueue` in PS3Kit, saved in `~/Library/Application Support/ps3center/queue.json`: add,
  pause, resume, reorder, remove. One transfer at a time. A lock makes sure the
  app and the CLI never send at the same time. CLI: `ps3 queue` (`list`, `start`, `pause`, `clear`).
- **Upload to `<name>.part` and rename when the file is done** (`RNFR`/`RNTO`, which webMAN has).
  That way a half game is never shown in the XMB, and an incomplete file can't be mistaken for a complete one.
- **Stop properly:** pause, cancel, when the app quits and when the Mac is about to sleep
  (`NSWorkspace.willSleepNotification`) the data connection is closed with FIN (`NWConnection.cancel()`,
  not `forceCancel()`), so that webMAN keeps the file and `APPE` can continue. After wake-up
  the console is found again and the queue continues.
- **Keep the Mac awake** with `ProcessInfo.beginActivity(options: .idleSystemSleepDisabled, …)` as
  long as the queue runs, in both the app and the CLI. A tip in the app when the Mac is on battery.
- **Verification:** the size is checked as now. Optional MD5: computed on the Mac while the file is read
  (free) and compared with `/md5.ps3/<path>` on the console, which takes a few minutes for a large
  game. On in night mode, off otherwise.
- **If the connection breaks anyway** the queue retries with a pause in between and continues from `SIZE`. If
  webMAN has deleted the file, that is said outright ("The PS3 deleted the half-finished file, starting over").
- **When the queue finishes:** Nothing / Notify on TV / Shut Down PS3 (`/shutdown.ps3`, logged), plus
  a notification on the Mac. CLI: `ps3 send … --shutdown-when-done`.

### Phase 5 – Faster: measure, tune and USB

**Status Oct 24, 2026:** `ps3 speedtest` (and the button in Transfers) and `ps3 usb prepare` are built.
The tuning is built (Oct 25): 1 MB chunks and two in flight, adjustable with `ftpChunkKB` and
`ftpWindow` in config.json to compare with the speed test (test 13). The time with a cable is shown in the
review (Nov 6): from a measurement over LAN if there is one, otherwise 10–40 MB/s. Two files
at the same time is not built (test 5).

- `ps3 speedtest` (and a button in Transfers): sends 256 MB from memory to `/dev_hdd0/tmp`,
  fetches it back and deletes the file. Shows MB/s in both directions and whether it is Wi-Fi or cable.
  The result is saved and gives the time estimates in the review view.
- Tune the client against `curl` as a comparison: larger chunks (1–4 MB) and a couple of sends in the
  air at the same time. Two parallel uploads (webMAN's max) are also tried. Only what
  measures as faster is kept.
- Suggest a cable when the console is on Wi-Fi and the queue is larger than a couple of GB, with the time for both.
- **The USB route:** `ps3 usb prepare /Volumes/<disk>` (and "Prepare USB Drive" in the Games tab)
  checks that the drive is FAT32, creates `PS3ISO`, `PS2ISO`, `PSXISO`, `PSPISO`, `GAMES` and
  copies the games. PS3 ISOs over 4 GB are split into `.iso.0`, `.iso.1` … (at most 4 GB, equal-sized parts
  except the last, according to webMAN's wiki). Game folders with a file over 4 GB don't work on FAT32
  and are stopped with a message.

### Phase 6 – Play straight from the Mac (built-in ps3netsrv)

**Goal:** the games in the Mac's folders show up and start on the PS3 without being copied.

**Status Oct 24, 2026:** built: `NetServer` (read-only, the connected folders as the root, `.SFO`/`.PNG`
from the PS3 ISOs, only the console's address is let in), `ps3 serve`, Game Server in the Games tab with
the steps for webMAN, "Play from Mac" and the Mac is kept awake while a network game is mounted.
Tested against a custom client in `swift test`, not against the console or the real ps3netsrv yet (test 10).
The menu bar comes in phase 7.

webMAN has a built-in client for ps3netsrv (`/net0`–`/net4`, port 38008). The protocol is small:
16-byte big-endian commands (`OPEN_FILE` = 0x1224, `READ_FILE`, `READ_CD_2048_CRITICAL`,
`STAT_FILE`, `OPEN_DIR`, `READ_DIR` …), defined in `include/netiso.h` in aldostools/ps3netsrv.

- `NetServer` in PS3Kit on `NWListener`, with read-only commands only. Write commands get an error,
  so the console can never change anything on the Mac.
- **The virtual root is the connected folders from phase 3**, merged into `/PS3ISO`,
  `/PS2ISO` etc. Next to each PS3 ISO, `<name>.SFO` and `<name>.PNG` are created on the fly, because
  webMAN fetches them from the server for title and icon. With the regular ps3netsrv you have to produce
  them yourself.
- Only the console's IP address is let in.
- Tests: recorded packets, and a comparison against the real ps3netsrv built from source.
- Setup on the PS3: webMAN's `/setup.ps3` → network server 1 = the Mac's IP and 38008. The app
  shows the steps and checks that it works. The Mac needs a fixed IP (reserve the address in the
  router).
- The app: the "From Mac" badge on games, Play → `/play.ps3/net0/PS3ISO/<file>`. The Mac is kept awake
  while a network game is mounted. The menu bar keeps the server going when the window is closed.
- Limitations to show: PS3 games should go over a cable, and PS2 ISOs are copied to the hard drive when
  mounted (webMAN's wiki).

### Phase 7 – Control the console

**Status Oct 24, 2026:** built: the power row in the Status tab and `ps3 power`/`ps3 disc`, "On but HEN is
off" (ping or TCP reply without webMAN), the remote with XMB image and `ps3 pad`/`ps3 screenshot`,
the fan target (`ps3 fan`), the menu bar with login item, notifications (queue, heat, app updates),
"Send to PS3" in Finder, Shortcuts and play time. Left to try at home: tests 7, 8 and 11.

- **Power:** Shut Down (`/shutdown.ps3`), Restart (`/restart.ps3`) with the warning "HEN must be
  enabled again after the restart", Quit Game, Eject/Insert Disc. CLI `ps3 power off|restart`.
  Logged, `--dry-run`.
- **"On but HEN is off":** if the console answers ping but webMAN doesn't, the connection screen says just that
  and shows how to enable HEN (provided the PS3 answers ping, test 7 under Try).
- **Remote:** `/pad.ps3?<buttons>` on screen and with the keyboard (arrow keys, Return = ✕,
  Esc = ◯), with the XMB as an image via `/xmb.ps3$screenshot?show?fast` every few seconds. Enough to
  activate things and navigate the XMB from the couch.
- **Fan:** show webMAN's mode and target temperature. Changes only in dynamic mode with a target between
  60 and 75 °C (`/cpursx.ps3?max=`), never a fixed low speed. Logged.
- **The menu bar** (`MenuBarExtra`) and login item (`SMAppService`): health, temperatures, what
  is playing, queue progress; Send File…, Refresh Game List, Quit Game, Shut Down.
- **Notifications:** queue done or failed, high temperature, new app updates.
- **Finder and Shortcuts:** "Send to PS3" as a quick action, and App Intents: Send to PS3,
  Start Game, Shut Down PS3, Status.
- **Play time:** `ConsoleStore` already sees which game is mounted every three seconds. The sessions
  are saved locally and give "Last Played" and total play time on the detail page.

### Phase 8 – Backups and maintenance (the Maintenance tab)

**Status Oct 24, 2026:** built: `ps3 saves`/`ps3 backup` and weekly saves in the app (with
the previous copy kept and what was on the console saved before a restore), system files,
`ps3 maintain` with Cleanup, `ps3 analyze` with Storage (via `/stat.ps3`) and `ps3 rip` with Disc.
Left to try at home: test 12.

- **Saves:** `ps3 saves list|backup|restore`. Copies `/dev_hdd0/home/<user>/savedata`
  to `~/Library/Application Support/ps3center/Saves/` (or `_Backups` in
  the mirror folder), only what has changed (size + `MDTM`). Restore only when no game is running,
  with a question and log. Automatically once a week when the console is visible (read-only).
- **System files:** a copy of `/dev_flash2/etc/xRegistry.sys` (the system settings),
  `/dev_hdd0/tmp/wm_config.bin` and `boot_plugins.txt`. Read-only.
- **`ps3 maintain`:** forgotten `.pkg` in `/dev_hdd0/packages`, `.part` from interrupted
  transfers, the same game in both `PS3ISO` and `GAMES`, a large `wmtmp`, lines in `boot_plugins.txt`
  that point to missing files, `hen_updater.off`. A report with Done / Skipped and the reason.
- **`ps3 analyze`:** a storage map over `/dev_hdd0`.
- **`ps3 rip`:** copy the disc in the drive with `/copy.ps3/dev_bdvd` (already planned).

### Phase 9 – What aldostools/Resources gave ideas for

**Status Oct 25, 2026:** built, untried on the console: test 14.

- **Reload XMB** (`ps3 refresh --xmb`, Remote → Reload XMB), and by itself after an
  uninstall when webMAN can do it with Reload XMB.
- **More apps in Apps:** mohasi's File Manager, Yo! Player, Cell Stream, Thermal Bench and
  Ren'Py Player (`mohasi/ps3-dev`), as well as Movian, JellyFin, Simple File Manager MOD, TEE Remote
  Play and TEE Vanced (aldostools Addons). Not Swarm (torrent client) or multiMAN (shares a folder
  with webMAN's cover pack).
- **Covers** for PSP games, and aldostools' PS1/PS2 covers when xlenore's are missing.
- **Recording and images:** `ps3 record` and Record in the Status tab; `ps3 media` and Videos &
  Photos in Maintenance import videos and screenshots to `~/Pictures/PS3 Center`; In-Game Screenshots
  turns on the XMB's screenshots.
- **PS1 and PS2:** the game page and `ps3 games info` say when a PS2 ISO doesn't start on HEN (only
  PS2 Classics do), whether PS2 CONFIG has a fix, and when a PAL PS1 game needs
  LibCrypt data (`ps3 games libcrypt`). The review view warns before a PS2 ISO is sent to HEN.
  `.lsd`/`.sbi` next to a PS1 image are sent along.
- **Checking against IRD:** `ps3 verify` and Verify Against IRD on the game page for a game folder in GAMES.
- **Themes:** a `.p3t` that is sent is installed by the XMB.
- **Small things:** `ps3 beep`, `ps3 music on|off`, `ps3 error <code>` and explained error codes in
  the app, names from aldostools' title list when PARAM.SFO is missing, and `ps3 maintain block-updates` with
  Block in Cleanup.
- **Not built:** setting the clock (webMAN writes the secure clock) and safe ejection of
  USB (webMAN's is a faked event).

### Phase 10 – The PC tools for ISOs on the Mac

**Status Nov 7, 2026:** built, tried on the Mac (see DESIGN.md), untried on the console: test 17.

The tools at ps3.world/iso-tools are Windows programs. This is what they became:

| PC tool | In PS3 Center |
|---|---|
| PS3 ISO Tools: Generator (folder → ISO) | `ps3 iso make`, and by itself for game folders with a file over 4 GB on USB |
| PS3 ISO Tools: Extractor (ISO → folder) | `ps3 iso extract` |
| PS3 ISO Tools: Splitter and Joiner | `ps3 iso split`/`join`, and by itself in `ps3 usb prepare` and Copy to USB Drive… |
| PS3 ISO Tools: ISO Patcher, Game Patcher | Not built: lowers the firmware requirement for CFW 4.20 and 3.55, not needed on 4.93 |
| PS3 Disc Dumper | Already exists: `ps3 rip` copies the disc in the PS3, without a special Blu-ray reader |
| PS3 ISO Decryptor GUI (ps3dec) | Not built. webMAN doesn't read `.dkey`, so an encrypted Redump ISO must be decrypted first |
| PS2 Classic GUI | `ps3 ps2 classic` and Convert to PS2 Classic… (below); the keys only on the Mac |
| PS2 Config Database | Partly: the game page says whether PS2 CONFIG has a fix (phase 9) |

- `ISOTools.swift`: `PS3ISOBuilder` (makeps3iso's layout, multiple extents for files over 4 GB,
  `.66600` parts become one file, `PS3_UPDATE` is left empty), `PS3ISO.split`/`join`/`extract` and
  `PartWriter`, which writes `.part` and renames when everything is done.
- `USBDrive`: ISOs over 4 GB are split for PS3, Blu-ray and DVD; a game folder with a file over 4 GB
  becomes a PS3 ISO in parts in PS3ISO instead of being skipped. `BDISO`/`DVDISO` list
  `.iso.0`.
- The app: Copy to USB Drive… in the selection row under Mac opens `USBCopyView`: the drives as pills,
  what happens to each game (parts, becomes an ISO), free space before and after, progress and Eject.

**PS2 Classics with the keys only on the Mac (built Nov 7, untried on the console: test 18).** Facts
and sources are in DESIGN.md. On HEN only the PS2 Classics Launcher (available in Apps) and a
`.BIN.ENC` in PS2ISO are needed; PS3HEN makes the license itself. This is how it turned out:
- `PS2Classic.encrypt` in PS3Kit: ISO → `<name>.BIN.ENC` with LIMG on the fly (the ISO on the Mac
  is not changed), CommonCrypto for AES-CBC, AES-CMAC on top, CryptoKit for SHA-1. CD games in
  `.bin` (2352 bytes) are first converted to 2048-byte sectors.
- The keys in `~/.config/ps3center/ps2classic-keys.json`, never in the repo, the log or printouts.
  The repo only has the SHA-256 of the seven values, so PS3 Center can say exactly which one is wrong.
- Two ways to get them there: Import… (`ps2classic.c` and `.rifkey`, as PS2 Classic GUI also
  has), or a button that fetches them from webMAN MOD's repo on GitHub and saves them on the Mac.
- `ps3 ps2 classic <iso>` and Convert to PS2 Classic where the review view and the game page today
  warn about PS2 ISOs on HEN. Requires the PS2 Classics Launcher to be installed.
- Test: test 18 (a PS2 ISO on the console). The encryption can be checked back and forth in
  `swift test` with test keys, but whether the game starts only the console shows.
- Decided Nov 7: the keys may live on the Mac, and PS3 Center may fetch them (Download Keys in the
  app, `ps3 ps2 keys --fetch`). Import also exists.

### Phase 11 – Easier for new users, and more to adjust

**Status Nov 7, 2026:** built (all six steps), tried from Fixtures on the Mac; test 20 on the console.

**Goal:** someone who has never used PS3 Center gets from opening the app to a connected console without
reading the README, finds an explanation wherever a word or a button is unclear, and can make the app
fit how they use it.

What it looked like before: the first launch went straight to "Connecting to the PS3…", searched for up
to half a minute and ended in "Can't reach the PS3" with only Try Again. The PS3 folder was first asked
for when an app install had already failed. The settings were in six places (the gear only had the
themes; the weekly backup in Maintenance, Launch at Login in the menu bar, Verify with MD5 in Transfers,
watched folders in Game Folders, the FTP tuning only in config.json). Notifications could not be turned
off one by one, and macOS asked for permission when the first one arrived. There were about 28
tooltips and no help in the app.

One step per PR:

1. **Settings in one place.** The gear and ⌘, open Settings: General (the tab the app opens in, Launch
   at Login, the menu bar icon), Appearance (the themes), Folders (the PS3 folder, with Create… for a
   new user, Game Folders and Package Folders), Notifications (one switch per kind, and whether macOS
   allows them) and Transfers (when the queue finishes, Verify with MD5, the weekly save backup, and
   under Advanced the FTP chunk size and window with Reset). The switches stay where they were too and
   read the same value. A storage rule: what the CLI also reads is in config.json, what only changes
   how the app looks or behaves is in UserDefaults. The console's address comes with the connection
   sheet (branch `worktree-connection-sheet`), which already finds the PS3 and takes a typed address;
   Settings gets a Console section that opens it once that is merged.
2. **A setup guide on the first launch,** when no console is saved: Welcome (what is needed: PS3HEN or
   CFW and webMAN MOD), Prepare the PS3 (enable HEN after every restart), Find your PS3 (the connection
   sheet's search, with firmware, HEN and webMAN for each console), Folders (optional: Create PS3 Folder,
   Game Folders), Preferences (theme, Launch at Login, and the notification permission asked here with
   a reason) and Done (Take the Tour or Start). Skip Setup on every page; a saved console skips it.
   Optional: Explore with Sample Data, the Fixtures with a banner and every button that changes
   something turned off.
3. **A help center with how-to guides.** Markdown in PS3Kit, shown with `ReadmeView` in the app (⌘?
   and the Help menu) and by `ps3 guide` in the CLI: Getting Started, Send Your First Game, Play from
   the Mac, Install and Update Homebrew, Install Your Own .pkg, Back Up Saves, Copy to USB, Make a PS2
   Classic, Game Updates from Sony, Troubleshooting, and The CLI and Claude. Empty views and errors get
   a How? link to the right guide (`HelpTopic`). The guides follow the rules in CLAUDE.md.
4. **Tooltips and explanations.** A glossary in PS3Kit (HEN, CFW, XMB, title ID, PS3ISO/GAMES,
   APP_VER, CEX/DEX, PS2 Classic, LibCrypt, IRD, Game Server, dynamic fan mode), an ⓘ on every status
   card whose limits are read from `Thermal`, `iconLabel` on every icon button and a `.help` that says
   what happens on every button that changes the console. Rules for tooltip text in DESIGN.md, and a
   check in CI for icon buttons without a label.
5. **A tour and tips at the right moment.** Five or six steps after the setup (or from Help): the tabs,
   the status cards, PS3/Mac and drag and drop in Games, Updates in Apps, Transfers and the gear. An
   overlay of our own with `anchorPreference`, so the snapshots can render it. Short tips with TipKit
   (macOS 14) in the PS style, shown once when they matter. Both can be turned off and reset.
6. **More to adjust.** Which status cards show and in what order, hiding tabs, the menu bar's quick
   buttons, °C or °F (only the display; the fan target stays 60–75 °C) and the text size (every size
   goes through `Font.ui`, so one factor is enough). No colour picker of our own: the PS app's themes
   keep the look together.

How it turned out, where it differs from the plan above:
- **Settings** has seven sections: General (open in, Launch at Login, tabs, the menu bar and its
  buttons), Appearance (text size, temperatures, theme), Status (the cards), Folders, Transfers,
  Notifications and Help (Open Help, Show Setup Again, Take the Tour, Show Tips).
- **The setup guide's Find step** uses the app's own search (`ConsoleLocator`) and a typed address
  (`ConsoleAddress.clean`, `ConsoleStore.connect(to:)`), the same `AddressEntry` that the connection
  screen got. The connection sheet's list of consoles and cable advice can replace it once that branch
  is merged; until then Settings has no Console section.
- **Tips are our own** (`AppTip`, `TipCard`), not TipKit: TipKit only resets its tips before
  `Tips.configure()`, so Show Them Again would need a restart, and its views don't render in the
  snapshots. Ours are a set in UserDefaults and draw like the rest of the app.
- **Explore with Sample Data** (optional) is not built: every store and button would need a demo mode.
- **Help** opens from ⌘?, the ? beside the gear, Settings → Help, the How? links in empty views and on
  the connection screen, and the ⓘ popovers. Links between guides are `ps3center://guide/<id>`.
- **The guides** were written from DESIGN.md, the README and the code, and checked against it; they
  describe what the app does and claim nothing that hasn't been tried on the console.

## Order and size

| Phase | Size | Builds on | Why in that order |
|---|---|---|---|
| 1 The game library | L | – | What you asked for first; everything else in the Games tab builds on `Game` |
| 2 Covers | M | 1 | Makes the tab a library |
| 3 Mac folders | L | 1 | The second thing you asked for |
| 4 Interruption-safe | M | 3 | Needed before large queues run overnight |
| 5 Faster and USB | M | 4 | Measure first, change later |
| 6 ps3netsrv | L | 3 | Solves the wait time in another way |
| 7 Control the console | M | 1 | Small parts that can be taken in any order |
| 8 Maintenance | M | – | Can be done at any time |
| 9 Ideas from aldostools | L | 1–8 | Built once the rest worked |
| 10 The ISO tools from the PC | M | 5 | You asked for them Nov 7 |
| 11 New users and settings | L | 1–10 | You asked for it Nov 7; Settings first, since the setup guide reuses its rows |

## Try on the console

This can only be done at home, and the answers steer phases 1, 4 and 7. Run on the Mac and paste what
comes out (none of it contains PSID/IDPS). Replace spaces in filenames with `%20`.

```bash
PS3=10.0.1.35   # your PS3's address (ps3 config shows it)

# 1. webMAN's own game list and cache (phase 1)
curl -s "ftp://$PS3/dev_hdd0/xmlhost/game_plugin/mygames.xml" -o mygames.xml && head -c 3000 mygames.xml
curl -s "ftp://$PS3/dev_hdd0/tmp/wmtmp/" | head -40

# 2. Read a piece of an ISO on the console without fetching the whole thing (REST). Expected: "01 43 44 30 30 31" (CD001)
curl -s -r 32768-32773 "ftp://$PS3/dev_hdd0/PS3ISO/<filename>.iso" | xxd

# 3. Start and quit a game from the Mac
curl "http://$PS3/play.ps3/dev_hdd0/PS3ISO/<filename>.iso"
curl "http://$PS3/xmb.ps3\$exit"

# 4. Speed, first over Wi-Fi and then with a cable; MD5 on the console; clean up
dd if=/dev/zero bs=1m count=300 2>/dev/null | curl -s -T - "ftp://$PS3/dev_hdd0/tmp/speedtest.bin" -o /dev/null -w '%{speed_upload}\n' | awk '{printf "%.1f MB/s\n", $1/1e6}'
time curl -s "http://$PS3/md5.ps3/dev_hdd0/tmp/speedtest.bin" | grep -io '[0-9a-f]\{32\}'
curl -s "ftp://$PS3/" -Q "DELE /dev_hdd0/tmp/speedtest.bin" -o /dev/null

# 5. Two uploads at the same time: is it faster in total?
for i in 1 2; do (dd if=/dev/zero bs=1m count=150 2>/dev/null | curl -s -T - "ftp://$PS3/dev_hdd0/tmp/speed$i.bin" -o /dev/null -w "$i: %{speed_upload}\n") & done; wait
curl -s "ftp://$PS3/" -Q "DELE /dev_hdd0/tmp/speed1.bin" -Q "DELE /dev_hdd0/tmp/speed2.bin" -o /dev/null

# 6. What happens to a half-finished file? Start test 4 with count=3000, cancel with ctrl-C and check
#    the size (the file should still exist). Do it again, but turn off the Mac's Wi-Fi for two minutes
#    instead (according to the source code the file should be gone).
curl -sI "ftp://$PS3/dev_hdd0/tmp/speedtest.bin"

# 7. Does the PS3 answer ping when HEN isn't enabled? (right after a restart)
ping -c 3 $PS3

# 8. Virtual controller (◯ is harmless in the XMB) and a screenshot of the XMB
curl "http://$PS3/pad.ps3?cancel"
open "http://$PS3/xmb.ps3\$screenshot?show?fast"
```

9. Measure the power with an energy meter in the outlet: in the XMB, during a game and during a transfer.
10. The game server (phase 6): open Game Server in the app and press "Set Up webMAN for Me" (or
    set network server 1 yourself in `http://$PS3/setup.ps3` with the Mac's address and port 38008
    and run `ps3 serve`). Afterwards check in webMAN's settings that nothing else changed. Do the games show up in the Mac's PS3ISO folder with title and icon? Start one and play
    for a while, preferably both over Wi-Fi and with a cable. Say what `ps3 serve` printed and whether anything stuttered.
11. Phase 7 in the app: Remote in the Status tab (does the XMB on the TV move when you press the
    arrow keys?), − and + on the fan card (only if webMAN runs in dynamic mode), the menu bar
    with the window closed, "Send to PS3" in Finder (right-click → Quick Actions or Services;
    may require the app to be in Applications and to have been started once) and Shortcuts → PS3 Status.
    Turn off HEN with a restart and see whether the app says "HEN is not enabled".
12. Phase 8: `ps3 saves` (are your saves shown with names?), `ps3 backup`, and `ps3 saves restore` on
    a save you have a copy of elsewhere. `ps3 maintain` and `ps3 analyze` (how long did
    it take?). If you have a PS3 disc: `ps3 rip` and see whether the folder in GAMES starts. Also check what
    `curl "http://$PS3/stat.ps3/dev_hdd0/game"` prints, so that the interpretation is right.
13. The last one: watch a folder in Game Folders and copy in a game (does it land in the queue a minute after
    the copy is done?), pull out the network cable in the middle of a transfer and plug it back in
    (does the queue continue by itself?), uninstall an app you can install again, delete a save
    and put it back. Run the speed test with `"ftpWindow": 1` and then `4` in
    config.json and say which went fastest.
14. Phase 9:
    - Uninstall an app with Reload XMB installed: does the icon disappear by itself?
    - Record half a minute of a game (Record in the Status tab) and import the video under
      Maintenance → Videos & Photos. Turn on In-Game Screenshots, take a picture with the PS button →
      Save Screenshot, and see whether it comes along too. Say where on the PS3 it ended up.
    - Open a PS2 game in the Games tab: is the warning about HEN right?
    - If you have a PAL PS1 game with LibCrypt (e.g. Ape Escape): does the game page show it?
    - `ps3 verify` on a folder from `ps3 rip`, and if you have a decrypted ISO on the Mac.
    - Send a theme (.p3t) and see whether the XMB installs it.
    - `ps3 beep`, `ps3 music on` during a game with music in the XMB, and
      `ps3 maintain block-updates` followed by a restart: does Settings → System Update
      say that no update is available?
15. Apps:
    - Press Ignore on an update. Is it moved to Ignored, does it disappear from the
      number badge, and do `ps3 apps` and `ps3 apps ignore` say the same thing? Then stop ignoring it.
    - Update All: do the sizes in the review match the packages on GitHub, and is HEN shown under
      Skipped? Uncheck an app and install the rest. Does the report arrive when the queue is done, with
      the unchecked one under Skipped? Feel free to try while a game is running, so that the queue has to wait.
16. MCP and the ps3.world ideas:
    - `claude mcp add ps3 -- ~/.local/bin/ps3 mcp`, and ask Claude about the PS3's status, whether there are
      updates and what an error code means. Turn off HEN (restart the PS3): does Claude say that HEN
      is not enabled?
    - Install or update an app: does the progress say "matches GitHub's checksum"
      (`ps3 apps install …`)?
    - Browse: does the New row match the apps that got a release in the last month?
17. Phase 10, with a USB stick formatted as "MS-DOS (FAT)":
    - `ps3 iso split "Blur (Europe) (En,Fr,De,Es,It).iso" /Volumes/<the stick>/PS3ISO` (or put the folder
      with Blur in Game Folders and choose Copy to USB Drive… in the Games tab). Put the stick in the PS3:
      does Blur show up in webMAN's game list, and does it start?
    - If you have a game as a folder (GAMES, e.g. from `ps3 rip`): `ps3 iso make <the folder>` and start
      the ISO from PS3ISO. Run `ps3 verify` on the ISO if the game is in the IRD database.
18. PS2 Classics (phase 10):
    - Install PS2 Classics Launcher under Apps → Browse if it is missing.
    - A PS2 game of your own under Mac: right-click → Convert to PS2 Classic…, Download Keys, Convert,
      Send to PS3. Does the game show up in webMAN's list under PS2, and does it start? If not: what
      is on the TV (an error code, or a black screen)?
    - Preferably both a DVD game (.iso) and a CD game (.cue/.bin).
20. Phase 11, new users (19 is the connection sheet's test, on its own branch):
    - The first launch: quit PS3 Center, run `defaults delete local.ps3center.app onboardingVersion`
      and remove `"host"` from `~/.config/ps3center/config.json` (note the address first). Open the app:
      does the setup guide come? On Find Your PS3, is the console found by itself, with firmware, HEN
      and webMAN? Then type the address by hand (Connect): does it connect and save it?
    - With HEN off (right after a restart): does Find Your PS3 say so, and connect once HEN is on?
    - Take the Tour: does each step point at the right place, and switch tab?
    - ⌘? and the ? at the top right: does Help open, and do the links between guides work? The ⓘ on
      a status card, and its "What is …?" link.
    - Settings: hide Maintenance, move Health last, choose °F and Larger text. Do the tabs, the cards,
      the temperatures (cards, menu bar, the fan target) and all text follow at once?
    - Settings → Folders → Create…: does the PS3 folder appear, and does installing an app work after?
    - `ps3 guide`, `ps3 guide send`, `ps3 guide glossary` in Terminal.

## Decisions (Oct 24, 2026)

1. **Game updates (patches): yes**, as long as nothing can update the console or lead to a
   ban. The patches are fetched from Sony's open server
   (`a0.ww.np.dl.playstation.net/tpl/np/<ID>/<ID>-ver.xml`), as RPCS3 does, on the Mac and without
   signing in. They are installed as regular packages in `/dev_hdd0/game/<ID>`, which doesn't touch
   the system software. Never firmware (`PS3UPDAT.PUP`), the console never goes out to PSN for that, and
   a patch that requires newer system software than the console's (`ps3_system_ver` in the XML) is blocked
   as in the compatibility check. Comes in phase 2 as "Updates" in the Games tab.
2. **ps3netsrv:** our own implementation in Swift (phase 6): read-only, the connected folders as the root
   and icons on the fly.
3. **The order** stands: the library, covers, the Mac folders and then the transfers.
