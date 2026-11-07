// "Play Games from the Mac" in Help (⌘?) and `ps3 guide play-from-mac`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let playFromMac = Guide(
        id: .playFromMac,
        title: "Play Games from the Mac",
        summary: "Let the PS3 play ISOs straight from the Mac's game folders, without copying them.",
        symbol: "server.rack",
        markdown: #"""
The Game Server lets the PS3 play games that stay on your Mac. PS3 Center has a small server built in: a read-only version of ps3netsrv, the tool webMAN uses for games on the network. webMAN reads the game over the network while you play, so nothing is copied to the PS3's hard drive. It is handy for trying a game, for PS1 and PSP games, or for a library too big for the PS3.

## Before you start

- Link your game folders first (see [Send Your First Game](ps3center://guide/send-games)). The server shares exactly those folders.
- Only ISO files work over the network. Game folders (`GAMES`) have to be sent to the PS3.
- A cable is best for PS3 games. Wi-Fi may be too slow for smooth play.
- Give the Mac a fixed address in your router. webMAN remembers the address and won't find the server if it changes.

## Turn on the Game Server

1. Open **Games** and choose **On Mac**.
2. Press **Game Server**. The dot on the button turns green while the server runs.
3. Turn on the switch at the top right of the sheet. The Status card shows the Mac's address with port 38008, whether the PS3 is connected, and what it is reading.

The server only lets in your PS3's address, and it only reads. The PS3 can read your games, but never change anything on the Mac.

## Tell webMAN where the server is

webMAN needs this once. Under WEBMAN in the sheet:

1. Press **Set Up webMAN for Me**. PS3 Center first saves a copy of webMAN's settings (under Maintenance → System Files). Then it fills in a free network server in webMAN with the Mac's address and port 38008, saves, and refreshes the game list. Your other webMAN settings stay as they are.
2. Or press **Do It Myself** to open webMAN's settings in your browser, and set network server 1 to the Mac's address and port 38008.

When it is done, the sheet says which network server webMAN uses, for example `/net0`.

## Start a game

- **On the PS3:** the Mac's games show up among webMAN's games and start as usual.
- **From the Mac:** right-click a game under **On Mac** and choose **Play from Mac**. If another game is running, PS3 Center asks before it quits that game.

## While you play

- The Mac has to stay on. PS3 Center keeps it awake while a game from the Mac is mounted, and lets it sleep again afterwards.
- PS3 Center has to keep running, but you can close its window. With **Show in Menu Bar** on (Settings → General), the menu bar shows that the Game Server is on.
- PS2 ISOs are copied to the hard drive when they start, so the server gains little for them. On HEN, PS2 games only start as PS2 Classics (see [Make a PS2 Classic](ps3center://guide/ps2-classic)).

## If something goes wrong

- **The games don't show up on the PS3:** check that the switch is on and the sheet says webMAN is set up. Then use **Refresh Game List** in the menu bar.
- **It worked before, but not now:** the Mac's address has probably changed. Reserve it in the router, then press **Set Up webMAN for Me** again.
- **A game stutters:** connect the PS3 with a cable.

## In Terminal

```bash
ps3 config folder add PS3ISO ~/Games/PS3
ps3 serve          # runs the Game Server until you press Ctrl-C
```

`ps3 serve` only lets in the PS3 it finds. Set up webMAN once at `http://<the PS3's address>/setup.ps3`: network server 1 = the Mac's address, port 38008.
"""#
    )
}
