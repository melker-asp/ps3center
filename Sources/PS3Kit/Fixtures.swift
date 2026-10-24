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
        s.totalBytes = 500_107_862_016  // the Super Slim's 500 GB drive
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

    /// Gran Turismo 5 played on and off for a while.
    public static let playLog: PlayLog = {
        var log = PlayLog()
        log.games["/dev_hdd0/PS3ISO/Gran Turismo 5 (Europe).iso"] = PlayLog.Record(
            title: "Gran Turismo 5", seconds: 41 * 3600 + 25 * 60, sessions: 37,
            lastPlayed: Date(timeIntervalSince1970: 1_792_670_400))
        return log
    }()

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

    // MARK: Games

    /// The console's games as `GameLibraryService.scan` returns them: Test Drive Unlimited 2 is
    /// the one mounted in `snapshot`, Gran Turismo 5 and The Last of Us have updates installed.
    public static let games: [Game] = GameListing.attach(["BCES00569": "02.11", "BCES01584": "01.11"], to: [
        Game(path: "/dev_hdd0/PS3ISO/Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso", title: "Test Drive Unlimited 2",
             titleID: "BLES01200", platform: .ps3, size: 9_642_180_608, version: "01.00"),
        Game(path: "/dev_hdd0/PS3ISO/Gran Turismo 5 (Europe).iso", title: "Gran Turismo 5", titleID: "BCES00569",
             platform: .ps3, size: 13_481_082_880, version: "01.00"),
        Game(path: "/dev_hdd0/PS3ISO/The Last of Us (Europe).iso", title: "The Last of Us", titleID: "BCES01584",
             platform: .ps3, size: 27_525_120_000, version: "01.00"),
        Game(path: "/dev_hdd0/PS3ISO/Red Dead Redemption (Europe).iso", title: "Red Dead Redemption", titleID: "BLES00680",
             platform: .ps3, size: 7_331_643_392, version: "01.00"),
        Game(path: "/dev_hdd0/GAMES/BLUS30443-[Demon's Souls]", title: "Demon's Souls", titleID: "BLUS30443",
             platform: .ps3, isFolder: true, version: "01.00"),
        Game(path: "/dev_hdd0/game/NPEA00418", title: "Journey", titleID: "NPEA00418", platform: .psn, isFolder: true,
             version: "01.03"),
        Game(path: "/dev_hdd0/PS2ISO/Shadow of the Colossus [SCES-53326].iso", title: "Shadow of the Colossus",
             titleID: "SCES-53326", platform: .ps2, size: 4_352_016_384),
        Game(path: "/dev_hdd0/PS2ISO/Ratchet & Clank [SCES-50916].iso", title: "Ratchet & Clank", titleID: "SCES-50916",
             platform: .ps2, size: 3_120_562_176),
        Game(path: "/dev_hdd0/PSXISO/Final Fantasy VII (Europe) (Disc 1).cue", title: "Final Fantasy VII", titleID: "SCES-00867",
             platform: .ps1, size: 698_496_000,
             companions: ["/dev_hdd0/PSXISO/Final Fantasy VII (Europe) (Disc 1).bin"]),
        Game(path: "/dev_usb000/PSXISO/Crash Bandicoot (Europe).cue", title: "Crash Bandicoot", titleID: "SCES-00344",
             platform: .ps1, size: 529_221_552, companions: ["/dev_usb000/PSXISO/Crash Bandicoot (Europe).bin"]),
        Game(path: "/dev_hdd0/PSPISO/Patapon (Europe).iso", title: "Patapon", titleID: "UCES-00995", platform: .psp,
             size: 312_475_648),
    ])

    /// Games in the Mac's game folders: Gran Turismo 5 is on the console too, the others are not.
    public static let macGames: [Game] = GameListing.attach([:], to: [
        Game(path: "/Users/melker/Spel/PS3/Gran Turismo 5 (Europe).iso", title: "Gran Turismo 5", titleID: "BCES00569",
             platform: .ps3, size: 13_481_082_880, version: "01.00", source: .mac,
             remotePath: "/dev_hdd0/PS3ISO/Gran Turismo 5 (Europe).iso"),
        Game(path: "/Users/melker/Spel/PS3/Uncharted 2 - Among Thieves (Europe).iso", title: "Uncharted 2: Among Thieves",
             titleID: "BCES00757", platform: .ps3, size: 24_830_115_840, version: "01.00", source: .mac,
             remotePath: "/dev_hdd0/PS3ISO/Uncharted 2 - Among Thieves (Europe).iso"),
        Game(path: "/Users/melker/Spel/PS3/LittleBigPlanet 2 (Europe).iso", title: "LittleBigPlanet 2", titleID: "BCES00850",
             platform: .ps3, size: 6_754_975_744, version: "01.00", source: .mac,
             remotePath: "/dev_hdd0/PS3ISO/LittleBigPlanet 2 (Europe).iso"),
        Game(path: "/Users/melker/Spel/PS2/God of War [SCES-53133].iso", title: "God of War", titleID: "SCES-53133",
             platform: .ps2, size: 4_389_634_048, source: .mac, remotePath: "/dev_hdd0/PS2ISO/God of War [SCES-53133].iso"),
        Game(path: "/Users/melker/Spel/PS1/Spyro the Dragon (Europe).cue", title: "Spyro the Dragon", titleID: "SCES-01438",
             platform: .ps1, size: 621_455_088, companions: ["/Users/melker/Spel/PS1/Spyro the Dragon (Europe).bin"],
             source: .mac, remotePath: "/dev_hdd0/PSXISO/Spyro the Dragon (Europe).cue"),
    ])

    /// The send queue halfway through Uncharted 2, set to shut the console down when done.
    public static var queue: TransferQueue {
        var queue = TransferQueue()
        func item(_ game: Game, _ state: TransferQueue.Item.State, sent fraction: Double) -> TransferQueue.Item {
            let size = game.size ?? 0
            let file = TransferQueue.File(local: game.path, remote: game.remotePath ?? "", kind: .ps3ISO, size: size)
            return TransferQueue.Item(id: UUID(), title: game.title, files: [file], state: state, sent: Int64(Double(size) * fraction),
                                      message: nil, addedAt: Date(), finishedAt: state == .done ? Date() : nil)
        }
        let uncharted = macGames.first { $0.titleID == "BCES00757" }!
        let lbp = macGames.first { $0.titleID == "BCES00850" }!
        let gow = macGames.first { $0.titleID == "SCES-53133" }!
        queue.items = [item(gow, .done, sent: 1), item(uncharted, .sending, sent: 0.42), item(lbp, .waiting, sent: 0)]
        queue.whenDone = .shutdown
        return queue
    }

    public static let speed = SpeedResult(upload: 3_250_000, download: 4_100_000, network: "Wi-Fi", measuredAt: Date())

    /// Sony's newer patches for Gran Turismo 5 (02.11 installed) and Red Dead Redemption, by game id.
    public static var patches: [String: [GamePatch]] {
        func patch(_ titleID: String, _ version: String, _ size: Int64, system: String) -> GamePatch {
            let file = "EP9000-\(titleID)_00-GRANTURISMO5XXXX-A\(version.replacingOccurrences(of: ".", with: ""))-V0100-PE.pkg"
            return GamePatch(titleID: titleID, version: version, size: size, sha1: "", systemVersion: system,
                             url: URL(string: "http://b0.ww.np.dl.playstation.net/tppkg/np/\(titleID)/\(titleID)_T5/\(file)")!)
        }
        let gt5 = games.first { $0.titleID == "BCES00569" }!
        let rdr = games.first { $0.titleID == "BLES00680" }!
        return [
            gt5.id: ["02.12", "02.13", "02.14", "02.15", "02.16", "02.17"].map { patch("BCES00569", $0, 212_000_000, system: "4.00") },
            rdr.id: [patch("BLES00680", "01.09", 98_566_144, system: "3.41")],
        ]
    }
}
