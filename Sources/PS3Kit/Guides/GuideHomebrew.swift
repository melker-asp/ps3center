// "Install and Update Homebrew" in Help (⌘?) and `ps3 guide homebrew`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let homebrew = Guide(
        id: .homebrew,
        title: "Install and Update Homebrew",
        summary: "Keep your PS3 apps up to date, and install new ones from the catalog.",
        symbol: "shippingbox",
        markdown: #"""
Homebrew is software the community makes for the PS3: file managers, save tools, media players and more. The **Apps** tab compares the apps on your PS3 with the latest releases on GitHub, and installs updates and new apps for you.

PS3 Center keeps a copy of every package it installs in your PS3 folder, under `_Installed/Packages`. If you haven't set one up, a red banner in Apps offers **Create Folder…** and **Choose Folder…**.

## Updates

The **Updates** list shows each app with a new version as *02.40 → 02.41*, in the form the PS3 itself uses for versions.

- **Update** installs that one app.
- **Ignore** hides this version. The app moves to *Ignored*, and when an even newer version comes out it shows up again. **Stop Ignoring** brings it back now.
- **Update All…** installs them all, after a review. If some updates only get advice, the button names how many it installs instead, for example **Update 2…**.

Apps PS3 Center can't check by itself are under *Check Manually*, with **Open Page**.

## Update All, step by step

1. Press **Update All…**. The *Update Apps* sheet lists the updates with check boxes and sizes, the total download and the free space on the PS3. Under *Skipped* you see what won't be installed, and why.
2. Untick anything you want to leave for later, then press the white button, for example **Install 3 Updates**.
3. The packages are downloaded from GitHub and installed one at a time. Each is checked against the size and SHA-256 checksum GitHub gives. A file that doesn't match is deleted, not installed.
4. When the queue is done, a report appears at the top of Updates: *Done*, *Failed* and *Skipped*, each with the reason. Close it with the cross.

If a game is running, installs wait until you quit it. A banner says so, and **Install Anyway** goes ahead.

## Browse

**Browse** shows the whole catalog, in *System*, *Tools* and *webMAN Add-ons*. Apps released in the last 30 days are also in a *New* row at the top. Press **Install** on a tile to install one.

Click any app for its page: the installed and latest version, whether it works on your PS3, its source, and its README from GitHub. An installed app has **Uninstall…**, which asks first. Its saves stay on the PS3.

## The compatibility check

Before anything is installed, PS3 Center reads your PS3's firmware: HEN or CFW, CEX or DEX, and the version. Each app's requirements come from its own README or release notes.

- *Doesn't Work:* the app doesn't run on your PS3, so it is blocked.
- *Untested:* no one has confirmed it on a PS3 like yours. You get a warning, but can install it.
- *Unknown Firmware:* the firmware couldn't be read, so apps that have requirements are blocked. Apps without requirements are never affected.

## HEN, webMAN and plugins

- **PS3HEN** and plugins such as **ds45pad** are never installed automatically, because a broken plugin can make the PS3 freeze at startup. Their rows show advice and **Learn More** instead of an Update button. PS3 Center never uninstalls them either.
- **webMAN MOD** can be updated from here. Afterwards, start the webMAN MOD installer under Game on the PS3, restart the console, and enable HEN again.

## In Terminal

```bash
ps3 apps                    # installed apps and updates
ps3 apps available          # the whole catalog
ps3 apps info apollo        # version, compatibility and README
ps3 apps update --dry-run   # see what would be installed
ps3 apps update             # asks for each app; -y says yes
ps3 apps install ezremote
ps3 apps ignore irisman     # skip this version
```
"""#
    )
}
