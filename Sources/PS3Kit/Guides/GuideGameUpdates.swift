// "Game Updates from Sony" in Help (⌘?) and `ps3 guide game-updates`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let gameUpdates = Guide(
        id: .gameUpdates,
        title: "Game Updates from Sony",
        summary: "Find and install official patches for your PS3 games, safely and without PSN.",
        symbol: "arrow.down.circle",
        markdown: #"""
Many PS3 games got patches after release that fix bugs or add features. PS3 Center can ask Sony's official update server which patches exist for the games on your PS3, and install them for you, the same way the RPCS3 emulator gets them.

## Check for updates

1. Open **Games** and stay on **On PS3**.
2. Press **Check for Updates** at the top right. PS3 Center asks Sony about each PS3 and PSN game with an official title ID.
3. The button then shows **Updates** with a count, or **No Updates**. A game with a newer patch gets an *Update 01.05* label on its tile.

Press the button again later to ask Sony again.

## Install a patch

1. Click a game with an update to open its page.
2. A blue banner shows the change, for example *Update 01.00 → 01.05*, how many packages it takes and their size.
3. Press **Install** in the banner.

PS3 Center downloads the packages to the Mac and checks each one against the SHA-1 checksum in Sony's list. Then it installs them one after another, oldest first. A package that doesn't match the checksum is never installed. If a game is running, the install waits until you quit it.

Afterwards, the Version card on the game's page shows the installed update.

## Why this is safe

- **Only game patches, never system software.** PS3 Center never downloads or installs firmware, so it can't update your PS3's system software.
- **The PS3 never talks to Sony.** The Mac downloads the patches and sends them to the PS3 like any other package. There is no PSN sign-in.
- **Patches that need newer system software are blocked.** Each patch lists the lowest system software it needs. If that is newer than your PS3's, PS3 Center refuses before it downloads anything. It also refuses if your PS3's firmware can't be read.
- **Installed as a normal package,** in the game's own folder, `/dev_hdd0/game/<title ID>`.

## If something goes wrong

- **No updates for a game you know has some:** only PS3 and PSN games with an official title ID can be checked. A disc image webMAN hasn't read yet may have no title ID; open the game's page to see.
- **"requires system software …":** that patch needs newer firmware than your PS3 has, so it won't be installed.
- **"does not match Sony's checksum":** the download was damaged, and nothing was installed. Try again.

## In Terminal

```bash
ps3 games updates                    # patches for the games on the PS3
ps3 games update "Gran Turismo 5"    # download, check and install
ps3 games update --all --dry-run     # see what would be installed
```
"""#
    )
}
