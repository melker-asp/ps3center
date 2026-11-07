// "Back Up and Restore Saves" in Help (⌘?) and `ps3 guide saves`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let saves = Guide(
        id: .saves,
        title: "Back Up and Restore Saves",
        summary: "Copy your saves to the Mac every week, and put one back when you need it.",
        symbol: "externaldrive.badge.checkmark",
        markdown: #"""
Your game saves live on the PS3's hard drive. PS3 Center copies them to the Mac, so a broken drive or a mistake doesn't cost you your progress. Backing up only reads the console; nothing on the PS3 changes.

## Back up now

1. Open the **Maintenance** tab.
2. On the **Saves** card, press **Back Up Now**.

The first backup copies every save. After that, only saves that have changed are copied. The card shows how many saves are backed up and when the last backup ran.

The backup is in `~/Library/Application Support/ps3center/Saves`, with a folder per PS3 user and save. When a save changes, the copy it replaces is kept in a `.previous` folder, so you also have the version before the latest.

## Back up every week

Turn on **Back Up Saves Weekly** in Settings → Transfers, or the **Weekly** switch on the Saves card. They are the same setting.

A little while after PS3 Center connects to the PS3, it checks whether a week has passed since the last backup. If so, and no game is running and the queue isn't sending, it copies the saves that have changed.

## See and restore saves

Press **Show…** on the Saves card. Switch between **On PS3** and **On Mac** at the top right.

To put a save back:

1. Choose **On Mac**.
2. Press **Restore…** beside the save.
3. Confirm with **Overwrite on PS3**.

Before the save on the PS3 is replaced, PS3 Center copies what is there now to the Mac. A few rules keep this safe:

- A save is only put back for the same PS3 user it came from.
- Restoring doesn't work while a game is running. Quit the game first.
- PS3 Center only reads a save's title and subtitle. It never shows the account details stored in the save.

## Delete a save from the PS3

Under **On PS3**, press **Delete…** beside a save and confirm. PS3 Center copies the save to the Mac first, so you can restore it later under **On Mac**.

## System files

The **System Files** card copies the PS3's system settings, webMAN's settings and the plugin lists (`boot_plugins.txt`) to the Mac when you press **Back Up Now**. Each backup is a dated folder in `~/Library/Application Support/ps3center/System Files`.

These copies are only for safekeeping: PS3 Center never writes them back to the console. **Set Up webMAN for Me** in the Game Server makes such a copy by itself before it changes anything (see [Play Games from the Mac](ps3center://guide/play-from-mac)).

## If something goes wrong

- **Restore is refused:** a game is running. Quit it and try again.
- **The backup didn't run this week:** PS3 Center has to be open while the PS3 is on and no game is running. Press **Back Up Now** to do it at once.

## In Terminal

```bash
ps3 saves                                   # the saves on the PS3
ps3 saves backup                            # copy changed saves to the Mac
ps3 saves local                             # what is in the backup
ps3 saves restore "Demon's Souls"           # put one back (asks first)
ps3 saves delete "Demon's Souls" --dry-run  # see what would happen
ps3 backup                                  # saves and system files (--only saves or system)
```
"""#
    )
}
