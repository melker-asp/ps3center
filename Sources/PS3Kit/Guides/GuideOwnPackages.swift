// "Install Your Own .pkg Files" in Help (⌘?) and `ps3 guide own-packages`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let ownPackages = Guide(
        id: .ownPackages,
        title: "Install Your Own .pkg Files",
        summary: "Install .pkg files you already have on the Mac, with one click and no USB stick.",
        symbol: "square.and.arrow.down",
        markdown: #"""
A `.pkg` is the PS3's install package, the format apps and game updates come in. If you have packages on the Mac that aren't in PS3 Center's catalog, or a version you downloaded yourself, the **From Mac** list in the Apps tab installs them for you. No USB stick needed.

## Link a package folder

1. Open **Apps** and choose **From Mac**.
2. Press **Package Folders** (or **Add Package Folders…** if the list is empty). You can also get there from Settings → Folders → Package Folders → **Edit…**.
3. Press **Add…** and choose a folder with `.pkg` files. PS3 Center looks in the folder and in the folders directly inside it.
4. Press **Done**.

Removing a folder from the list never touches the files.

## Install a package

The packages are listed per folder. Each row shows the name, the file, its size and whether it is installed on the PS3. When PS3 Center knows the package from its catalog, it shows the app's real name and its title ID, the code every app and game has (like `NP0APOLLO`).

1. Press **Install** on a row (**Reinstall** if it is already there).
2. PS3 Center sends the package to `/dev_hdd0/packages` on the PS3 and has webMAN install it. The row shows the progress.
3. The install is done when the app's folder on the PS3 has been updated and stops changing. PS3 Center then removes its copy from the PS3.

The file on the Mac stays exactly where it is. It isn't moved, renamed or archived.

If a game is running, the install waits until you quit it. A banner says so, and **Install Anyway** goes ahead.

## The compatibility check

PS3 Center reads the title ID inside each package. If that title ID is in the catalog, the package gets the same check as an install from **Browse**. If the app doesn't work on your PS3's firmware, the row says *Doesn't Work* and the install is blocked.

A package PS3 Center doesn't know is installed without this check, so make sure it is meant for your PS3.

Click a package that is in the catalog to open that app's page, with its README and compatibility. See [Install and Update Homebrew](ps3center://guide/homebrew).

## If something goes wrong

- **The install never starts:** PS3 Center sends the install command once more, then stops with advice. The package is still in `/dev_hdd0/packages`, so you can install it on the PS3 under Game → Package Manager → Install Package Files → Standard.
- **"is not a valid PS3 package":** the file is damaged, or isn't a PS3 package. Get it again.
- **Dragging a `.pkg` onto the window** only copies it to `/dev_hdd0/packages`. Use **From Mac** to install it.

## In Terminal

```bash
ps3 config folder add PKG ~/Packages   # link a package folder
ps3 apps mac                           # packages and whether they are installed
ps3 apps mac --missing                 # only those not installed
ps3 apps install NP0APOLLO             # file name or title ID from a package folder
ps3 apps install ~/Downloads/App.pkg   # any file; archived in _Installed/Packages
```
"""#
    )
}
