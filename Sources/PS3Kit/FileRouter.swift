import Foundation

/// Decides where on the console a local file belongs (README: "Vart ska filen?").
public enum ContentKind: String, Codable, Sendable {
    case ps3ISO, ps2ISO, pspISO, psxISO, bluRayISO, dvdISO, ps3Folder, package, license, theme, other

    public var remoteFolder: String? {
        switch self {
        case .ps3ISO: return "/dev_hdd0/PS3ISO"
        case .ps2ISO: return "/dev_hdd0/PS2ISO"
        case .pspISO: return "/dev_hdd0/PSPISO"
        case .psxISO: return "/dev_hdd0/PSXISO"
        case .bluRayISO: return "/dev_hdd0/BDISO"
        case .dvdISO: return "/dev_hdd0/DVDISO"
        case .ps3Folder: return "/dev_hdd0/GAMES"
        case .package: return "/dev_hdd0/packages"
        case .license: return "/dev_hdd0/exdata"
        // Installed from there by the XMB (`TransferService.installThemes`).
        case .theme: return "/dev_hdd0/packages"
        case .other: return nil
        }
    }

    public var label: String {
        switch self {
        case .ps3ISO: return "PS3-spel"
        case .ps2ISO: return "PS2-spel"
        case .pspISO: return "PSP-spel"
        case .psxISO: return "PS1-spel"
        case .bluRayISO: return "Blu-ray-film"
        case .dvdISO: return "DVD-film"
        case .ps3Folder: return "PS3-spel (mapp)"
        case .package: return "Paket"
        case .license: return "Licens"
        case .theme: return "Tema"
        case .other: return "Fil"
        }
    }

    /// Kinds that show up in webMAN's game list after a refresh.
    public var needsRefresh: Bool {
        switch self {
        case .package, .license, .theme, .other: return false
        default: return true
        }
    }
}

public struct Route: Equatable, Sendable {
    public let local: URL
    public let remote: String
    public let kind: ContentKind
    public let size: Int64
    /// Game title for the popup, when it can be read from the file.
    public let title: String?

    public init(local: URL, remote: String, kind: ContentKind, size: Int64, title: String?) {
        self.local = local
        self.remote = remote
        self.kind = kind
        self.size = size
        self.title = title
    }

    static let gameFolders = ["PS3ISO", "PS2ISO", "PSXISO", "PSPISO", "BDISO", "DVDISO", "GAMES"]
        .map { "/dev_hdd0/\($0)/" }

    /// True when the file lands where webMAN scans for games, so the list needs a refresh.
    public var refreshesGameList: Bool {
        Self.gameFolders.contains { remote.hasPrefix($0) }
    }
}

public enum FileRouter {
    static let ignoredNames: Set<String> = [".DS_Store", "Vimm's Lair.txt", "Thumbs.db"]

    public static func routes(for inputs: [URL], mirrorRoot: URL?, remoteFolder override: String? = nil) throws -> [Route] {
        var routes: [Route] = []
        for input in inputs {
            routes += try routesFor(input.standardizedFileURL, mirrorRoot: mirrorRoot?.standardizedFileURL, override: override)
        }
        // A .cue and the .bin it references might both be listed; keep one of each.
        var seen = Set<String>()
        return routes.filter { seen.insert($0.local.path).inserted }
    }

    private static func routesFor(_ url: URL, mirrorRoot: URL?, override: String?) throws -> [Route] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw PS3Error.invalidFile("Hittar inte \(url.path).")
        }

        if let root = mirrorRoot {
            let usb = root.appendingPathComponent("USB").path + "/"
            if url.path.hasPrefix(usb) || url.path == root.appendingPathComponent("USB").path {
                throw PS3Error.unsupportedFile("\(url.lastPathComponent) ligger i USB/, som är till för USB-stickan. Kopiera den till stickan i stället.")
            }
        }

        if isDir.boolValue {
            if fm.fileExists(atPath: url.appendingPathComponent("PS3_GAME/PARAM.SFO").path) {
                let base = override ?? mirrorRelativeParent(of: url, root: mirrorRoot) ?? ContentKind.ps3Folder.remoteFolder!
                let title = (try? Data(contentsOf: url.appendingPathComponent("PS3_GAME/PARAM.SFO"))).flatMap(ParamSFO.init(data:))?.title
                return try filesRecursively(in: url).map { file in
                    let relative = String(file.path.dropFirst(url.path.count))
                    return Route(local: file, remote: base + "/" + url.lastPathComponent + relative,
                                 kind: .ps3Folder, size: fileSize(file), title: title)
                }
            }
            return try filesRecursively(in: url).flatMap { file -> [Route] in
                do { return try routesFor(file, mirrorRoot: mirrorRoot, override: override) }
                catch PS3Error.unsupportedFile { return [] }  // skip unknown files inside folders
            }
        }

        if ignoredNames.contains(url.lastPathComponent) { return [] }

        let ext = url.pathExtension.lowercased()
        if ext == "pup" {
            throw PS3Error.unsupportedFile("Firmware (\(url.lastPathComponent)) installeras från USB-stickan: /PS3/UPDATE/PS3UPDAT.PUP.")
        }

        // Files inside the mirror keep their path ("mappnamn = sökväg på PS3:an").
        if override == nil, let root = mirrorRoot, let remote = mirrorPath(of: url, root: root) {
            let (kind, title) = (try? classify(url)) ?? (.other, nil)
            var routes = [Route(local: url, remote: remote, kind: kind, size: fileSize(url), title: title)]
            if ext == "cue" { routes += cueCompanions(url, mirrorRoot: root, override: nil, title: title) }
            if kind == .psxISO { routes += libCryptCompanions(url, remote: remote, title: title) }
            return routes
        }

        // With an explicit --to folder any file is allowed.
        let (kind, title) = override == nil ? try classify(url) : ((try? classify(url)) ?? (.other, nil))
        guard let folder = override ?? kind.remoteFolder else {
            throw PS3Error.unsupportedFile("Vet inte var \(url.lastPathComponent) ska ligga. Ange mapp med --to, t.ex. --to /dev_hdd0/PS3ISO")
        }
        var routes = [Route(local: url, remote: folder + "/" + url.lastPathComponent, kind: kind, size: fileSize(url), title: title)]
        if ext == "cue" { routes += cueCompanions(url, mirrorRoot: nil, override: folder, title: title) }
        if kind == .psxISO { routes += libCryptCompanions(url, remote: folder + "/" + url.lastPathComponent, title: title) }
        return routes
    }

    /// Identifies a file by extension and, for ISOs, by its contents.
    public static func classify(_ url: URL) throws -> (ContentKind, String?) {
        switch url.pathExtension.lowercased() {
        case "pkg": return (.package, nil)
        case "rap": return (.license, nil)
        case "p3t": return (.theme, GameName.clean(url.lastPathComponent))
        // A PS2 Classic: the only kind of PS2 game webMAN mounts on HEN.
        case "enc" where url.lastPathComponent.lowercased().hasSuffix(".bin.enc"): return (.ps2ISO, GameName.clean(url.lastPathComponent))
        case "cue", "bin", "img", "ecm": return (.psxISO, GameName.clean(url.lastPathComponent))
        case "iso": return try classifyISO(url)
        default:
            throw PS3Error.unsupportedFile("Vet inte var \(url.lastPathComponent) ska ligga. Ange mapp med --to.")
        }
    }

    static func classifyISO(_ url: URL) throws -> (ContentKind, String?) {
        let iso = try ISOImage(url: url)
        let fallbackTitle = GameName.clean(url.lastPathComponent)
        if let sfo = try iso.readFile("PS3_GAME/PARAM.SFO").flatMap(ParamSFO.init(data:)) {
            return (.ps3ISO, sfo.title ?? fallbackTitle)
        }
        if iso.volumeID == "PS3VOLUME" { return (.ps3ISO, fallbackTitle) }
        if iso.systemID.hasPrefix("PSP GAME") { return (.pspISO, fallbackTitle) }
        if iso.systemID.hasPrefix("PLAYSTATION") {
            let cnf = try iso.readFile("SYSTEM.CNF").map { String(decoding: $0, as: UTF8.self) } ?? ""
            return (cnf.contains("BOOT2") ? .ps2ISO : .psxISO, fallbackTitle)
        }
        if try iso.find("BDMV") != nil { return (.bluRayISO, fallbackTitle) }
        if try iso.find("VIDEO_TS") != nil { return (.dvdISO, fallbackTitle) }
        throw PS3Error.unsupportedFile("Känner inte igen \(url.lastPathComponent) som PS3-, PS2-, PS1- eller PSP-spel. Ange mapp med --to.")
    }

    /// "/Users/.../PS3/dev_hdd0/PS3ISO/X/x.iso" -> "/dev_hdd0/PS3ISO/X/x.iso"
    static func mirrorPath(of url: URL, root: URL) -> String? {
        let hdd = root.appendingPathComponent("dev_hdd0").path
        guard url.path.hasPrefix(hdd + "/") else { return nil }
        return "/dev_hdd0" + url.path.dropFirst(hdd.count)
    }

    static func mirrorRelativeParent(of url: URL, root: URL?) -> String? {
        guard let root else { return nil }
        return mirrorPath(of: url.deletingLastPathComponent(), root: root)
    }

    static func cueCompanions(_ cue: URL, mirrorRoot: URL?, override: String?, title: String?) -> [Route] {
        guard let text = try? String(contentsOf: cue, encoding: .utf8) else { return [] }
        let names = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            ConsoleSnapshot.firstMatch(#"FILE\s+"([^"]+)""#, in: String(line))?[1]
        }
        return names.compactMap { name in
            let file = cue.deletingLastPathComponent().appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            let remote: String
            if let root = mirrorRoot, let path = mirrorPath(of: file, root: root) { remote = path }
            else { remote = (override ?? ContentKind.psxISO.remoteFolder!) + "/" + name }
            return Route(local: file, remote: remote, kind: .psxISO, size: fileSize(file), title: title)
        }
    }

    /// LibCrypt data beside a PS1 image (<name>.lsd or .sbi) goes along. HEN looks for it beside
    /// the data track it opens, with the track's ".bin" swapped for ".lsd" or ".sbi" (lowercase),
    /// so it is sent under the first track's name.
    static func libCryptCompanions(_ image: URL, remote: String, title: String?) -> [Route] {
        let folder = image.deletingLastPathComponent()
        var track = image
        if image.pathExtension.lowercased() == "cue", let first = cueCompanions(image, mirrorRoot: nil, override: "/", title: nil).first {
            track = first.local
        }
        let stems = Set([image.deletingPathExtension().lastPathComponent, track.deletingPathExtension().lastPathComponent].map { $0.lowercased() })
        let remoteFolder = (remote as NSString).deletingLastPathComponent
        let remoteStem = track.deletingPathExtension().lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for ext in ["lsd", "sbi"] {
            if let name = names.first(where: { stems.contains(($0 as NSString).deletingPathExtension.lowercased()) && ($0 as NSString).pathExtension.lowercased() == ext }) {
                let file = folder.appendingPathComponent(name)
                return [Route(local: file, remote: remoteFolder + "/" + remoteStem + "." + ext, kind: .psxISO, size: fileSize(file), title: title)]
            }
        }
        return []
    }

    static func filesRecursively(in dir: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .filter { !ignoredNames.contains($0.lastPathComponent) }
            .sorted { $0.path < $1.path }
    }

    public static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
