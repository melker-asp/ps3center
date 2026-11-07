import Foundation

/// The homebrew `ps3 apps` knows how to check and install. Add new programs here.
/// Title IDs were read from each release's .pkg header (content ID at 0x30). Left out on purpose:
/// Swarm (a torrent client) and multiMAN, which shares /dev_hdd0/game/BLES80608 with webMAN's
/// cover packs, so uninstalling it would take the covers with it.
public struct CatalogEntry: Sendable {
    public enum Installed: Sendable {
        /// Version from /dev_hdd0/game/<titleID>/PARAM.SFO.
        case paramSFO(titleID: String)
        case webman
        case hen
        /// Plugin file on the console, compared byte for byte with the latest release asset.
        case pluginFile(remotePath: String)
    }

    public enum Source: Sendable {
        /// `tag` pins a release (for repos whose "latest" is something else); nil = latest.
        case github(repo: String, asset: String, tag: String? = nil)
        /// PS3HEN publishes no GitHub releases; HEN_REV in the payload source is the version.
        case henSource
        /// Brewology sits behind a bot check, so these are only linked, never fetched.
        case manual(url: String)
    }

    public enum Action: Sendable {
        case installPackage
        /// Installs the .pkg, then the user must finish a step on the console.
        case installPackageThenManual(String)
        /// Never installed automatically (HEN, plugins): show advice instead.
        case notifyOnly(String)
    }

    public enum Category: String, Codable, Sendable, CaseIterable {
        case system, tools, webmanAddons

        public var label: String {
            switch self {
            case .system: return "System"
            case .tools: return "Tools"
            case .webmanAddons: return "webMAN Add-ons"
            }
        }
    }

    public let id: String
    public let name: String
    public let summary: String
    public let category: Category
    public let installed: Installed
    public let source: Source
    public let installedStyle: VersionStyle
    public let releaseStyle: VersionStyle
    public let action: Action
    public let homepage: String
    /// False for packages bundled in someone else's release (their version does not follow the tag).
    public let tracksUpdates: Bool
    /// HEN/CFW, CEX/DEX and firmware limits. Installs that do not meet them are blocked.
    public let requirements: Requirements

    public init(id: String, name: String, summary: String, category: Category, installed: Installed, source: Source,
                installedStyle: VersionStyle = .appVer, releaseStyle: VersionStyle = .dotted,
                action: Action = .installPackage, homepage: String, tracksUpdates: Bool = true,
                requirements: Requirements = .any) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.installed = installed
        self.source = source
        self.installedStyle = installedStyle
        self.releaseStyle = releaseStyle
        self.action = action
        self.homepage = homepage
        self.tracksUpdates = tracksUpdates
        self.requirements = requirements
    }

    public var titleID: String? {
        if case .paramSFO(let id) = installed { return id }
        return nil
    }

    /// The GitHub repo whose README describes the program, nil for Brewology-only entries.
    public var repository: String? {
        switch source {
        case .github(let repo, _, _): return repo
        case .henSource: return "PS3Xploit/PS3HEN"
        case .manual: return nil
        }
    }

    /// Can `ps3 apps install <name>` fetch and install it?
    public var isInstallable: Bool {
        guard case .github = source else { return false }
        if case .notifyOnly = action { return false }
        return true
    }
}

public enum Catalog {
    static let webmanRepo = "aldostools/webMAN-MOD"
    static let resourcesRepo = "aldostools/Resources"
    static let mohasiRepo = "mohasi/ps3-dev"

    public static let entries: [CatalogEntry] = [
        // System
        CatalogEntry(
            id: "hen", name: "PS3HEN", summary: "Homebrew Enabler – the base for everything else",
            category: .system, installed: .hen, source: .henSource, installedStyle: .dotted,
            action: .notifyOnly("Update HEN only once you know your plugins (e.g. ds45pad) work with the new version. Installed through the HFW browser or the HEN installer."),
            homepage: "https://github.com/PS3Xploit/PS3HEN",
            // README: OFW 4.80–4.82, HFW 4.83–4.93; "CFWs can be used for testing, but not recommended".
            requirements: Requirements(exploits: [.hen], minFirmware: "4.80", note: "HEN is not needed on CFW")),
        CatalogEntry(
            id: "webman", name: "webMAN MOD", summary: "Game menu, FTP, ISO mounting and web commands",
            category: .system, installed: .webman,
            source: .github(repo: webmanRepo, asset: #"^webMAN_MOD_.*_Installer\.pkg$"#), installedStyle: .dotted,
            action: .installPackageThenManual("Start the webMAN MOD installer under Game in the XMB, then restart the console."),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases"),
        CatalogEntry(
            id: "ds45pad", name: "ds45pad (DualSense)", summary: "Plugin for DualSense and DualShock 4",
            category: .system, installed: .pluginFile(remotePath: "/dev_hdd0/plugins/ds45pad/ds45pad_vsh.sprx"),
            source: .github(repo: "domyno6773/DualSense-PS3", asset: #"^ds45pad_vsh\.sprx$"#), installedStyle: .dotted,
            action: .notifyOnly("Update manually: a broken sprx can make the console freeze when HEN starts. Read the release notes and have _Emergency/boot_plugins.txt ready."),
            homepage: "https://github.com/domyno6773/DualSense-PS3/releases"),

        // Programs
        CatalogEntry(
            id: "apollo", name: "Apollo Save Tool", summary: "Backs up, moves and patches saves",
            category: .tools, installed: .paramSFO(titleID: "NP0APOLLO"),
            source: .github(repo: "bucanero/apollo-ps3", asset: #"^apollo-ps3\.pkg$"#), releaseStyle: .semverAsAppVer,
            homepage: "https://github.com/bucanero/apollo-ps3/releases"),
        CatalogEntry(
            id: "pkgi", name: "PKGi PS3", summary: "Downloads PSN games, DLC and updates on the console",
            category: .tools, installed: .paramSFO(titleID: "NP00PKGI3"),
            source: .github(repo: "bucanero/pkgi-ps3", asset: #"^pkgi-ps3\.pkg$"#), releaseStyle: .semverAsAppVer,
            homepage: "https://github.com/bucanero/pkgi-ps3/releases"),
        CatalogEntry(
            id: "artemis", name: "Artemis PS3", summary: "Cheat codes (offline only)",
            category: .tools, installed: .paramSFO(titleID: "ARTPS3001"),
            source: .github(repo: "bucanero/ArtemisPS3", asset: #"^ArtemisPS3-GUI\.pkg$"#), releaseStyle: .artemis,
            homepage: "https://github.com/bucanero/ArtemisPS3/releases"),
        CatalogEntry(
            id: "ezremote", name: "ezRemote Client", summary: "Downloads files from FTP, SMB, WebDAV and HTTP servers",
            category: .tools, installed: .paramSFO(titleID: "RMTC00001"),
            source: .github(repo: "cy33hc/ps3-ezremote-client", asset: #"\.pkg$"#),
            homepage: "https://github.com/cy33hc/ps3-ezremote-client/releases"),
        CatalogEntry(
            id: "irisman", name: "IRISMAN", summary: "Backup manager and file manager (an alternative to multiMAN)",
            category: .tools, installed: .paramSFO(titleID: "IRISMAN00"),
            source: .github(repo: "aldostools/IRISMAN", asset: #"^IRISMAN_[\d.]+\.pkg$"#),
            homepage: "https://github.com/aldostools/IRISMAN/releases"),
        CatalogEntry(
            id: "managunz", name: "ManaGunZ", summary: "Backup manager with a file manager and game fixes",
            category: .tools, installed: .paramSFO(titleID: "MANAGUNZ0"),
            source: .github(repo: "Zarh/ManaGunZ", asset: #"^ManaGunZ_v[\d.]+\.pkg$"#),
            homepage: "https://github.com/Zarh/ManaGunZ/releases"),
        CatalogEntry(
            id: "ps3health", name: "PS3 Health", summary: "Shows the hard drive's SMART health on the TV",
            category: .tools, installed: .paramSFO(titleID: "HDSH00001"),
            source: .github(repo: "lucasdaddiego/ps3-health", asset: #"^PS3-Health-v[\d.]+\.pkg$"#), releaseStyle: .semverAsAppVer,
            homepage: "https://github.com/lucasdaddiego/ps3-health/releases",
            requirements: Requirements(untestedOn: [.cfw], note: "According to the README, a disk command can freeze the console on untested systems")),
        CatalogEntry(
            id: "ps3loadx", name: "PS3LoadX", summary: "Starts homebrew sent over the network (for developers)",
            category: .tools, installed: .paramSFO(titleID: "PSL145310"),
            source: .github(repo: "bucanero/ps3loadx", asset: #"^ps3loadx\.pkg$"#), releaseStyle: .semverAsAppVer,
            homepage: "https://github.com/bucanero/ps3loadx/releases"),
        // mohasi's apps (github.com/mohasi/ps3-dev). Their tags are build numbers ("191-3541f8d"),
        // not APP_VER, so updates are not tracked.
        CatalogEntry(
            id: "filemanager", name: "File Manager", summary: "File manager on the console (mohasi)",
            category: .tools, installed: .paramSFO(titleID: "FILEMGR01"),
            source: .github(repo: mohasiRepo, asset: #"^file-manager\.pkg$"#),
            homepage: "https://github.com/mohasi/ps3-dev/releases", tracksUpdates: false),
        CatalogEntry(
            id: "yoplayer", name: "Yo! Player", summary: "YouTube on the TV, up to 1080p",
            category: .tools, installed: .paramSFO(titleID: "YOPLAYER1"),
            source: .github(repo: mohasiRepo, asset: #"^yo-player\.pkg$"#),
            homepage: "https://github.com/mohasi/ps3-dev/releases", tracksUpdates: false),
        CatalogEntry(
            id: "cellstream", name: "Cell Stream", summary: "Streams the computer's screen to the PS3",
            category: .tools, installed: .paramSFO(titleID: "CELSTRM01"),
            source: .github(repo: mohasiRepo, asset: #"^cell-stream\.pkg$"#),
            homepage: "https://github.com/mohasi/ps3-dev/releases", tracksUpdates: false),
        CatalogEntry(
            id: "thermalbench", name: "Thermal Bench", summary: "Tests heat, fan and clock speeds and saves every run",
            category: .tools, installed: .paramSFO(titleID: "THERMAL01"),
            source: .github(repo: mohasiRepo, asset: #"^thermal-bench\.pkg$"#),
            homepage: "https://github.com/mohasi/ps3-dev/releases", tracksUpdates: false),
        CatalogEntry(
            id: "renpy", name: "Ren'Py Player", summary: "Plays visual novels made in Ren'Py (.rpk)",
            category: .tools, installed: .paramSFO(titleID: "RENPLAY01"),
            source: .github(repo: mohasiRepo, asset: #"^renpy-player\.pkg$"#),
            homepage: "https://github.com/mohasi/ps3-dev/releases", tracksUpdates: false),

        // Packages aldostools collects in Resources' "Addons" release; their versions do not follow it.
        CatalogEntry(
            id: "movian", name: "Movian", summary: "Media player for movies, music and photos (M7)",
            category: .tools, installed: .paramSFO(titleID: "HTSS00003"),
            source: .github(repo: resourcesRepo, asset: #"^movianM7-deank-playstation3\.pkg$"#, tag: "Addons"),
            homepage: "https://github.com/aldostools/Resources/releases/tag/Addons", tracksUpdates: false),
        CatalogEntry(
            id: "jellyfin", name: "JellyFin", summary: "Plays movies and shows from a Jellyfin server",
            category: .tools, installed: .paramSFO(titleID: "JFPS30000"),
            source: .github(repo: resourcesRepo, asset: #"^JellyFin-PS3\.pkg$"#, tag: "Addons"),
            homepage: "https://github.com/aldostools/Resources/releases/tag/Addons", tracksUpdates: false),
        CatalogEntry(
            id: "simplefm", name: "Simple File Manager MOD", summary: "File manager for exFAT, NTFS, FAT32, ext2/3/4 and UFS2",
            category: .tools, installed: .paramSFO(titleID: "PS3SFM001"),
            source: .github(repo: resourcesRepo, asset: #"^Simple_File_Manager_MOD\.pkg$"#, tag: "Addons"),
            homepage: "https://github.com/aldostools/Resources/releases/tag/Addons", tracksUpdates: false),
        CatalogEntry(
            id: "teeremoteplay", name: "TEE Remote Play", summary: "Streams the computer's screen to the PS3",
            category: .tools, installed: .paramSFO(titleID: "TEECRPMX1"),
            source: .github(repo: resourcesRepo, asset: #"^TEE-Remote-Play\.pkg$"#, tag: "Addons"),
            homepage: "https://github.com/aldostools/Resources/releases/tag/Addons", tracksUpdates: false),
        CatalogEntry(
            id: "teevanced", name: "TEE Vanced", summary: "YouTube on the TV",
            category: .tools, installed: .paramSFO(titleID: "TEEVANCED"),
            source: .github(repo: resourcesRepo, asset: #"^TEE-Vanced-PS3\.pkg$"#, tag: "Addons"),
            homepage: "https://github.com/aldostools/Resources/releases/tag/Addons", tracksUpdates: false),

        // webMAN add-ons: shipped inside webMAN's own release, so their versions do not follow the tag.
        CatalogEntry(
            id: "ps2launcher", name: "PS2 Classics Launcher", summary: "Starts PS2 Classics (.BIN.ENC), the only way PS2 games start on HEN",
            category: .webmanAddons, installed: .paramSFO(titleID: "PS2U10000"),
            source: .github(repo: webmanRepo, asset: #"^PS2_Classics_Launcher\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "ps2config", name: "PS2 CONFIG Database", summary: "Compatibility fixes for PS2 games",
            category: .webmanAddons, installed: .paramSFO(titleID: "PS2CONFIG"),
            source: .github(repo: webmanRepo, asset: #"^PS2CONFIG\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "pspremasters", name: "PSP Remasters Launcher", summary: "Starts PSP ISOs (try this first)",
            category: .webmanAddons, installed: .paramSFO(titleID: "PSPC66820"),
            source: .github(repo: webmanRepo, asset: #"^PSP_Remasters_Launcher\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "pspminis", name: "PSP Minis Launcher", summary: "Starts PSP ISOs (if Remasters does not work)",
            category: .webmanAddons, installed: .paramSFO(titleID: "PSPM66820"),
            source: .github(repo: webmanRepo, asset: #"^PSP_Minis_Launcher\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "prepiso", name: "prepISO", summary: "Prepares ISOs on NTFS drives for webMAN",
            category: .webmanAddons, installed: .paramSFO(titleID: "BLES80616"),
            source: .github(repo: webmanRepo, asset: #"^prepISO_[\d.]+\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "reloadxmb", name: "Reload XMB", summary: "Lets webMAN reload the XMB so new games show right away",
            category: .webmanAddons, installed: .paramSFO(titleID: "RELOADXMB"),
            source: .github(repo: resourcesRepo, asset: #"^Reload_XMB\.pkg$"#, tag: "Launchers"),
            homepage: "https://github.com/aldostools/Resources/releases/tag/Launchers", tracksUpdates: false),
        CatalogEntry(
            id: "romlauncher", name: "ROMS/PKG Launcher", summary: "Starts ROMs and PKGs from webMAN's game menu",
            category: .webmanAddons, installed: .paramSFO(titleID: "PKGLAUNCH"),
            source: .github(repo: resourcesRepo, asset: #"^ROMS_PKG_Launcher\.pkg$"#, tag: "Launchers"),
            homepage: "https://github.com/aldostools/Resources/releases/tag/Launchers", tracksUpdates: false),
    ]

    public enum Lookup {
        case found(CatalogEntry)
        case ambiguous([CatalogEntry])
        case missing
    }

    /// Exact id, title ID or name first; then a unique partial name match.
    public static func lookup(_ query: String) -> Lookup {
        let q = query.lowercased()
        if let exact = entries.first(where: { $0.id == q || $0.name.lowercased() == q || $0.titleID?.lowercased() == q }) {
            return .found(exact)
        }
        let partial = entries.filter { $0.name.lowercased().contains(q) || $0.id.contains(q) }
        switch partial.count {
        case 0: return .missing
        case 1: return .found(partial[0])
        default: return .ambiguous(partial)
        }
    }

    /// The entry a .pkg belongs to, from the title ID in its header.
    public static func entry(titleID: String) -> CatalogEntry? {
        entries.first { $0.titleID?.caseInsensitiveCompare(titleID) == .orderedSame }
    }

    public static func entry(named query: String) -> CatalogEntry? {
        if case .found(let entry) = lookup(query) { return entry }
        return nil
    }
}
