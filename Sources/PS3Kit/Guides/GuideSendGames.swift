// "Send Your First Game" in Help (⌘?) and `ps3 guide send-games`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let sendGames = Guide(
        id: .sendGames,
        title: "Send Your First Game",
        summary: "Link your game folders, pick games, and let the queue send them to the PS3.",
        symbol: "arrow.up.circle",
        markdown: #"""
PS3 Center sends your own games from the Mac to the PS3's hard drive, each into the folder webMAN expects.

## Link your game folders

1. Open the **Games** tab and choose **On Mac** at the top left.
2. Press **Game Folders** (or **Add Game Folders…** if the view is empty).
3. Each row is a type: PS3 Games (ISO) for `PS3ISO`, PS3 Games (Folders) for `GAMES`, PS2, PS1 and PSP games, and Blu-ray and DVD movies. Press **Add…** on a row and choose a folder.
4. Press **Done**. Your games show up as a grid. A game the PS3 already has gets an *On PS3* label, and one that was only partly sent gets *Partial*.

Removing a folder from the list never touches the files. If your PS3 folder has `dev_hdd0/PS3ISO` and the like, those count by themselves.

## Pick games and send them

1. Click the games you want. Each gets a check mark, and a bar at the bottom shows how many you picked and their size.
2. Press **Send to PS3**. A review sheet opens.
3. Check the list, and untick a game to leave it out. The sheet shows the free space on the PS3 before and after, and how long it will take once you have measured the speed.
4. Choose what happens when the queue finishes: Nothing, Popup on TV or Shut Down PS3.
5. Press the white button, for example **Send 3 Games**. The queue starts right away.

You can also drag files or folders onto the window; they go to the same review. In Finder, **Send to PS3** is also under Quick Actions and Services.

## Follow the queue in Transfers

Press **Transfers**, the round button at the top right. A number on it shows how many games are waiting.

- Each game shows its progress, and the top line shows what is left, the speed and the time to go.
- **Pause** stops cleanly, and **Start** goes on from the same spot. A failed game has a retry button. The cross removes a game from the queue, not from the PS3.
- **Verify with MD5** has the PS3 compute a checksum of each large game to compare with the Mac's. It takes a few minutes per game.

## Interruptions are safe

- Each file is uploaded as `name.part` and renamed when it is complete, so the PS3 never lists half a game.
- If the network drops, the queue tries again after 15 seconds, 30 seconds, then 1, 2 and 4 minutes, and continues where the file stopped. If the PS3 has deleted the half-finished file, the queue starts that file over and says so.
- The Mac stays awake while the queue runs. If it sleeps anyway (a closed lid on battery), the queue pauses cleanly and goes on when the Mac wakes.
- **Warn and wait:** uploads start even while a game is running, but refreshing the game list waits until you quit the game.

## Watch a folder

In **Game Folders**, turn on **Watch** beside a folder. New games that land in it (not what is already there) join the queue once they have stopped growing, and are sent by themselves. PS3 Center has to be running for this.

## Wi-Fi or cable

The PS3's Wi-Fi only uses 2.4 GHz, the biggest brake on sending. A cable to the router, or straight to the Mac, is usually many times faster. Press **Measure Speed** in Transfers: the review then gives real time estimates, and on Wi-Fi it says how long a large batch would take with a cable.

## In Terminal

```bash
ps3 config folder add PS3ISO ~/Games/PS3   # link a folder
ps3 games mac --missing                    # games not on the PS3 yet
ps3 queue add "Gran Turismo"               # add to the queue the app shares
ps3 queue start --when-done shutdown --verify
ps3 send Game.iso                          # send one file right away
ps3 config folder watch ~/Games/PS3        # then run: ps3 watch
ps3 speedtest
```
"""#
    )
}
