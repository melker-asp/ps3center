// "Copy Games to a USB Drive" in Help (⌘?) and `ps3 guide usb-drive`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let usbDrive = Guide(
        id: .usbDrive,
        title: "Copy Games to a USB Drive",
        summary: "Put many games on a FAT32 drive at once; large ISOs are split for you.",
        symbol: "externaldrive",
        markdown: #"""
A USB drive is the fastest way to move many games at once. Copy them on the Mac, plug the drive into the PS3, and webMAN starts them straight from it. PS3 Center takes care of the one tricky part: the 4 GB limit.

## Why 4 GB matters

The PS3 reads USB drives formatted as FAT32, and FAT32 can't hold a file larger than 4 GB. PS3 Center works around it:

- **ISOs over 4 GB** (PS3 games, Blu-ray and DVD movies) are split into parts named `.iso.0`, `.iso.1` and so on. webMAN mounts the parts together.
- **A PS3 game folder with a file over 4 GB** becomes a PS3 ISO in parts, in `PS3ISO`, because webMAN can't start a split game folder from USB. Like the PC tool makeps3iso, PS3 Center leaves out the game's system update folder (`PS3_UPDATE`), so no firmware ends up on the drive.
- **Other files over 4 GB,** such as a large PS2 ISO, can't be split. They are listed as skipped, with the reason.

## Prepare the drive

Format the drive as *MS-DOS (FAT)* in Disk Utility. This erases everything on it. macOS can't write to NTFS drives.

## Copy the games

1. Plug the drive into the Mac.
2. Open **Games**, choose **On Mac**, and click the games you want.
3. Press **Copy to USB Drive…** in the bar at the bottom.
4. Pick the drive at the top. Each drive shows its format and free space, and a drive that isn't FAT32 gets a warning.
5. Check the list. Labels show what happens to each game: *Becomes an ISO*, the number of parts, or *Already there* for a game that is on the drive with the right size. Below the list you see the free space before and after.
6. Press the white button, for example **Copy 3 Games to “PS3”**.

Each file is written under a temporary name and renamed when it is complete. If you press **Stop Copying**, or something fails, what was finished stays and what wasn't is removed.

When it is done, press **Eject “PS3”** and unplug the drive.

## On the PS3

Plug the drive into the PS3. The games show up in webMAN's game list after a refresh: use **Refresh Game List** in the menu bar, or `ps3 refresh` in Terminal.

> A disc image that is still encrypted must be decrypted first. webMAN can't start an encrypted image on HEN, and PS3 Center doesn't decrypt images.

## If something goes wrong

- **No drive in the list:** check that the drive shows up in Finder, and that it is formatted as MS-DOS (FAT).
- **Not enough space:** the free-space line turns red. Untick games, or use a bigger drive.
- **A game is skipped:** the reason is on its row. Usually it is a file over 4 GB that can't be split.

## In Terminal

```bash
ps3 usb prepare /Volumes/PS3 gran demon   # two games from your Game Folders
ps3 usb prepare /Volumes/PS3 --missing    # every game not on the PS3 yet
ps3 iso make ~/Games/GAMES/MyGame         # a PS3 ISO from a game folder
ps3 iso split Game.iso /Volumes/PS3/PS3ISO
ps3 iso join Game.iso.0                   # parts back into one ISO
ps3 iso extract Game.iso                  # an ISO back into a game folder
```
"""#
    )
}
