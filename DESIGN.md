# PS3 Center – design and architecture

Inspiration: [Mole](https://github.com/tw93/mole). Mole is an open CLI (`mo`) that does the work,
plus a separate Mac app that shows the same features as tabs. PS3 Center follows the same idea,
but with **one** shared engine instead of two codebases.

```
PS3Kit (Swift library)     ← all logic: webMAN, FTP, ISO/SFO/PKG, updates
 ├── ps3   (CLI)           ← `ps3` with no arguments is a menu in the terminal
 └── PS3 Center.app        ← SwiftUI, links PS3Kit directly
```

The CLI also writes JSON (`--json`, and automatically when output is piped), and
`ps3 status --watch --json` streams NDJSON. That lets widgets, Raycast or Claude
read the same data without the app. `ps3 mcp` gives Claude the same data as MCP tools (read-only in
the first version; tools that change the console would get the same dry run and log as the CLI).

## Principles from Mole

| Mole | PS3 Center |
|---|---|
| `mo status` is read-only | `ps3 status` only reads |
| `--dry-run` before anything that changes something | `send`, `apps update` and `apps install` have `--dry-run` |
| Asks before changes, `--yes` skips the question | `apps update` asks per app, `-y` answers yes; the app's Update All shows a review first |
| Protected paths are never touched | HEN and plugins are never installed automatically, only advice |
| `~/Library/Logs/mole/operations.log` + `mo history` | `~/Library/Logs/ps3center/operations.log` + `ps3 history` |
| `~/.config/mole/` | `~/.config/ps3center/config.json` (shared with the app) |
| JSON automatically when output is piped | The same for `status`, `apps` and `history` |
| ➤ headings, ✓ ◎ → markers, health score 0–100 | The same style |

A rule of our own: **the compatibility check**. Each app in the catalog can have requirements (`Requirements`: HEN
or CFW, CEX or DEX, lowest and highest firmware). Before anything is installed, the console's
firmware is read and apps that won't work are blocked, in the app, in `apps install` and `apps update`,
and for custom .pkg files whose title ID is in the catalog. If the firmware can't be read, apps
that have requirements are blocked; apps without requirements are never affected. "Untested" (e.g. PS3 Health on CFW)
warns but does not block. Requirements are entered from the app's README or release notes.

A rule of our own: **"warn and wait"**. Anything that affects the console (install, refresh the game list)
waits until no game is running. Uploads start right away. `--force` runs anyway.

## Commands ↔ tabs in the app

| Tab | CLI | Contents |
|---|---|---|
| **Status** | `ps3 status`, `ps3 discover`, `ps3 connection` | Cards: Health, CPU, RSX, Fan, Free, Network, Now Playing, versions (FW/HEN/webMAN). The Network card's search button (and Find PS3… on the connection screen) opens Connection: every PS3 on the Mac's networks with Use, an address typed by hand, the Mac's connections with the cable's link speed, and what to enter on the PS3 for a cable |
| **Games** | `ps3 games`, `ps3 send`, `ps3 serve`, `ps3 usb`, `ps3 iso` | Library Mac ↔ PS3, drag and drop to send, mount/play, delete |
| **Apps** | `ps3 apps`, `apps available`, `apps info`, `apps update`, `apps install` | Like Mole's Apps → Updates: "02.40 → 02.41", Update / Ignore / Update All. Ignore skips just that version (`apps ignore`); a newer one shows up again. Update All first shows a review and afterwards a report. The Browse tab shows `apps available`, grouped as System, Programs and webMAN add-ons, with New (released in the last 30 days) on top. From Mac (`apps mac`) shows the .pkg files in the package folders, per folder, like the Mac's games in the Games tab; they are installed where they are, with the same compatibility check when the title ID is in the catalog. Clicking a row opens the detail page (`apps info`): version, compatibility with the console and the README with images |
| **Maintenance** | `ps3 saves`, `ps3 backup`, `ps3 maintain`, `ps3 analyze`, `ps3 rip` | Saves and system files to the Mac, Cleanup like Mole's Optimize (a report with Done and what remains, with the reason), Storage like Mole's Analyze (one bar over /dev_hdd0) and Disc |
| **Menu bar** | `ps3 status --watch` | Compact status + quick buttons (Send Files…, Refresh Game List, Quit Game, Shut Down), Launch at Login, Settings… |
| **Settings** (the gear, ⌘,) | `ps3 config` | General, Console, Appearance, Status, Folders, Transfers, Notifications and Help in one sheet (below) |
| **Help** (?, ⌘?) | `ps3 guide` | Eleven how-to guides and a glossary, the same texts in the app and the terminal |

## Appearance (Mole's structure, the PS app's colors)

From Mole: the layout. From the PlayStation app: colors, buttons and feel. All values are in
`Theme.swift`.

- **Base:** blue-black like the PS app's dark mode, with the home screen's slanted light planes
  (`FacetBackground`). Each tab is tinted with one of the PS app's themes: Status Starlight Blue,
  Games Nova Pink, Apps Galactic Purple, and later Maintenance Cosmic Red.
- **Colors:** PlayStation blue for what you can act on (icons, links, progress), the PS app's
  green for presence, badges and "good", yellow and red for warnings.
- **Tabs** as pills centered at the top, like the PS app's segmented control: dark capsule, lighter
  selected capsule, green number badges. The logo on a PS-blue disc with a green dot when the console responds.
- **Buttons:** white with black text for the main action ("Install", like "Buy Now"), outline for
  secondary ones, round outline buttons for icons. **At most one white button per screen**: actions
  repeated per row or card (Update, Install) are outlined, and a button inside a colored banner is
  tinted (`PillButtonStyle(tint:)`, white text). Delete, Uninstall and other removals use
  `PillButtonStyle(destructive: true)` (red outline, red text), stand apart from the other buttons
  (to the right) and end in "…" because a question follows.
- **Sheets** close with Done at the bottom right (`DoneButton`, Esc), where review sheets have Cancel
  and their main button. The remote uses ⌘W instead, since Esc there is the PS3's Back.
- **Text:** every size comes from `Theme.TextSize` (`.font(.ui(.body))`). `tertiaryText` is 50 %
  white (5.1:1 on a card; WCAG AA asks for 4.5:1), and red text on the dark base is `hotText`.
  Dates and numbers are always English (`Format`, `Format.locale`), never the system language.
  Time still to go is written in words (`Format.estimate`: "51 min", "1 h 48 min"), never as a clock
  like "51:17" beside "4–17 min"; a running clock or elapsed time may use `Format.duration`. Labels
  that sit side by side must not share a word with different meanings ("On PS3 | On Mac" beside the
  platform pill "PS3").
  Clickable targets are at least 28 pt, and a switch (`PillToggle`) has a VoiceOver label and value.
- **Labels** like the PS app's "PS5": bold text on a small black plate.
- **Typeface:** large numbers, page headings and app names in a thin weight (the PS app's SST isn't
  available on the Mac, so it's SF Pro).
- **Cards:** small uppercase heading with an icon, a chip in the corner (e.g. "Wi-Fi", "Normal"), a large number with
  a unit, a sparkline or bar and a gray footnote. A card never repeats what another card or a banner
  already says, and the footnote says something useful (a peak, what a bar shows), not trivia.
  Chips are in sentence case ("6 parts", "New").
- **Loading and progress:** a thin ring (`Spinner`) and the PS app's storage bar (`PSProgressBar`),
  not `ProgressView`, which can't be rendered to screenshots.
- **Splash screen:** the connection screen is the PS app's blue splash screen with a white logo (`SplashBackground`).
- **Images:** Now Playing shows the game's ICON0/PIC1 from `/dev_bdvd/PS3_GAME` (`GameArt`), and
  the detail page has a banner like the PS Store with the app's PIC1.PNG or the README's first image.
  Browse is a grid of cards like the PS app's library.
- **Settings** (the gear at the top right, ⌘, and Settings… in the menu bar): one sheet with the
  sections on the left like the PS app's Settings, a short line on what each section is for, and
  groups of rows on cards (`SettingsGroup`, `SettingsRow`; a row of pills goes below its title,
  `SettingsStackedRow`). One choice out of a few is a `PillPicker`, on/off is a `PillToggle`; both are
  drawn by SwiftUI so snapshots render them. The sheet's white button is Done; everything else in it
  is outlined. It works while the console is offline, since a new user needs it before there is one.
  - General: the tab the app opens in (or the last one), Launch at Login, which tabs show (Status
    always), Show in Menu Bar and which of its quick buttons show.
  - Console: the PS3's address and whether it answers, and Find PS3… (the connection sheet).
  - Appearance: the text size (Default, Large, Larger: one factor in `Font.ui`, so every text grows
    and the layout stays), temperatures in °C or °F (only the display: the fan target is still moved
    in °C within 60–75, and the CLI and `ps3 mcp` keep Celsius), and the PS app's themes. "Match Tab"
    (default) gives each tab its own color; Starlight Blue, Nova Pink, Cosmic Red, Galactic Purple
    and Midnight Black color all tabs the same.
  - Status: which cards show and in what order. A row of cards is as tall as its tallest card, so a
    reordered grid still lines up.
  - Help: Open Help, Show Setup Again, Take the Tour, Show Tips and Show Them Again.
  - Folders: the PS3 folder (Create… makes an empty one for someone without a copy of the console's
    drive, Choose… offers one inside a folder that isn't one), Game Folders and Package Folders.
  - Transfers: when the queue finishes, Verify with MD5, the weekly save backup, and under Advanced
    the FTP piece size and pieces in flight with Reset to Default.
  - Notifications: whether macOS allows them (asks once; after a no, a button opens System
    Settings) and one switch per kind (`NotificationKind`).
  - A switch that also sits where it is used (Launch at Login in the menu bar, Verify with MD5 in
    Transfers, the weekly backup in Maintenance) reads and writes the same value, so nothing moved away
    from where people already found it.
  - **Where a setting is saved:** what the CLI also reads (host, root, folders, FTP tuning, theme) is
    in `config.json`, so `ps3 config` and the app agree. What only changes how the app looks or behaves
    (the start tab, the menu bar icon, notifications, the weekly backup, the Games view) is in
    UserDefaults. A value equal to the default is saved as nothing, so config.json only holds what
    someone changed.
- **For new users** (phase 11):
  - **The setup guide** covers the window on a launch with no console saved: Welcome (what is
    needed), Get the PS3 Ready, Find Your PS3 (the search live, or a typed address), Your Folders,
    Make It Yours and You're All Set. It is on the blue splash, with Skip Setup on every page and one
    white button (Continue, or Take the Tour at the end).
  - **Help** is a sheet like Settings: the guides on the left with a search field and the glossary
    last, the text drawn by `ReadmeView`, and Next at the bottom of each guide.
  - **How?** links (`HelpLink`) sit under empty views and on the connection screen, and lead to the
    guide that explains. They are blue on the base and white on the splash.
  - **ⓘ** (`InfoButton`) after a card's title shows two or three sentences in a popover, with
    "What is …?" (the glossary) or "Read …" (a guide). The numbers in them come from the code
    (`Thermal`, `FanControl`), never typed twice.
  - **The tour** dims the window around one part at a time, with a bubble beside it: "2 of 6", a
    title, two sentences, Skip Tour, Back and Next. It switches tab itself.
  - **Tips** (`TipCard`) are a tinted strip at the top of a tab with Got It, one at a time per place.
- **Tooltips** (`.help`, `iconLabel`): every icon-only button has one (a test reads the sources), and
  every button that changes the console says what happens and what follows from it ("Restarts the
  PS3 after a question. On HEN, enable HEN again afterwards."), not its own label again. One or two
  short sentences, in English, no period after a single one. A tooltip never decides anything in code.
- A hero image that mirrors health. Mole uses a planet; here it could be the console or a
  disc that glows in the health color.
- **Review view before changes:** groups with checkboxes and size, and a white main button that
  says exactly what happens ("Install 2 Updates"; the Updates list's button says "Update 2…" when HEN
  or a plugin only gets advice, not "Update All"). Shown when games are sent
  (`SendReviewView`) and for Update All (`UpdateReviewView`), which also shows what is skipped
  and why, a game that makes the queue wait and what a package requires afterwards.
- **Detail report afterwards:** Done / Failed / Skipped, with the reason right-aligned in gray.
  After Update All it sits at the top of Updates until it is dismissed (`UpdateReportCard`).

## Facts about the console that the code builds on

- **Network settings** are in `/dev_flash2/etc/xRegistry.sys` with every other system setting, and
  webMAN has no command for them. Changing them over the network would also cut the connection that
  makes the change, with only the console's own menu to fix a wrong value. So the connection sheet and
  `ps3 connection` show the values to type (`WiredSetup`), and the Mac side is left to System Settings.
- **A cable, measured Nov 7, 2026** (`ps3 speedtest`): Wi-Fi 1.1 MB/s up and down; a USB adapter
  straight to the PS3 5.5 MB/s up, with the link at only 100 Mbit (the adapter manages 5 Gbit, the
  Super Slim gigabit), so an old cable. macOS gives the link speed in `ifi_baudrate` without admin rights.
- **webMAN hangs on reused HTTP connections.** Every request sends `Connection: close`
  and runs one at a time. Parallel requests take 4+ seconds each while a game is running.
- **A running game** is read via PS3MAPI `PROCESS GETCURRENTPID` + `GETNAME` (`…_EBOOT.BIN` = game,
  `vsh.self` = XMB). `GETALLPID` sends broken JSON.
- **FTP:** `SIZE` works. Interrupted uploads continue with `APPE`. When the PS3 closes a
  data connection it shows up as ENODATA instead of end of file.
- **FTP according to webMAN's source code** (`include/ftp.h`, read Oct 24, 2026, not tried on the console yet):
  if the data connection breaks with an error, or no data arrives within 60 seconds (or the timeout
  that is configured), the upload counts as failed and the file is deleted. Only a clean close
  (FIN, as with ctrl-C) leaves the half-finished file so that `APPE` can continue. At most two
  transfers at a time (`MAX_FTP_TRANSFERS`). `REST`, `RNFR`/`RNTO`, `MDTM`, `MFMT` and
  `SITE SHUTDOWN` exist.
- **Auto power off:** during an FTP session, `/install.ps3` and `/download.ps3`, webMAN
  temporarily turns off the console's "Auto Power Off" and turns it back on afterwards
  (`include/init/autopoweroff.h`).
- **`/md5.ps3/<path>`** shows a file's MD5 on the console. **`/play.ps3/<path>`** mounts and
  starts, **`/play.ps3?<title ID>`** starts an installed game from its icon, **`/xmb.ps3$exit`**
  quits the game, **`/shutdown.ps3`** shuts down (webMAN's wiki). RMD deletes folders recursively in
  the build with the file manager (`COPY_PS3`).
- **Covers:** PS3 and PSN from `aldostools/Resources/COV/<ID>.JPG` (webMAN's online covers, 260×300)
  and GameTDB `art.gametdb.com/ps3/coverM/<EN|US|JA>/<ID>.jpg` (350×408). PS2 and PS1 from
  `xlenore/ps2-covers` and `psx-covers` (`covers/default/<SLES-12345>.jpg`), as their README
  suggests for PCSX2's cover downloader. No sources for PSP. All responded Oct 24, 2026.
- **Game updates:** the list per game is `https://a0.ww.np.dl.playstation.net/tpl/np/<ID>/<ID>-ver.xml`
  (`<package version size sha1sum url ps3_system_ver>`), the packages are on `http://b0.ww.np…` and
  the server answers 403 over HTTP for the list. The servers have certificates from Sony's own CA ("SCEI"), which
  macOS doesn't trust, so `SonyTrust` accepts a chain from Sony's CA for just those hosts and saves
  its fingerprint the first time. Each package is checked against the SHA-1 in the list. Not tried from
  a Mac yet; the server couldn't be reached from the cloud session.
- **Transfers (PS3 Center):** files are uploaded to `<name>.part` and renamed with `RNFR`/`RNTO`
  when the size matches, so webMAN never lists half a game. A file with the real name that is
  smaller (from before `.part`) continues with `APPE` as before. Pause and sleep close the
  data connection with FIN (`NWConnection.cancel()`), which webMAN treats as a clean end and
  keeps the file. The FTP session is closed before anything with a long wait (a running game, MD5), because
  webMAN drops a session that is silent for a minute.
- **The game list and the cache:** webMAN writes the XMB's game list to
  `/dev_hdd0/xmlhost/game_plugin/mygames.xml` and saves title and icon for ISOs as
  `<name>.SFO`/`<name>.PNG` in `/dev_hdd0/tmp/wmtmp` (`include/scan/`, confirmed by test 1 in
  PLAN.md). For network games it fetches the `<name>.SFO` next to the ISO from the ps3netsrv server.
- **Recently Added** is based on the date in the FTP listing, which in the console's responses lacks a year
  ("Jun 05 18:33"). It is interpreted as the latest such date that isn't in the future, so a
  game that is more than a year old can end up wrong. On the Mac, Finder's "Date Added" is used, because a
  copied file keeps the original's modification date.
- **What `send` knows (Nov 6):** after the upload, the target folder is listed once, and title, title ID and
  version from the image on the Mac are saved under the same key (path, size and the listing's date)
  that the next read of the console uses. ICON0 is saved per path on the console and shown until
  webMAN has made its own copy in wmtmp. "Rescan Games" keeps it for games without PARAM.SFO
  on the console (PS1, PS2, PSP), since there is nothing to rescan there.
- **ps3netsrv** (aldostools/ps3netsrv, `include/netiso.h` and `src/main.cpp`, read Oct 24, 2026):
  16-byte big-endian commands from `OPEN_FILE` = 0x1224 to `READ_DIR` = 0x1232, replies with a
  fixed size. `READ_DIR` gives a count and then 529-byte entries (size, time, folder, 512-byte name).
  `//` in the path means the files in subfolders are to be included, as "folder/file". CD images
  of 2–848 MB get their sector size guessed from where the volume descriptor is. The READ_ONLY
  build closes the connection on write commands, and so does PS3 Center's `NetServer`.
  webMAN reaches the server as `/net0` … `/net4` (network server 1–5 in `/setup.ps3`).
- **The controller** (`/pad.ps3?<button>`, `include/feat/vpad.h`, read Oct 24, 2026): the buttons
  are up, down, left, right, cross, circle, square, triangle, l1–l3, r1–r3, start, select, psbtn,
  and accept/cancel press the console's own OK and Back. `/pad.ps3?off` disconnects the
  virtual controller. **An "=" after cross or circle switches the console's OK button and restarts
  it**, so PS3 Center only sends the fixed names in `PadButton`, never free text.
- **The fan** (`include/cpursx.h`): `/cpursx.ps3?max=<°C>` moves the target in dynamic mode
  (webMAN spins the fan up to keep the console below the target). `?fan=`, `?man` and `?sys` switch
  mode or set a fixed speed; PS3 Center doesn't use those. GETSYSINFO shows `MAX: 68°C` only
  in dynamic mode, and only then can the target be changed, within 60–75 °C.
- **The disc and the screen:** `/eject.ps3` and `/insert.ps3` eject and insert the disc.
  `/xmb.ps3$screenshot?show?fast` shows the XMB as an image (not during a game); PS3 Center takes both an
  image and a page with `<img>` (test 8 in PLAN.md decides which).
- **HEN off:** webMAN only starts when HEN is enabled. If the address answers ping, or refuses a
  TCP connection to port 80 (only a powered-on machine answers with RST), but webMAN doesn't, the app
  and `ps3 status` say that HEN needs to be enabled.
- **Saves:** one folder per save in `/dev_hdd0/home/<user>/savedata/` (the user is eight
  digits, 00000001). PARAM.SFO in it has TITLE and SUB_TITLE, but also account details
  (ACCOUNT_ID, PARAMS); PS3 Center only reads the first two. A save is only put back for the
  same user.
- **`/stat.ps3<path>`** (`include/cmd/stat_chmod.h`) counts a folder's size on the console and
  answers `Size: 12.3 GB (13,207,024,640 bytes)<br>Dir(s): …<br>File(s): …`. With `&id=` it links
  files instead, so that is never used.
- **`/copy.ps3/<path>&to=<target>`** copies on the console, `/copy.ps3$abort` stops. Whether the reply
  comes only when the copy is done is not known, so PS3 Center sends it on its own connection
  and follows the target folder over FTP (test 12 in PLAN.md).
- **HEN's settings** are empty files in `/dev_hdd0/hen/toggles/` (`hotkey_polling.off`,
  `remap_files.off` in `payload/main.c`). `ps3 maintain` only shows them.
- **webMAN's settings** (`/setup.ps3`, `include/setup.h`): when the form is submitted, *all*
  settings are reset and then read from the request, so a field that is missing is turned off. Some fields
  (icon type, information tags, USB wait times) also get their value from JavaScript in the
  page (`wm_res/setup/setup*.dat`). PS3 Center therefore loads the page in a hidden `WKWebView`, changes
  only the network server and sends `new URLSearchParams(new FormData(form))`, that is, exactly what
  Safari would send. First a copy of the settings is saved (System Files), and afterwards the page
  is read again and compared field by field. The network servers are called `nd<n>`, `neth<n>` and `netp<n>`
  (n = 0–4, `/net0`–`/net4`).
- **Uploads (Oct 25):** the file is sent in 1 MB chunks, and the next chunk is handed to the
  network before the previous one has been sent (two in flight), in the same order. If the connection breaks
  the queue retries with a pause in between and continues from the `.part` file's size. If webMAN has removed
  the file (the connection broke with an error) it starts over and says so.
- **Uninstall:** an installed game or app is a folder in `/dev_hdd0/game/<title ID>`
  that is deleted over FTP (RMD is recursive in webMAN). Saves and trophies are not touched. The XMB shows
  the icon until it is reloaded (see Reload XMB below).
- **`/cpursx.ps3` shows PSID/IDPS.** They are never saved or shown.
- **Package installation:** `/install.ps3/<path>` installs, but does *not* delete the .pkg file
  as the wiki claims (tried Oct 24, 2026). The tool knows the installation is done when
  `PARAM.SFO` in `/dev_hdd0/game/<title ID>/` has a new `MDTM` timestamp and the folder then
  hasn't changed over two checks in a row. After that the tool deletes its copy of the package.
  Reinstalling Apollo took 11 seconds. The reply to `/install.ps3` can take until the XMB is
  done, so it is sent on its own connection and the status continues meanwhile. Each check
  opens its own FTP session (webMAN drops one that is silent for a minute). If nothing changes in the
  folder for 75 seconds, `/install.ps3` is sent once more, and then the tool gives up with advice
  to install from the XMB (an interruption made the app wait for an installation that never
  started, Oct 25, 2026).
- **The app tolerates a few missed status calls:** webMAN is slow at times, so the console is counted as gone
  only after three calls in a row without a reply. Meanwhile the dot by the PS logo is yellow. While a long
  command is running (an installation, `/stat.ps3` counting a large folder, copying a disc) it is not
  counted as gone at all; that command's own timeout decides (counting storage lost
  contact, Oct 25, 2026).
- **`/refresh.ps3` and `/popup.ps3`** answer OK right away, even with åäö in the text (tried Oct 24, 2026).
- **Brewology** is behind a Cloudflare protection against automated requests and is not circumvented.
  Apps that are only found there get a link.
- **The firmware line** in PS3MAPI `PS3 GETSYSINFO` comes from webMAN's `get_cobra_version`
  (`include/cpursx.h`): `Firmware : 4.93 CEX PS3HEN 3.5.0` on HEN and `4.92 CEX Cobra 8.4`,
  `4.92 DEX Mamba 8.4` or `qCFW` on CFW. The type is `CEX`, `DEX` or `DECR`; on Evilnat's
  PEX/D-PEX the first letter is replaced with P, so `PEX` can be either. If `PS3HEN` is missing it is CFW,
  since webMAN only runs on HEN or CFW.
- **README** is fetched with GitHub's `/repos/<repo>/readme` (base64). Relative images are repointed
  to `raw.githubusercontent.com`, badges (SVG, shields.io) are removed and the HTML that many
  PS3 repos are written in (`<p align="center"><img …>`, `<h1>`, `<br>`) is converted to Markdown.
  IRISMAN's README is Latin-1.
- **PS3HEN** has no GitHub releases. The latest version is read from `HEN_REV` in
  `payload/main.c` (0x0360 → 3.6.0).

### Phase 9: from webMAN's, PS3HEN's and aldostools' sources (Oct 25, 2026)

- **PS2 on HEN:** webMAN doesn't mount regular PS2 ISOs on HEN ("HEN does not support PS2 ISO",
  `include/mount/mount_cobra.h`). Only PS2 Classics (encrypted `.BIN.ENC`) start, through the PS2
  Classics Launcher. Fixes are read from `/dev_hdd0/game/PS2CONFIG/USRDIR`: for a PS2 Classic
  `CONFIG/ENC/<SLES_123.45>.ENC`, for an ISO on CFW `<ID>.CONFIG` in `CUSTOM`, `NET`, `GX` or
  `SOFT` (`include/mount/ps2_classic.h`).
- **LibCrypt (PAL PS1):** PS3HEN reads the protection data in `payload/storage_ext.c`: first
  `<track name>.lsd`/`.sbi` next to the data file (`.bin` is replaced with `.lsd`), then
  `/dev_hdd0/tmp/lsd/<EXE>.lsd` and `/dev_hdd0/tmp/sbi/<EXE>.sbi`, where EXE is the boot file in
  SYSTEM.CNF (`SCES_014.31`). webMAN MOD's installer puts 225 LSD files in `/dev_hdd0/tmp/lsd`
  (`_Projects_/updater/pkgfiles/USRDIR/lsd`); an entry is 15 bytes.
- **Reload XMB:** `/refresh.ps3?xmb` rereads the game list and reloads the XMB, only when the XMB
  is showing. With a user and Reload XMB (`/dev_hdd0/game/RELOADXMB`, which webMAN's installer
  also puts there) webMAN starts that app, otherwise it logs out and in with virtual
  button presses (`reload_xmb`, `include/init/vsh.h`). PS3 Center only reloads by itself after an
  uninstall when the first applies.
- **Recording:** `/videorec.ps3` starts or stops recording, only during a game, as 720p
  MP4 in `/dev_hdd0/VIDEO/<title ID>_<date>.mp4`. The reply says `Video recording: Enabled` or
  `Disabled` (`include/feat/video_rec.h`).
- **In-game screenshots:** `/xmb.ps3$ingame_screenshot` turns on the XMB's Save Screenshot in all games,
  until the next restart. Photos are under `/dev_hdd0/photo`.
- **In-game music:** `/sysbgm.ps3?1` and `?0` set the background music. webMAN can't read the
  state: `?` and `?status` change it (`include/cmd/sysbgm.h`), so they aren't used.
- **Beep:** `/beep.ps3?1`–`3` are the buzzer's beeps (`play_sound_id`, `include/notify/vsh_notify.h`).
- **Themes:** `/install.ps3/<path>.p3t` calls the XMB's theme installer
  (`include/feat/pkg_handler.h`). PS3 Center uploads the theme to `/dev_hdd0/packages`.
- **System updates:** if `/dev_hdd0/ps3-updatelist.txt` exists, webMAN points the XMB's
  update check at it on every start (`include/www/www_start.h`). webMAN MOD's own file
  sends every region's update to 127.0.0.1. Nothing in dev_flash is changed.
- **Not used:** `/fixclock.ps3` writes the console's secure clock (`sys_ss_secure_rtc`,
  `include/feat/clock.h`), and the XMB sets the clock over the Internet by itself. The USB "eject"
  (`/xmb.ps3$eject/dev_usb000`) is a faked event to the XMB, not a safe unmount.
  Overclocking, LV1/LV2 memory, IDPS/PSID dumps and network settings are never used.
- **IRD:** the format follows 13xforever's ps3-disc-dumper (`IrdLibraryClient/IrdFormat`):
  little-endian, the whole file often gzip, `header` is the disc's first block (gzip) with the file system,
  and the files' MD5 (on decrypted data) are keyed on the block the file starts in. Names are read from the
  Joliet tree. The IRD files are fetched from FlexBy420's database on GitHub
  (`flexby420.github.io/playstation_3_ird_database/all.json`).
- **ps3.aldostools.org** has a self-signed HTTPS certificate and only works over HTTP, so
  PS3 Center fetches nothing from there. The same data is on GitHub (titleid.txt, covers, LSD files).
  psdevwiki is behind a Cloudflare protection; the error codes (0x8001xxxx) come instead from
  RPCS3's `rpcs3/Emu/Cell/ErrorCodes.h`.
- **Covers:** PSP from `aldostools/Resources/PSP/<UCES00995>.PNG`, and PS1/PS2 from there
  as a fallback (`PSX/<SCES_014.38>_COV.JPG`).

### Phase 10: the ISO tools from the PC (Nov 7, 2026)

- **Split files on USB** (webMAN MOD `include/file/file_copy.h`): when webMAN copies a file over
  0xFFFFFFFF bytes to `/dev_usb`, an `.iso` becomes `.iso.0`, `.iso.1` … and other files `.66600`,
  `.66601` …, in parts of 0xFFFF0000 bytes (4 GB − 64 KB). If a `.66600` is copied from USB to hdd0,
  webMAN joins the parts again. Only ISOs start in parts: `.iso.0` is mounted with the parts
  that follow for PS3 games, PS2 (CFW), Blu-ray and DVD (`include/mount/mount_cobra.h`). A game folder
  with `.666` parts won't start from USB, so PS3 Center turns it into an ISO instead.
- **The PS3 ISO** (Estwald's makeps3iso, bucanero/ps3iso-utils): sector 0 has the number of unencrypted
  regions and their first and last sector (one region, the whole image, when it is decrypted),
  sector 1 "PlayStation3" and the title ID as `BLES-00932`. Primary volume descriptor at 16, Joliet
  (UCS-2, `%/@`) at 17, terminator at 18, path tables from 20, directories from 32, then the files: a folder's
  own files before the subfolders'. A file over 4 GB gets one entry per chunk of 0xFFFFF800 bytes,
  with the flag 0x80 on all but the last (multiple extents). The names in the primary tree are uppercase.
  makeps3iso leaves out the files in `PS3_UPDATE`, and so does PS3 Center: no firmware
  is included.
- **Encrypted images:** Redump images have several regions in sector 0, and the encrypted ones are the gaps
  between them. Even decrypted ones (ps3dec) keep the table; that `EBOOT.BIN` starts with
  `SCE` in a gap shows that the image is decrypted. webMAN MOD's source code has no support for
  disc keys (`.dkey`), so an encrypted image must be decrypted before it can be started on HEN.
- **Tried on the Mac (Nov 7):** an ISO from a test folder is mounted by macOS (`hdiutil`) with both
  Joliet and the primary tree, and the contents are identical to the folder. A file of 4 GB + 4 KB
  got two entries with the right start and the same MD5 as the source (checked with a custom parser,
  because macOS `cd9660` only reads the last chunk of such a file). Split, join and extract
  gave the same files. `bsdtar` takes the region table in sector 0 for LZMA and can't read the ISO.
  Not tried on the console (test 17 in PLAN.md).
- **PS2 Classics on HEN** (built Nov 7, `PS2Classics.swift`; the sources below):
  - webMAN (`include/mount/mount_misc.h`, `ps2_classic.h`) starts `<name>.BIN.ENC` in PS2ISO by
    linking it as `/dev_hdd0/game/PS2U10000/USRDIR/ISO.BIN.ENC` in the PS2 Classics Launcher (which
    must be installed) and copying CONFIG and memory cards there. CONFIG is looked up by itself in
    PS2CONFIG (`CONFIG/ENC/<SLES_123.45>.ENC`, already encrypted), so they don't need to be made here.
  - PS3HEN (`payload/make_rif.c`) makes the license for exactly `2P0001-PS2U10000_00-0000111122223333`
    by itself, with a built-in RAP, and creates `act.dat` if it is missing. No license is needed from
    the user.
  - The encryption (`ps2classic.c`, GPLv3, in webMAN MOD's `_Projects_/tools/ps2classic_*.7z`):
    the image is padded to 16 KB and gets a LIMG block (`"LIMG"`, 1, sectors, 0x800). The data and
    meta key is `klicensee` encrypted with two fixed CEX keys and a fixed IV. Data is encrypted
    with AES-128-CBC in segments of 0x4000, 0x200 segments per block, and before each block comes a
    table with SHA-1 and segment number, encrypted with the meta key. The header (`PS2\0`, NPD type 2,
    content ID, the name `ISO.BIN.ENC`) is signed with AES-CMAC and three NPD keys.
  - What is needed beyond the code is seven 16-byte values: two CEX keys, the IV, three NPD keys
    and the placeholder's `klicensee` (`…3333.rifkey`, derived from the same RAP that PS3HEN has built in;
    checked with SHA-256). The IV is sixteen zeros. `aes128cbc_enc` in ps2classic copies the IV,
    so each segment starts over with it; the key derivation is therefore AES(key, klicensee).
  - The keys are in webMAN MOD's public repo but not in PS3 Center (decision Nov 7): Download Keys downloads
    the two archives, extracts `src/ps2classic.c` and `.rifkey` with macOS `bsdtar` into memory,
    compares against the SHA-256 in the code and saves to `~/.config/ps3center/ps2classic-keys.json` (0600).
  - Tried on the Mac Nov 7: CMAC against RFC 4493, encryption and decryption with made-up keys
    (header, LIMG, tables across the block boundary, raw CD sectors), and Download Keys plus a PS2 Classic made from
    a custom test ISO with the real keys. Whether the game starts is shown by test 18.

## Roadmap

The plan phase by phase, with what is built, what remains and what to try on the console,
is in [PLAN.md](PLAN.md). Some decisions that apply going forward:

- **The catalog:** new apps are vetted against how well established they are; repos that are a few weeks
  old with 1–2 stars are not included automatically.
- **Games:** only your own files via `send`, `ps3 rip` and watched folders. No built-in download
  from ROM or ISO archives.
- **Plugins:** PS3 Center never changes `boot_plugins.txt`, so there will be no `plugin add/remove`.
  Missing plugins are reported by `ps3 maintain`.
- **Screenshots without a PS3:** `PS3CENTER_FIXTURES=1` gives the app data from `Fixtures` in the `PS3KitFixtures` target; CI
  renders every screen and uploads the PNGs as the artifact `screenshots`, and
  `make snapshot-fixtures` does the same on the Mac.
