import Foundation

/// The homebrew `ps3 apps` knows how to check and install. Add new programs here.
/// Title IDs were read from each release's .pkg header (content ID at 0x30).
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
            case .tools: return "Program"
            case .webmanAddons: return "webMAN-tillägg"
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

    public init(id: String, name: String, summary: String, category: Category, installed: Installed, source: Source,
                installedStyle: VersionStyle = .appVer, releaseStyle: VersionStyle = .dotted,
                action: Action = .installPackage, homepage: String, tracksUpdates: Bool = true) {
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
    }

    public var titleID: String? {
        if case .paramSFO(let id) = installed { return id }
        return nil
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

    public static let entries: [CatalogEntry] = [
        // System
        CatalogEntry(
            id: "hen", name: "PS3HEN", summary: "Homebrew Enabler – grunden för allt annat",
            category: .system, installed: .hen, source: .henSource, installedStyle: .dotted,
            action: .notifyOnly("Uppdatera HEN först när du vet att dina plugins (t.ex. ds45pad) fungerar med den nya versionen. Installeras via HFW-webbläsaren eller HEN-installeraren."),
            homepage: "https://github.com/PS3Xploit/PS3HEN"),
        CatalogEntry(
            id: "webman", name: "webMAN MOD", summary: "Spelmeny, FTP, ISO-montering och webbkommandon",
            category: .system, installed: .webman,
            source: .github(repo: webmanRepo, asset: #"^webMAN_MOD_.*_Installer\.pkg$"#), installedStyle: .dotted,
            action: .installPackageThenManual("Starta webMAN MOD-installeraren under Spel i XMB och starta sedan om konsolen."),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases"),
        CatalogEntry(
            id: "ds45pad", name: "ds45pad (DualSense)", summary: "Plugin för DualSense och DualShock 4",
            category: .system, installed: .pluginFile(remotePath: "/dev_hdd0/plugins/ds45pad/ds45pad_vsh.sprx"),
            source: .github(repo: "domyno6773/DualSense-PS3", asset: #"^ds45pad_vsh\.sprx$"#), installedStyle: .dotted,
            action: .notifyOnly("Uppdatera manuellt: en trasig sprx kan få konsolen att frysa vid HEN. Läs releaseanteckningarna och ha _Nödläge/boot_plugins.txt redo."),
            homepage: "https://github.com/domyno6773/DualSense-PS3/releases"),

        // Programs
        CatalogEntry(
            id: "apollo", name: "Apollo Save Tool", summary: "Säkerhetskopiera, flytta och patcha sparfiler",
            category: .tools, installed: .paramSFO(titleID: "NP0APOLLO"),
            source: .github(repo: "bucanero/apollo-ps3", asset: #"^apollo-ps3\.pkg$"#), releaseStyle: .semverAsAppVer,
            homepage: "https://github.com/bucanero/apollo-ps3/releases"),
        CatalogEntry(
            id: "pkgi", name: "PKGi PS3", summary: "Ladda ner PSN-spel, DLC och uppdateringar på konsolen",
            category: .tools, installed: .paramSFO(titleID: "NP00PKGI3"),
            source: .github(repo: "bucanero/pkgi-ps3", asset: #"^pkgi-ps3\.pkg$"#), releaseStyle: .semverAsAppVer,
            homepage: "https://github.com/bucanero/pkgi-ps3/releases"),
        CatalogEntry(
            id: "artemis", name: "Artemis PS3", summary: "Fuskkoder (bara offline)",
            category: .tools, installed: .paramSFO(titleID: "ARTPS3001"),
            source: .github(repo: "bucanero/ArtemisPS3", asset: #"^ArtemisPS3-GUI\.pkg$"#), releaseStyle: .artemis,
            homepage: "https://github.com/bucanero/ArtemisPS3/releases"),
        CatalogEntry(
            id: "ezremote", name: "ezRemote Client", summary: "Hämta filer från FTP-, SMB-, WebDAV- och HTTP-servrar",
            category: .tools, installed: .paramSFO(titleID: "RMTC00001"),
            source: .github(repo: "cy33hc/ps3-ezremote-client", asset: #"\.pkg$"#),
            homepage: "https://github.com/cy33hc/ps3-ezremote-client/releases"),
        CatalogEntry(
            id: "irisman", name: "IRISMAN", summary: "Backup-hanterare och filhanterare (alternativ till multiMAN)",
            category: .tools, installed: .paramSFO(titleID: "IRISMAN00"),
            source: .github(repo: "aldostools/IRISMAN", asset: #"^IRISMAN_[\d.]+\.pkg$"#),
            homepage: "https://github.com/aldostools/IRISMAN/releases"),
        CatalogEntry(
            id: "managunz", name: "ManaGunZ", summary: "Backup-hanterare med filhanterare och spelfixar",
            category: .tools, installed: .paramSFO(titleID: "MANAGUNZ0"),
            source: .github(repo: "Zarh/ManaGunZ", asset: #"^ManaGunZ_v[\d.]+\.pkg$"#),
            homepage: "https://github.com/Zarh/ManaGunZ/releases"),
        CatalogEntry(
            id: "ps3health", name: "PS3 Health", summary: "Visar hårddiskens SMART-hälsa på TV:n",
            category: .tools, installed: .paramSFO(titleID: "HDSH00001"),
            source: .github(repo: "lucasdaddiego/ps3-health", asset: #"^PS3-Health-v[\d.]+\.pkg$"#), releaseStyle: .semverAsAppVer,
            homepage: "https://github.com/lucasdaddiego/ps3-health/releases"),
        CatalogEntry(
            id: "ps3loadx", name: "PS3LoadX", summary: "Starta homebrew skickat över nätverket (för utvecklare)",
            category: .tools, installed: .paramSFO(titleID: "PSL145310"),
            source: .github(repo: "bucanero/ps3loadx", asset: #"^ps3loadx\.pkg$"#), releaseStyle: .semverAsAppVer,
            homepage: "https://github.com/bucanero/ps3loadx/releases"),
        CatalogEntry(
            id: "filemanager", name: "File Manager", summary: "Filhanterare på konsolen",
            category: .tools, installed: .paramSFO(titleID: "FILEMGR01"),
            source: .manual(url: "https://www.brewology.com/downloads/download.php?id=841"),
            releaseStyle: .appVer, action: .notifyOnly("Finns bara på Brewology. Kolla sidan manuellt."),
            homepage: "https://www.brewology.com/downloads/download.php?id=841"),

        // webMAN add-ons: shipped inside webMAN's own release, so their versions do not follow the tag.
        CatalogEntry(
            id: "ps2launcher", name: "PS2 Classics Launcher", summary: "Krävs för PS2-ISO:er på Super Slim (ingen PS2-hårdvara)",
            category: .webmanAddons, installed: .paramSFO(titleID: "PS2U10000"),
            source: .github(repo: webmanRepo, asset: #"^PS2_Classics_Launcher\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "ps2config", name: "PS2 CONFIG Database", summary: "Kompatibilitetsfixar för PS2-spel",
            category: .webmanAddons, installed: .paramSFO(titleID: "PS2CONFIG"),
            source: .github(repo: webmanRepo, asset: #"^PS2CONFIG\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "pspremasters", name: "PSP Remasters Launcher", summary: "Startar PSP-ISO:er (prova först)",
            category: .webmanAddons, installed: .paramSFO(titleID: "PSPC66820"),
            source: .github(repo: webmanRepo, asset: #"^PSP_Remasters_Launcher\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "pspminis", name: "PSP Minis Launcher", summary: "Startar PSP-ISO:er (om Remasters inte fungerar)",
            category: .webmanAddons, installed: .paramSFO(titleID: "PSPM66820"),
            source: .github(repo: webmanRepo, asset: #"^PSP_Minis_Launcher\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "prepiso", name: "prepISO", summary: "Förbereder ISO:er på NTFS-diskar för webMAN",
            category: .webmanAddons, installed: .paramSFO(titleID: "BLES80616"),
            source: .github(repo: webmanRepo, asset: #"^prepISO_[\d.]+\.pkg$"#),
            homepage: "https://github.com/aldostools/webMAN-MOD/releases", tracksUpdates: false),
        CatalogEntry(
            id: "reloadxmb", name: "Reload XMB", summary: "Låter webMAN ladda om XMB så nya spel syns direkt",
            category: .webmanAddons, installed: .paramSFO(titleID: "RELOADXMB"),
            source: .github(repo: resourcesRepo, asset: #"^Reload_XMB\.pkg$"#, tag: "Launchers"),
            homepage: "https://github.com/aldostools/Resources/releases/tag/Launchers", tracksUpdates: false),
        CatalogEntry(
            id: "romlauncher", name: "ROMS/PKG Launcher", summary: "Startar ROM:ar och PKG från webMANs spelmeny",
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

    public static func entry(named query: String) -> CatalogEntry? {
        if case .found(let entry) = lookup(query) { return entry }
        return nil
    }
}
