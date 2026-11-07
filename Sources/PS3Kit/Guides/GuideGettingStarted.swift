// "Getting Started" in Help (⌘?) and `ps3 guide getting-started`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let gettingStarted = Guide(
        id: .gettingStarted,
        title: "Getting Started",
        summary: "What you need, how PS3 Center finds your PS3, and what to set up first.",
        symbol: "sparkles",
        markdown: #"""
PS3 Center controls your PS3 from the Mac: its status, your games, homebrew and save backups. This guide takes you from opening the app to a connected console.

## What you need

- **A PS3 with PS3HEN or custom firmware (CFW).** HEN, the Homebrew Enabler, lets the PS3 run homebrew on its regular system software. CFW is modified system software that does the same from the start.
- **webMAN MOD on the PS3.** It is a plugin that gives the PS3 a small web server and FTP server, and lists your games. PS3 Center talks to the console through it.
- **The Mac and the PS3 on the same network,** or a network cable between them. A cable is much faster for sending games.

> PS3 Center never installs or enables HEN for you. On HEN, choose *Enable HEN* under Game on the PS3 after every restart. Until you do, webMAN doesn't start and PS3 Center can't reach the console.

## Connect to the PS3

1. Turn on the PS3 and enable HEN. On CFW there is nothing to do.
2. Open PS3 Center. The first time, a setup guide walks you through these steps (**Skip Setup** leaves it).
3. PS3 Center first tries the address it saved last time. If nothing answers there, it searches your local network for webMAN, which takes up to half a minute.
4. When the PS3 answers, the tabs light up and a green dot appears by the PlayStation logo at the top. The address is saved, and if the PS3 gets a new one later, PS3 Center finds it again by itself.

If the screen says *The PS3 is on, but HEN isn't enabled*, the console answers on the network but webMAN doesn't. Enable HEN on the PS3, and PS3 Center connects by itself.

If it says *Can't reach the PS3*, check that the PS3 is on and HEN is enabled, then press **Try Again**. **Find PS3…** searches every network the Mac is on, takes an address you type, and shows how to connect a cable. More help is in [Troubleshooting](ps3center://guide/troubleshooting).

## Set up your folders

Open **Settings** with the gear at the top right (or ⌘,) and choose **Folders**. Settings works even before a console is connected.

1. **PS3 Folder.** A folder on the Mac laid out like the PS3's hard drive. PS3 Center keeps a copy of every app it installs in its `_Installed/Packages`. If you don't have one, press **Create…** and pick a place: PS3 Center makes a folder called PS3 there. If you already have one, press **Choose…**.
2. **Game Folders.** Press **Edit…** and add the folders where you keep your games, one or more per type. They show up under **On Mac** in the Games tab. See [Send Your First Game](ps3center://guide/send-games).
3. **Package Folders** are optional: folders with `.pkg` files you want to install. See [Install Your Own .pkg Files](ps3center://guide/own-packages).

## A quick tour

- **Status:** health, temperatures, the fan, free space and what is playing, with the **Remote**, the power buttons and a list of what PS3 Center has changed.
- **Games:** the games on the PS3 (**On PS3**) and in your Game Folders (**On Mac**). Click a game on the PS3 to start, mount or delete it.
- **Apps:** homebrew updates, a catalog to **Browse**, and your own packages under **From Mac**.
- **Maintenance:** save backups, system files, Cleanup, Storage, the disc and your videos and photos.
- **Transfers,** the round button at the top right, is the queue of games being sent. Beside it are Help (the question mark, or ⌘?) and **Settings** (the gear).

## In Terminal

```bash
ps3 discover                               # find the PS3 and save its address
ps3 status                                 # health, temperatures, fan, free space
ps3 config set root ~/Documents --create   # make an empty PS3 folder
ps3 config folder add PS3ISO ~/Games/PS3   # link a game folder
```
"""#
    )
}
