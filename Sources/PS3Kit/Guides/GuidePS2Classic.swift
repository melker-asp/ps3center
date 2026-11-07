// "Make a PS2 Classic" in Help (⌘?) and `ps3 guide ps2-classic`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let ps2Classic = Guide(
        id: .ps2Classic,
        title: "Make a PS2 Classic",
        summary: "Turn your own PS2 game into a PS2 Classic, the only way PS2 games start on HEN.",
        symbol: "opticaldisc",
        markdown: #"""
On HEN, webMAN can't start a regular PS2 ISO. What does start is a *PS2 Classic*: the game encrypted into a single `.BIN.ENC` file, which the PS2 Classics Launcher starts. PS3 Center can make one from your own PS2 game on the Mac, much like the PC tool PS2 Classic GUI.

## What you need

- **PS2 Classics Launcher** on the PS3. Install it from **Apps** → **Browse**, under *webMAN Add-ons*. PS3HEN makes the license it needs by itself.
- **Your PS2 game on the Mac,** as an `.iso`, or a CD game as `.cue` and `.bin`, in a Game Folder for PS2 games (see [Send Your First Game](ps3center://guide/send-games)).
- **The keys.** PS2 Classics are encrypted with Sony's keys. PS3 Center doesn't ship them; it gets them when you ask.

## Get the keys

The first time, the *Convert to PS2 Classic* sheet asks for the keys:

- **Download Keys** reads them from webMAN MOD's public repository on GitHub, checks each one against a fingerprint built into PS3 Center, and saves them only on this Mac, in `~/.config/ps3center`.
- **Import…** reads them from files you already have: `ps2classic.c`, the placeholder's `.rifkey`, or the `.7z` archives, for example from PS2 Classic GUI.

When the keys are in place, the sheet says *The keys are on this Mac and check out.* **Delete** removes them again.

## Convert the game

1. Open **Games** and choose **On Mac**.
2. Right-click the PS2 game and choose **Convert to PS2 Classic…**.
3. The sheet shows the game, the file it becomes (with the game's title ID in the name) and its size. Under *On the PS3* it says whether PS2 Classics Launcher is installed.
4. Press **Convert** with the game's name after it. PS3 Center encrypts a copy into a `.BIN.ENC` next to the game. The original isn't changed.
5. When it is done, press **Send to PS3**. The file joins the queue and goes to `PS2ISO` on the PS3.

The `.BIN.ENC` also shows up under **On Mac**, so you can send it later like any game.

## Play it

Start the game from webMAN's game list, among the PS2 games. webMAN hands it to the PS2 Classics Launcher.

The Super Slim runs PS2 games in software. Most work. If a game stutters, **PS2 CONFIG Database** (also in Apps → Browse) may have a fix, which webMAN uses by itself. The title ID in the file name is how webMAN finds that fix.

## If something goes wrong

- **Convert is grayed out:** the keys are missing, or a `.BIN.ENC` of the game is already next to it.
- **Download Keys fails:** check the internet connection and try again, or use **Import…**. The message says which key didn't check out.
- **The game doesn't start:** check that PS2 Classics Launcher is installed. Note any error code on the TV; [Troubleshooting](ps3center://guide/troubleshooting) shows how to look it up.

## In Terminal

```bash
ps3 ps2 keys                          # are the keys on the Mac?
ps3 ps2 keys --fetch                  # download them from webMAN MOD's repo
ps3 ps2 keys --import ~/Downloads/ps2classic.c
ps3 ps2 classic "Game (Europe).iso"   # writes a .BIN.ENC next to the game
ps3 send ~/Games/PS2/Game.BIN.ENC     # goes to PS2ISO on the PS3
```
"""#
    )
}
