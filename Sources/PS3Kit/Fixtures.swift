import Foundation

/// Canned console and catalog data, so the app can render every screen without a PS3
/// (`PS3CENTER_FIXTURES=1`, used by CI to produce screenshots). The console strings are
/// trimmed copies of real responses (PSID/IDPS removed); versions are made up but realistic.
public enum Fixtures {
    public static let host = "10.0.1.35"

    static let henSysInfo = "CPU: 60°C RSX: 67°C FAN: 31% Play: 00:28:50 MAX: 68°C Firmware : 4.93 CEX PS3HEN 3.5.0 IP: 10.0.1.35 WLAN System storage: 355.8 GB free Memory: 1044 KB free [Full] "
    static let cfwSysInfo = "CPU: 58°C RSX: 63°C FAN: 30% Play: 00:12:04 MAX: 68°C Firmware : 4.92 CEX Cobra 8.4 IP: 10.0.1.35 LAN System storage: 112.4 GB free Memory: 1044 KB free [Full] "
    static let statusPage = #"<a href="/dev_bdvd">/dev_bdvd</a> -> <a class="f" href="/dev_hdd0/">/dev_hdd0</a>/<a class="f" href="/dev_hdd0/PS3ISO/">PS3ISO</a>/<a href="/mount.ps3/dev_hdd0/PS3ISO/Test+Drive+Unlimited+2+(Europe)+(En,Fr,De,Es,It).dec.iso">Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso</a></font><hr>webMAN 1.47.50c MOD - Simple Web Server (NTFS) [Full]"#

    /// The user's console: Super Slim on HFW 4.93 with PS3HEN, a game running.
    public static var snapshot: ConsoleSnapshot { make(sysInfo: henSysInfo, game: "EBOOT.BIN") }

    /// The same console on CFW, for screens that differ there (compatibility).
    public static var cfwSnapshot: ConsoleSnapshot { make(sysInfo: cfwSysInfo, game: nil) }

    private static func make(sysInfo: String, game: String?) -> ConsoleSnapshot {
        var s = ConsoleSnapshot.parse(sysInfo: sysInfo, statusPage: statusPage)
        s.host = host
        s.runningProcess = game
        s.computeHealth()
        return s
    }

    /// A temperature-like series for the sparklines.
    public static func series(around value: Double, count: Int = 40, swing: Double = 3) -> [Double] {
        (0..<count).map { i in
            let t = Double(i)
            return value + swing * sin(t / 4.5) + swing * 0.4 * sin(t / 1.7)
        }
    }

    public static let history: [OperationLog.Entry] = [
        .init(date: "2026-10-24T18:12:40+02:00", action: "install", detail: "apollo-ps3.pkg"),
        .init(date: "2026-10-24T17:58:03+02:00", action: "send", detail: "/dev_hdd0/PS3ISO/Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso (9.6 GB)"),
        .init(date: "2026-10-23T21:40:11+02:00", action: "refresh", detail: "/refresh.ps3"),
        .init(date: "2026-10-23T21:31:55+02:00", action: "install", detail: "pkgi-ps3.pkg"),
    ]

    // MARK: Apps

    /// Installed APP_VER (or plugin/console version) and the latest release, per catalog id.
    /// nil installed = not on the console.
    private static let versions: [String: (installed: String?, latest: String)] = [
        "hen": (nil, "3.6.0"),  // read from the console snapshot
        "webman": (nil, "1.47.51"),  // read from the console snapshot
        "ds45pad": ("installerad", "v2.0.0"),
        "apollo": ("02.40", "v2.4.1"),
        "pkgi": ("01.30", "v1.3.0"),
        "artemis": ("00.64", "r6.4"),
        "ezremote": (nil, "1.25"),
        "irisman": ("04.92", "4.92"),
        "managunz": (nil, "v1.41"),
        "ps3health": (nil, "v2.2.1"),
        "ps3loadx": ("01.20", "v1.2.0"),
        "filemanager": ("01.10", ""),
        "ps2launcher": ("01.00", "1.47.51"),
        "ps2config": ("01.00", "1.47.51"),
        "pspremasters": (nil, "1.47.51"),
        "pspminis": (nil, "1.47.51"),
        "prepiso": (nil, "1.47.51"),
        "reloadxmb": ("01.00", "Launchers"),
        "romlauncher": (nil, "Launchers"),
    ]

    /// Catalog rows as `AppsService.check` would return them for `console`.
    public static func appStatuses(on console: ConsoleSnapshot = snapshot) -> [AppStatus] {
        let service = AppsService(host: host)
        return Catalog.entries.map { entry in
            let version = versions[entry.id]
            var installedFile: Data?
            var assetData: Data?
            switch entry.installed {
            case .paramSFO(let titleID):
                installedFile = version?.installed.map { ParamSFO.encode(["APP_VER": $0, "TITLE_ID": titleID]) }
            case .pluginFile:
                installedFile = Data("ds45pad".utf8)
                assetData = installedFile
            case .webman, .hen:
                break
            }
            let release: Result<AppsService.LatestInfo, Error>?
            switch entry.source {
            case .manual:
                release = nil
            case .github, .henSource:
                let latest = version?.latest ?? "1.0"
                let asset: URL? = entry.isInstallable ? URL(string: "https://github.com/\(entry.repository ?? "")/releases/download/\(latest)/\(entry.id).pkg") : nil
                release = .success(AppsService.LatestInfo(version: latest, assetURL: asset, assetName: asset?.lastPathComponent, assetData: assetData))
            }
            return service.status(for: entry, installedFile: installedFile, console: console, release: release)
        }
    }

    /// A README with every kind of block, in the style of Apollo's.
    public static let readme = Readme(markdown: """
    # Apollo Save Tool (PS3)

    [![Downloads](https://img.shields.io/github/downloads/bucanero/apollo-ps3/total.svg)](https://github.com/bucanero/apollo-ps3/releases)

    **Apollo Save Tool** is an application to manage save-game files, trophies, and licenses on the PlayStation 3.

    ![image](./docs/screenshots/screenshot_main.png)

    # Features

    * **Easy to use:** no crypto-key configuration or advanced setup needed.
    * **Standalone:** no computer required, everything happens on the PS3.
    * **Multi-user:** supports multiple user accounts.
      - Supported formats: `.PSV`, `.MCS`, `.PSU`

    > [!NOTE]
    > On first run, the application will detect and setup the required user settings.

    ## Data folders

    | PS3 | Folder |
    |-----|--------|
    | **USB saves** | `/dev_usb00x/PS3/SAVEDATA/` |
    | **HDD saves** | `/dev_hdd0/home/000000XX/savedata/` |

    ```
    /dev_hdd0/game/NP0APOLLO/USRDIR/owners.xml
    ```

    See the [latest changes here](CHANGELOG.md).
    """, repo: "bucanero/apollo-ps3",
         rawBase: URL(string: "https://raw.githubusercontent.com/bucanero/apollo-ps3/master/"),
         htmlBase: URL(string: "https://github.com/bucanero/apollo-ps3/blob/master/"),
         htmlURL: URL(string: "https://github.com/bucanero/apollo-ps3/blob/master/README.md"))
}
