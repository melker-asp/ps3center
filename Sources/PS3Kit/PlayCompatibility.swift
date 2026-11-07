import Foundation

/// Why a PS1 or PS2 game might not start on this console, and what helps. Read from the
/// sources: PS3HEN's payload/storage_ext.c (LibCrypt) and webMAN's include/mount/mount_cobra.h
/// and ps2_classic.h (PS2).
public enum PlayCheck {
    public enum Finding: Equatable, Sendable {
        /// A PAL PS1 game with LibCrypt protection. HEN plays it when the subchannel data is in
        /// /dev_hdd0/tmp/lsd (or next to the image); without it the game stops early.
        case libCrypt(exe: String, installed: Bool)
        /// A plain PS2 ISO on HEN: webMAN refuses to mount it ("HEN does not support PS2 ISO").
        case ps2NeedsClassic
        /// A PS2 Classic (.BIN.ENC) with a fix in PS2 CONFIG Database, or none.
        case ps2Config(present: Bool)
        /// PS2 CONFIG Database is not installed, so no fixes are applied.
        case ps2ConfigMissing

        /// One line for the game page, `ps3 games info` and the send review.
        public var message: String {
            switch self {
            case .libCrypt(let exe, true):
                return "Kopieringsskyddet LibCrypt: datan som HEN behöver (\(exe).lsd) finns på PS3:an."
            case .libCrypt(let exe, false):
                return "Kopieringsskyddet LibCrypt: spelet stannar tidigt utan datan \(exe).lsd. Installera den härifrån (ps3 games libcrypt)."
            case .ps2NeedsClassic:
                return "Startar inte på HEN: webMAN monterar bara PS2-spel som PS2 Classics (.BIN.ENC) där, inte vanliga ISO:er. Gör om ISO:n till en PS2 Classic på datorn (t.ex. med PS2 Classics GUI) eller spela den på CFW."
            case .ps2Config(true):
                return "PS2 CONFIG Database har en rättning för spelet, och webMAN använder den när spelet startas."
            case .ps2Config(false):
                return "PS2 CONFIG Database har ingen rättning för spelet. De flesta spel behöver ingen."
            case .ps2ConfigMissing:
                return "PS2 CONFIG Database är inte installerat. Installera det under Appar så får spel med kända problem sina rättningar."
            }
        }

        /// True when the game will not start as it is.
        public var blocksPlay: Bool {
            switch self {
            case .ps2NeedsClassic, .libCrypt(_, false): return true
            default: return false
            }
        }
    }

    /// What can be told from the game alone, before looking on the console.
    public static func offline(_ game: Game, console: ConsoleProfile?) -> [Finding] {
        switch game.platform {
        case .ps1:
            guard let exe = LibCrypt.exe(for: game) else { return [] }
            return [.libCrypt(exe: exe, installed: false)]
        case .ps2:
            if console?.exploit == .hen, !PS2Classic.isClassic(game.path) { return [.ps2NeedsClassic] }
            return []
        default:
            return []
        }
    }

    /// The full check, with what is on the console.
    public static func check(_ game: Game, console: ConsoleProfile?, host: String) async throws -> [Finding] {
        let findings = offline(game, console: console)
        guard game.platform == .ps1 || game.platform == .ps2 else { return findings }
        return try await TransferService(host: host).withFTP { ftp in
            var result: [Finding] = []
            for finding in findings {
                if case .libCrypt(let exe, _) = finding {
                    let installed = try await LibCrypt.isInstalled(exe: exe, game: game, ftp: ftp)
                    result.append(.libCrypt(exe: exe, installed: installed))
                } else {
                    result.append(finding)
                }
            }
            if game.platform == .ps2, !result.contains(.ps2NeedsClassic), let id = PS2Classic.configID(for: game) {
                if try await ftp.size("/dev_hdd0/game/PS2CONFIG/PARAM.SFO") == nil {
                    result.append(.ps2ConfigMissing)
                } else {
                    let paths = PS2Classic.configPaths(id: id, classic: PS2Classic.isClassic(game.path))
                    var present = false
                    for path in paths where try await ftp.size(path) != nil { present = true; break }
                    result.append(.ps2Config(present: present))
                }
            }
            return result
        }
    }
}

/// LibCrypt subchannel data for PAL PS1 games. HEN looks for /dev_hdd0/tmp/lsd/<EXE>.lsd, then
/// /dev_hdd0/tmp/sbi/<EXE>.sbi, and for an image also <image>.lsd or .sbi beside it, where EXE is
/// the boot file named in SYSTEM.CNF ("SCES_014.31"). webMAN MOD's installer puts its own copies
/// in /dev_hdd0/tmp/lsd; this fills in one that is missing, from the same files on GitHub.
public enum LibCrypt {
    /// The games webMAN MOD ships LSD files for (_Projects_/updater/pkgfiles/USRDIR/lsd).
    public static let protected: Set<String> = [
        "SCED_019.79", "SCES_003.11", "SCES_014.31", "SCES_014.44", "SCES_014.92", "SCES_014.93", "SCES_014.94", "SCES_014.95",
        "SCES_015.16", "SCES_015.17", "SCES_015.18", "SCES_015.19", "SCES_015.64", "SCES_016.95", "SCES_017.00", "SCES_017.01",
        "SCES_017.02", "SCES_017.03", "SCES_017.04", "SCES_017.63", "SCES_018.82", "SCES_019.09", "SCES_019.79", "SCES_020.04",
        "SCES_020.05", "SCES_020.06", "SCES_020.07", "SCES_020.28", "SCES_020.29", "SCES_020.30", "SCES_020.31", "SCES_020.80",
        "SCES_021.04", "SCES_021.05", "SCES_021.81", "SCES_021.82", "SCES_021.84", "SCES_021.85", "SCES_022.22", "SCES_022.64",
        "SCES_022.69", "SCES_022.90", "SCES_023.65", "SCES_023.66", "SCES_023.67", "SCES_023.68", "SCES_023.69", "SCES_024.30",
        "SCES_024.31", "SCES_024.32", "SCES_024.33", "SCES_024.87", "SCES_024.88", "SCES_024.89", "SCES_024.90", "SCES_024.91",
        "SCES_025.44", "SCES_025.45", "SCES_025.46", "SCES_028.34", "SCES_028.35", "SCES_120.80", "SCES_220.80", "SCES_320.80",
        "SLES_000.17", "SLES_009.95", "SLES_010.41", "SLES_012.26", "SLES_012.41", "SLES_013.01", "SLES_013.62", "SLES_015.45",
        "SLES_017.15", "SLES_017.33", "SLES_019.06", "SLES_019.07", "SLES_019.43", "SLES_020.24", "SLES_020.25", "SLES_020.26",
        "SLES_020.27", "SLES_020.61", "SLES_020.71", "SLES_020.81", "SLES_020.82", "SLES_020.83", "SLES_020.84", "SLES_020.86",
        "SLES_021.12", "SLES_021.13", "SLES_021.18", "SLES_022.07", "SLES_022.08", "SLES_022.09", "SLES_022.10", "SLES_022.11",
        "SLES_022.92", "SLES_022.93", "SLES_023.28", "SLES_023.29", "SLES_023.30", "SLES_023.54", "SLES_023.55", "SLES_023.95",
        "SLES_023.96", "SLES_024.02", "SLES_025.29", "SLES_025.30", "SLES_025.31", "SLES_025.32", "SLES_025.33", "SLES_025.38",
        "SLES_025.58", "SLES_025.59", "SLES_025.60", "SLES_025.61", "SLES_025.62", "SLES_025.63", "SLES_025.72", "SLES_025.73",
        "SLES_026.81", "SLES_026.88", "SLES_026.89", "SLES_026.98", "SLES_027.00", "SLES_027.04", "SLES_027.05", "SLES_027.06",
        "SLES_027.07", "SLES_027.08", "SLES_027.22", "SLES_027.23", "SLES_027.24", "SLES_027.33", "SLES_027.54", "SLES_027.55",
        "SLES_027.56", "SLES_027.63", "SLES_027.66", "SLES_027.67", "SLES_027.68", "SLES_027.69", "SLES_028.24", "SLES_028.30",
        "SLES_028.31", "SLES_028.39", "SLES_028.57", "SLES_028.58", "SLES_028.59", "SLES_028.60", "SLES_028.61", "SLES_028.62",
        "SLES_029.65", "SLES_029.66", "SLES_029.67", "SLES_029.68", "SLES_029.69", "SLES_029.75", "SLES_029.76", "SLES_029.77",
        "SLES_029.78", "SLES_029.79", "SLES_030.61", "SLES_030.62", "SLES_031.89", "SLES_031.90", "SLES_031.91", "SLES_032.41",
        "SLES_032.42", "SLES_032.43", "SLES_032.44", "SLES_032.45", "SLES_033.24", "SLES_034.89", "SLES_035.19", "SLES_035.20",
        "SLES_035.21", "SLES_035.22", "SLES_035.23", "SLES_035.30", "SLES_036.03", "SLES_036.04", "SLES_036.05", "SLES_036.06",
        "SLES_036.07", "SLES_036.26", "SLES_036.48", "SLES_120.81", "SLES_120.82", "SLES_120.83", "SLES_120.84", "SLES_123.28",
        "SLES_123.29", "SLES_123.30", "SLES_125.58", "SLES_125.59", "SLES_125.60", "SLES_125.61", "SLES_125.62", "SLES_129.65",
        "SLES_129.66", "SLES_129.67", "SLES_129.68", "SLES_129.69", "SLES_220.81", "SLES_220.82", "SLES_220.83", "SLES_220.84",
        "SLES_223.28", "SLES_223.29", "SLES_223.30", "SLES_229.65", "SLES_229.66", "SLES_229.67", "SLES_229.68", "SLES_229.69",
        "SLES_320.81", "SLES_320.82", "SLES_320.83", "SLES_320.84", "SLES_329.65", "SLES_329.66", "SLES_329.67", "SLES_329.68",
        "SLES_329.69",
    ]

    public static let folder = "/dev_hdd0/tmp/lsd"

    static func dataURL(exe: String) -> URL? {
        URL(string: "https://raw.githubusercontent.com/aldostools/webMAN-MOD/master/_Projects_/updater/pkgfiles/USRDIR/lsd/\(exe).lsd")
    }

    /// "SCES-01431", "SCES01431" or "SCES_014.31" → "SCES_014.31". Nil for PSN's "NPEA00418":
    /// a game bought on PSN has no disc, and so no boot file named after its ID.
    public static func exeName(fromTitleID id: String) -> String? {
        let letters = id.prefix(4).uppercased()
        let digits = id.dropFirst(4).filter(\.isNumber)
        guard letters.count == 4, letters.allSatisfy(\.isLetter), !letters.hasPrefix("NP"), digits.count == 5 else { return nil }
        return "\(letters)_\(digits.prefix(3)).\(digits.suffix(2))"
    }

    /// The boot file name, when the game is one of the protected ones.
    public static func exe(for game: Game) -> String? {
        guard game.platform == .ps1, let id = game.titleID, let exe = exeName(fromTitleID: id), protected.contains(exe) else { return nil }
        return exe
    }

    public static func isInstalled(exe: String, game: Game, ftp: FTPClient) async throws -> Bool {
        var candidates = ["\(folder)/\(exe).lsd", "/dev_hdd0/tmp/sbi/\(exe).sbi"]
        if game.source == .console {
            let stem = (game.path as NSString).deletingPathExtension
            candidates += [stem + ".lsd", stem + ".sbi"]
        }
        for path in candidates where try await ftp.size(path) != nil { return true }
        return false
    }

    /// Fetches the game's LSD file and puts it in /dev_hdd0/tmp/lsd. Logged.
    public static func install(exe: String, host: String, dryRun: Bool = false, events: @Sendable (String) -> Void = { _ in }) async throws {
        guard protected.contains(exe), let url = dataURL(exe: exe) else {
            throw PS3Error.refused("\(exe) är inte ett spel med LibCrypt-skydd.")
        }
        let remote = "\(folder)/\(exe).lsd"
        if dryRun {
            events("Skulle hämta \(exe).lsd från webMAN MOD och lägga den i \(remote)")
            return
        }
        events("Hämtar \(exe).lsd")
        let (data, response) = try await URLSession.shared.data(from: url)
        // Each record is 15 bytes (read_libcrypt_sectors in PS3HEN).
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty, data.count % 15 == 0 else {
            throw PS3Error.github("\(exe).lsd gick inte att hämta från webMAN MOD.")
        }
        try await TransferService(host: host).withFTP { ftp in
            try await ftp.makeDirectories(folder)
            try await ftp.upload(contents: data, to: remote)
            guard try await ftp.size(remote) == Int64(data.count) else {
                throw PS3Error.ftpProtocol("\(remote) blev inte rätt på PS3:an.")
            }
        }
        OperationLog.record("libcrypt", remote)
        events("\(exe).lsd ligger på PS3:an. Starta spelet igen.")
    }
}

/// PS2 games on webMAN. On HEN only PS2 Classics (encrypted .BIN.ENC images) mount, through the
/// PS2 Classics Launcher; fixes come from PS2 CONFIG Database in /dev_hdd0/game/PS2CONFIG.
public enum PS2Classic {
    public static func isClassic(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".bin.enc")
    }

    /// "SLES-53133" → "SLES_531.33", the name of the game's config files.
    public static func configID(for game: Game) -> String? {
        game.titleID.flatMap(LibCrypt.exeName(fromTitleID:))
    }

    /// Where webMAN looks for the game's fix. A PS2 Classic uses CONFIG/ENC/<ID>.ENC; an ISO on
    /// CFW uses <ID>.CONFIG from CUSTOM, NET, GX or SOFT, in that order.
    public static func configPaths(id: String, classic: Bool) -> [String] {
        let base = "/dev_hdd0/game/PS2CONFIG/USRDIR"
        if classic { return ["\(base)/CONFIG/ENC/\(id).ENC"] }
        return ["\(base)/\(id).CONFIG"] + ["CUSTOM", "NET", "GX", "SOFT"].map { "\(base)/CONFIG/\($0)/\(id).CONFIG" }
    }
}
