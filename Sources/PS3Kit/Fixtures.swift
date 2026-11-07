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

    // MARK: Maintenance

    public static let saves: [SaveGame] = [
        SaveGame(user: "00000001", folder: "BCES00569-GT5PROFILE", title: "Gran Turismo 5", subtitle: "Game Profile",
                 size: 3_481_600, modified: Date(timeIntervalSince1970: 1_792_670_400)),
        SaveGame(user: "00000001", folder: "BCES00757-SAVE0001", title: "Uncharted 2: Among Thieves", subtitle: "Chapter 14",
                 size: 262_144, modified: Date(timeIntervalSince1970: 1_792_400_000)),
        SaveGame(user: "00000001", folder: "BLES01807-AUTO", title: "Grand Theft Auto V", subtitle: "Franklin – 61 %",
                 size: 524_288, modified: Date(timeIntervalSince1970: 1_791_900_000)),
        SaveGame(user: "00000001", folder: "SLES-53326-SAVE", title: "Ratchet & Clank 3", size: 98_304,
                 modified: Date(timeIntervalSince1970: 1_790_000_000)),
    ]

    public static let maintenanceReport = MaintenanceReport(
        findings: [
            MaintenanceFinding(kind: .leftoverPackage, title: "IRISMAN_4.90.pkg",
                               detail: "A package or theme left in /dev_hdd0/packages. What it installed does not need it.",
                               path: "/dev_hdd0/packages/IRISMAN_4.90.pkg", size: 31_457_280, canFix: true),
            MaintenanceFinding(kind: .partialUpload, title: "Killzone 2 (Europe).iso",
                               detail: "A transfer that never finished. It does not show in the XMB.",
                               path: "/dev_hdd0/PS3ISO/Killzone 2 (Europe).iso.part", size: 4_294_967_296, canFix: true),
            MaintenanceFinding(kind: .duplicate, title: "Gran Turismo 5",
                               detail: "BCES00569 is there 2 times: /dev_hdd0/PS3ISO/Gran Turismo 5 (Europe).iso, /dev_hdd0/GAMES/BCES00569-[Gran Turismo 5]. Delete the one you don't need in the Games tab.",
                               size: 14_470_000_000),
            MaintenanceFinding(kind: .missingPlugin, title: "ds45pad.sprx",
                               detail: "boot_plugins.txt points to /dev_hdd0/plugins/ds45pad.sprx, which does not exist. PS3 Center never changes the list; remove the line yourself.",
                               path: "/dev_hdd0/plugins/ds45pad.sprx"),
            MaintenanceFinding(kind: .updates, title: "System updates are not blocked",
                               detail: "If the PS3 updates its system software by mistake, HEN can stop working. Blocking takes effect from the next start."),
        ],
        passed: ["webMAN's cache is small", "Plenty of free space"])

    public static let storageMap = StorageMap(
        areas: [
            StorageUsage(name: "PS3 ISOs", path: "/dev_hdd0/PS3ISO", bytes: 61_200_000_000),
            StorageUsage(name: "Installed games and apps", path: "/dev_hdd0/game", bytes: 38_400_000_000),
            StorageUsage(name: "Game folders", path: "/dev_hdd0/GAMES", bytes: 14_470_000_000),
            StorageUsage(name: "PS2 ISOs", path: "/dev_hdd0/PS2ISO", bytes: 9_800_000_000),
            StorageUsage(name: "Temporary files and webMAN's cache", path: "/dev_hdd0/tmp", bytes: 4_430_000_000),
            StorageUsage(name: "Users and saves", path: "/dev_hdd0/home", bytes: 1_250_000_000),
            StorageUsage(name: "Packages", path: "/dev_hdd0/packages", bytes: 31_457_280),
        ],
        largest: [
            StorageUsage(name: "Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso", path: "/dev_hdd0/PS3ISO/Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso", bytes: 9_600_000_000),
            StorageUsage(name: "Uncharted 2 - Among Thieves (Europe).iso", path: "/dev_hdd0/PS3ISO/Uncharted 2 - Among Thieves (Europe).iso", bytes: 23_200_000_000),
        ].sorted { $0.bytes > $1.bytes },
        free: 355_800_000_000, total: 500_107_862_016)

    public static let disc = DiscInfo(title: "Uncharted 3: Drake's Deception", titleID: "BCES01175", bytes: 41_300_000_000)

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
        "ds45pad": ("installed", "v2.0.0"),
        "apollo": ("02.40", "v2.4.1"),
        "pkgi": ("01.30", "v1.3.0"),
        "artemis": ("00.64", "r6.5"),  // an update the user has ignored (see ignoredUpdates)
        "ezremote": (nil, "1.25"),
        "irisman": ("04.92", "4.92"),
        "managunz": (nil, "v1.41"),
        "ps3health": (nil, "v2.2.1"),
        "ps3loadx": ("01.20", "v1.2.0"),
        "filemanager": ("01.10", "191-3541f8d"),
        "yoplayer": ("01.91", "191-3541f8d"),
        "cellstream": (nil, "191-3541f8d"),
        "thermalbench": (nil, "191-3541f8d"),
        "renpy": (nil, "191-3541f8d"),
        "movian": ("04.08", "Addons"),
        "jellyfin": (nil, "Addons"),
        "simplefm": (nil, "Addons"),
        "teeremoteplay": (nil, "Addons"),
        "teevanced": (nil, "Addons"),
        "ps2launcher": ("01.00", "1.47.51"),
        "ps2config": ("01.00", "1.47.51"),
        "pspremasters": (nil, "1.47.51"),
        "pspminis": (nil, "1.47.51"),
        "prepiso": (nil, "1.47.51"),
        "reloadxmb": ("01.00", "Launchers"),
        "romlauncher": (nil, "Launchers"),
    ]

    /// Release package sizes in bytes; the rest get `defaultPackageSize`.
    private static let packageSizes: [String: Int64] = [
        "webman": 21_495_808,
        "apollo": 5_452_595,
        "artemis": 3_879_731,
    ]
    private static let defaultPackageSize: Int64 = 6_291_456

    /// Days since the latest release, for "New" in Browse; the rest are older than 30 days.
    private static let releaseAges: [String: Double] = ["apollo": 5, "ezremote": 12, "ps3health": 21, "pkgi": 60]

    static func releaseDate(for id: String, now: Date = Date()) -> String {
        let days = releaseAges[id] ?? 200
        return ISO8601DateFormatter().string(from: now.addingTimeInterval(-days * 86_400))
    }

    /// Skipped in the fixtures, so the screens show the Ignored list.
    public static let ignoredUpdates = ["artemis": "r6.5"]

    /// Catalog rows as `AppsService.check` would return them for `console`.
    public static func appStatuses(on console: ConsoleSnapshot = snapshot,
                                   ignored: [String: String] = ignoredUpdates) -> [AppStatus] {
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
                release = .success(AppsService.LatestInfo(version: latest, assetURL: asset, assetName: asset?.lastPathComponent, assetData: assetData,
                                                          assetSize: asset == nil ? nil : packageSizes[entry.id] ?? defaultPackageSize,
                                                          releaseDate: releaseDate(for: entry.id)))
            }
            return service.status(for: entry, installedFile: installedFile, console: console, release: release, ignored: ignored)
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

    /// A fixed day, so that dates in the screenshots stay the same between runs.
    static func daysAgo(_ days: Int) -> Date {
        Date(timeIntervalSince1970: 1_792_670_400 - TimeInterval(days) * 86_400)
    }

    /// The console's games as `GameLibraryService.scan` returns them: Test Drive Unlimited 2 is
    /// the one mounted in `snapshot`, Gran Turismo 5 and The Last of Us have updates installed.
    public static let games: [Game] = GameListing.attach(["BCES00569": "02.11", "BCES01584": "01.11"], to: [
        Game(path: "/dev_hdd0/PS3ISO/Test Drive Unlimited 2 (Europe) (En,Fr,De,Es,It).dec.iso", title: "Test Drive Unlimited 2",
             titleID: "BLES01200", platform: .ps3, size: 9_642_180_608, version: "01.00", added: daysAgo(1)),
        Game(path: "/dev_hdd0/PS3ISO/Gran Turismo 5 (Europe).iso", title: "Gran Turismo 5", titleID: "BCES00569",
             platform: .ps3, size: 13_481_082_880, version: "01.00", added: daysAgo(120)),
        Game(path: "/dev_hdd0/PS3ISO/The Last of Us (Europe).iso", title: "The Last of Us", titleID: "BCES01584",
             platform: .ps3, size: 27_525_120_000, version: "01.00", added: daysAgo(9)),
        Game(path: "/dev_hdd0/PS3ISO/Red Dead Redemption (Europe).iso", title: "Red Dead Redemption", titleID: "BLES00680",
             platform: .ps3, size: 7_331_643_392, version: "01.00", added: daysAgo(64)),
        Game(path: "/dev_hdd0/GAMES/BLUS30443-[Demon's Souls]", title: "Demon's Souls", titleID: "BLUS30443",
             platform: .ps3, isFolder: true, version: "01.00", added: daysAgo(31)),
        Game(path: "/dev_hdd0/game/NPEA00418", title: "Journey", titleID: "NPEA00418", platform: .psn, isFolder: true,
             version: "01.03", added: daysAgo(200)),
        Game(path: "/dev_hdd0/PS2ISO/Shadow of the Colossus [SCES-53326].iso", title: "Shadow of the Colossus",
             titleID: "SCES-53326", platform: .ps2, size: 4_352_016_384, added: daysAgo(4)),
        Game(path: "/dev_hdd0/PS2ISO/Ratchet & Clank [SCES-50916].iso", title: "Ratchet & Clank", titleID: "SCES-50916",
             platform: .ps2, size: 3_120_562_176, added: daysAgo(88)),
        Game(path: "/dev_hdd0/PSXISO/Final Fantasy VII (Europe) (Disc 1).cue", title: "Final Fantasy VII", titleID: "SCES-00867",
             platform: .ps1, size: 698_496_000,
             companions: ["/dev_hdd0/PSXISO/Final Fantasy VII (Europe) (Disc 1).bin"], added: daysAgo(45)),
        Game(path: "/dev_usb000/PSXISO/Crash Bandicoot (Europe).cue", title: "Crash Bandicoot", titleID: "SCES-00344",
             platform: .ps1, size: 529_221_552, companions: ["/dev_usb000/PSXISO/Crash Bandicoot (Europe).bin"], added: daysAgo(150)),
        Game(path: "/dev_hdd0/PSPISO/Patapon (Europe).iso", title: "Patapon", titleID: "UCES-00995", platform: .psp,
             size: 312_475_648, added: daysAgo(17)),
    ])

    /// Games in the Mac's game folders: Gran Turismo 5 is on the console too, the others are not.
    public static let macGames: [Game] = GameListing.attach([:], to: [
        Game(path: "/Users/melker/Games/PS3/Gran Turismo 5 (Europe).iso", title: "Gran Turismo 5", titleID: "BCES00569",
             platform: .ps3, size: 13_481_082_880, version: "01.00", source: .mac,
             remotePath: "/dev_hdd0/PS3ISO/Gran Turismo 5 (Europe).iso", added: daysAgo(120)),
        Game(path: "/Users/melker/Games/PS3/Uncharted 2 - Among Thieves (Europe).iso", title: "Uncharted 2: Among Thieves",
             titleID: "BCES00757", platform: .ps3, size: 24_830_115_840, version: "01.00", source: .mac,
             remotePath: "/dev_hdd0/PS3ISO/Uncharted 2 - Among Thieves (Europe).iso", added: daysAgo(0)),
        Game(path: "/Users/melker/Games/PS3/LittleBigPlanet 2 (Europe).iso", title: "LittleBigPlanet 2", titleID: "BCES00850",
             platform: .ps3, size: 6_754_975_744, version: "01.00", source: .mac,
             remotePath: "/dev_hdd0/PS3ISO/LittleBigPlanet 2 (Europe).iso", added: daysAgo(3)),
        Game(path: "/Users/melker/Games/PS2/God of War [SCES-53133].iso", title: "God of War", titleID: "SCES-53133",
             platform: .ps2, size: 4_389_634_048, source: .mac, remotePath: "/dev_hdd0/PS2ISO/God of War [SCES-53133].iso", added: daysAgo(12)),
        Game(path: "/Users/melker/Games/PS1/Spyro the Dragon (Europe).cue", title: "Spyro the Dragon", titleID: "SCES-01438",
             platform: .ps1, size: 621_455_088, companions: ["/Users/melker/Games/PS1/Spyro the Dragon (Europe).bin"],
             source: .mac, remotePath: "/dev_hdd0/PSXISO/Spyro the Dragon (Europe).cue", added: daysAgo(40)),
    ])

    /// Game Folders: the folders behind `macGames`, the PS3 one watched, and one on a drive that is
    /// not plugged in (`unpluggedFolders`).
    public static var folderConfig: PS3Config {
        var config = PS3Config(folders: [
            "PS3ISO": ["/Users/melker/Games/PS3", "/Volumes/Games/PS3ISO"],
            "PS2ISO": ["/Users/melker/Games/PS2"],
            "PSXISO": ["/Users/melker/Games/PS1"],
        ])
        config.watchedFolders = ["/Users/melker/Games/PS3"]
        config.packageFolders = ["/Users/melker/Downloads/PS3", "/Users/melker/PS3/Homebrew", "/Volumes/Games/Packages"]
        return config
    }

    public static let unpluggedFolders: Set<String> = ["/Volumes/Games/PS3ISO", "/Volumes/Games/Packages"]

    // MARK: Packages on the Mac

    /// The .pkg files in the package folders of `folderConfig`: Apollo and RetroArch are
    /// installed on the console (`packageVersions`), PS3 Health (from the catalog) and multiMAN
    /// (in a folder of its own) are not.
    public static let packages: [LocalPackage] = [
        LocalPackage(path: "/Users/melker/Downloads/PS3/apollo-ps3.pkg", folder: "/Users/melker/Downloads/PS3",
                     contentID: "UP0001-NP0APOLLO_00-0000000000000000", size: 4_718_592, added: daysAgo(2)),
        LocalPackage(path: "/Users/melker/Downloads/PS3/PS3-Health-v2.2.1.pkg", folder: "/Users/melker/Downloads/PS3",
                     contentID: "UP0001-HDSH00001_00-0000000000000000", size: 1_153_434, added: daysAgo(0)),
        LocalPackage(path: "/Users/melker/PS3/Homebrew/RetroArch_1.19.1_CEX.pkg", folder: "/Users/melker/PS3/Homebrew",
                     contentID: "UP0001-SSNE10000_00-0000000000000002", size: 232_783_872, added: daysAgo(30)),
        LocalPackage(path: "/Users/melker/PS3/Homebrew/multiMAN/multiMAN_04.93.00_BASE.pkg", folder: "/Users/melker/PS3/Homebrew",
                     contentID: "EP0001-BLES80608_00-MULTIMANBASE0000", size: 48_496_640, added: daysAgo(90)),
    ]

    /// APP_VER on the console per title ID of `packages`, as `AppsService.installedVersions` reads it.
    public static let packageVersions: [String: String] = ["NP0APOLLO": "02.40", "SSNE10000": "01.19"]

    /// Two drives plugged in: a FAT32 stick for the console and an exFAT backup drive.
    public static let usbVolumes: [USBDrive.Volume] = [
        USBDrive.Volume(url: URL(fileURLWithPath: "/Volumes/PS3"), name: "PS3", format: "MS-DOS (FAT32)",
                        free: 118_300_000_000, capacity: 128_000_000_000),
        USBDrive.Volume(url: URL(fileURLWithPath: "/Volumes/Backup"), name: "Backup", format: "ExFAT",
                        free: 640_000_000_000, capacity: 1_000_000_000_000),
    ]

    /// A game folder with a file over 4 GB, which becomes an ISO on a FAT32 drive.
    static let folderGameWithBigFile = Game(path: "/Users/melker/Games/GAMES/Demon's Souls [BLES00932]", title: "Demon's Souls",
                                            titleID: "BLES00932", platform: .ps3, size: 7_431_000_000, isFolder: true, source: .mac,
                                            remotePath: "/dev_hdd0/GAMES/Demon's Souls [BLES00932]", added: daysAgo(2))

    /// What `USBDrive.plan` gives for four of the Mac's games and the folder above on the PS3
    /// stick: two split ISOs, the folder made into an ISO, a PS1 game as it is, and the PS2 ISO
    /// over 4 GB left out.
    public static var usbPlan: USBDrive.Plan {
        let root = usbVolumes[0].url
        func game(_ id: String) -> Game { macGames.first { $0.titleID == id }! }
        let uncharted = game("BCES00757"), lbp = game("BCES00850"), gow = game("SCES-53133"), spyro = game("SCES-01438")
        var plan = USBDrive.Plan()
        plan.copies = [
            USBDrive.Copy(game: uncharted, source: URL(fileURLWithPath: uncharted.path),
                          destination: root.appendingPathComponent("PS3ISO/Uncharted 2 - Among Thieves (Europe).iso.0"),
                          parts: PS3ISO.partCount(for: uncharted.size ?? 0), size: uncharted.size ?? 0),
            USBDrive.Copy(game: lbp, source: URL(fileURLWithPath: lbp.path),
                          destination: root.appendingPathComponent("PS3ISO/LittleBigPlanet 2 (Europe).iso.0"),
                          parts: PS3ISO.partCount(for: lbp.size ?? 0), size: lbp.size ?? 0),
            USBDrive.Copy(game: folderGameWithBigFile, source: URL(fileURLWithPath: folderGameWithBigFile.path),
                          destination: root.appendingPathComponent("PS3ISO/Demon's Souls [BLES00932].iso.0"),
                          parts: 2, size: 7_431_602_176, kind: .isoFromFolder),
            USBDrive.Copy(game: spyro, source: URL(fileURLWithPath: spyro.path),
                          destination: root.appendingPathComponent("PSXISO/Spyro the Dragon (Europe).cue"), parts: 1, size: 88),
            USBDrive.Copy(game: spyro, source: URL(fileURLWithPath: spyro.companions[0]),
                          destination: root.appendingPathComponent("PSXISO/Spyro the Dragon (Europe).bin"), parts: 1, size: 621_455_000),
        ]
        plan.skipped = [(gow, "God of War [SCES-53133].iso is over 4 GB, and only PS3 ISOs and movies can be split")]
        return plan
    }

    /// New on the console since the last import: two recordings and three screenshots.
    public static let mediaItems: [MediaImport.Item] = [
        .init(remotePath: "/dev_hdd0/VIDEO/BCES00569_2026.10.24_20_14_03.mp4", size: 412_000_000),
        .init(remotePath: "/dev_hdd0/VIDEO/BCES01584_2026.10.23_22_40_51.mp4", size: 1_240_000_000),
        .init(remotePath: "/dev_hdd0/photo/20261024/screenshot_001.jpg", size: 640_000),
        .init(remotePath: "/dev_hdd0/photo/20261024/screenshot_002.jpg", size: 655_000),
        .init(remotePath: "/dev_hdd0/photo/20261023/screenshot_001.jpg", size: 612_000),
    ]

    /// Demon's Souls, copied with `ps3 rip` and checked against its IRD.
    public static var discReports: [String: DiscVerifier.Report] {
        var report = DiscVerifier.Report(title: "Demon's Souls")
        report.checked = 1_204
        report.matched = 1_204
        return ["/dev_hdd0/GAMES/BLUS30443-[Demon's Souls]": report]
    }

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

    /// The connection sheet's Mac: a USB adapter straight to a PS3 that only links at 100 Mbit,
    /// and Wi-Fi to the router (the numbers from the console in PLAN.md's tests, Nov 7, 2026).
    public static let macInterfaces = [
        MacInterface(name: "en7", label: "USB 10/100/1000 LAN", kind: .ethernet, address: "192.168.2.1",
                     netmask: "255.255.255.0", linkSpeed: 100_000_000),
        MacInterface(name: "en0", label: "Wi-Fi", kind: .wifi, address: "10.0.1.62", netmask: "255.255.0.0", hasRouter: true),
    ]

    /// Two consoles answered: the one in use on Wi-Fi (`snapshot`) and one on the cable.
    public static let foundConsoles = [
        FoundConsole(host: "10.0.1.35", network: "Wi-Fi", firmware: "4.93 CEX · PS3HEN 3.5.0", via: "Wi-Fi"),
        FoundConsole(host: "192.168.2.2", network: "LAN", firmware: "4.92 CEX · PS3HEN 3.4.0", via: "USB 10/100/1000 LAN"),
    ]

    /// What `ps3 speedtest` measured over each network (the same Nov 7 numbers).
    public static let speedsByNetwork: [String: SpeedResult] = [
        "Wi-Fi": SpeedResult(upload: 1_112_650, download: 1_126_854, network: "Wi-Fi", measuredAt: Date()),
        "LAN": SpeedResult(upload: 5_504_212, download: nil, network: "LAN", measuredAt: Date()),
    ]

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
