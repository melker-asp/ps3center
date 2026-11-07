import Foundation

/// The console's error codes, explained in English. The system codes (0x8001xxxx) and their names
/// come from RPCS3's rpcs3/Emu/Cell/ErrorCodes.h. The XMB's own codes for discs, Blu-ray, video, the
/// network and the account (`xmbTable`) are the ones ps3.world/error-codes lists as common, with the
/// meaning checked there (Nov 2026). The advice is PS3 Center's own, for HEN and webMAN.
public enum ConsoleErrorCode {
    public struct Info: Sendable {
        public let code: UInt32
        public let name: String
        public let meaning: String
        public let advice: String?
    }

    static let table: [UInt32: (String, String, String?)] = [
        0x80010001: ("EAGAIN", "The resource is temporarily busy.", "Try again in a moment."),
        0x80010002: ("EINVAL", "An invalid value was passed.", nil),
        0x80010003: ("ENOSYS", "The function does not exist.", nil),
        0x80010004: ("ENOMEM", "Out of memory.", "Restart the console and try again."),
        0x80010005: ("ESRCH", "What was asked for does not exist.", nil),
        0x80010006: ("ENOENT", "The file does not exist.", "Check that the game is complete, or send it again."),
        0x80010007: ("ENOEXEC", "The file has an unknown format.", "Often a broken or incomplete EBOOT.BIN or SELF file."),
        0x80010008: ("EDEADLK", "A deadlock was avoided.", nil),
        0x80010009: ("EPERM", "The operation is not permitted.", "Is HEN enabled? Without HEN, homebrew does not start."),
        0x8001000A: ("EBUSY", "The device or resource is busy.", "Wait until what is running has finished."),
        0x8001000B: ("ETIMEDOUT", "The time ran out.", nil),
        0x8001000C: ("EABORT", "The operation was aborted.", nil),
        0x8001000D: ("EFAULT", "Invalid memory access.", nil),
        0x8001000E: ("ENOCHILD", "The process has no child processes.", nil),
        0x8001000F: ("ESTAT", "The thread is in the wrong state.", nil),
        0x80010010: ("EALIGN", "Wrong alignment in memory.", nil),
        0x80010011: ("EKRESOURCE", "Not enough kernel resources.", nil),
        0x80010012: ("EISDIR", "It is a folder, not a file.", nil),
        0x80010013: ("ECANCELED", "The operation was canceled.", nil),
        0x80010014: ("EEXIST", "It already exists.", nil),
        0x80010015: ("EISCONN", "The port is already connected.", nil),
        0x80010016: ("ENOTCONN", "The port is not connected.", nil),
        0x80010017: ("EAUTHFAIL", "The program could not be verified.", "The program is not signed for the console. Enable HEN, or reinstall the program."),
        0x80010018: ("ENOTMSELF", "The file is not an MSELF.", nil),
        0x80010019: ("ESYSVER", "Wrong system version.", "The game or app needs different system software than the console has."),
        0x8001001A: ("EAUTHFATAL", "Fatal system error during verification.", nil),
        0x8001001B: ("EDOM", "Math domain error.", nil),
        0x8001001C: ("ERANGE", "The value is out of range.", nil),
        0x8001001D: ("EILSEQ", "Invalid character sequence.", nil),
        0x8001001E: ("EFPOS", "Wrong position in the file.", nil),
        0x8001001F: ("EINTR", "The call was interrupted.", nil),
        0x80010020: ("EFBIG", "The file is too large.", "FAT32 drives cannot hold files over 4 GB; split the ISO (ps3 usb prepare)."),
        0x80010021: ("EMLINK", "Too many links.", nil),
        0x80010022: ("ENFILE", "The file table is full.", nil),
        0x80010023: ("ENOSPC", "There is no space left.", "Free up space on the hard drive (Maintenance → Storage)."),
        0x80010024: ("ENOTTY", "Not a terminal.", nil),
        0x80010025: ("EPIPE", "The connection broke.", nil),
        0x80010026: ("EROFS", "The file system is read-only.", nil),
        0x80010027: ("ESPIPE", "Invalid seek in the file.", nil),
        0x80010028: ("E2BIG", "Too many arguments.", nil),
        0x80010029: ("EACCES", "Access denied.", nil),
        0x8001002A: ("EBADF", "Invalid file reference.", nil),
        0x8001002B: ("EIO", "Input/output error.", "The drive or disc may be damaged, or the file incomplete."),
        0x8001002C: ("EMFILE", "Too many open files.", nil),
        0x8001002D: ("ENODEV", "The device does not exist.", "Is the USB drive connected?"),
        0x8001002E: ("ENOTDIR", "It is not a folder.", nil),
        0x8001002F: ("ENXIO", "The device does not exist or is not answering.", nil),
        0x80010030: ("EXDEV", "Cannot link across devices.", nil),
        0x80010031: ("EBADMSG", "Bad message.", nil),
        0x80010032: ("EINPROGRESS", "Already in progress.", nil),
        0x80010033: ("EMSGSIZE", "The message has the wrong size.", nil),
        0x80010034: ("ENAMETOOLONG", "The name is too long.", "Shorten the file or folder name."),
        0x80010035: ("ENOLCK", "No lock available.", nil),
        0x80010036: ("ENOTEMPTY", "The folder is not empty.", nil),
        0x80010037: ("ENOTSUP", "Not supported.", nil),
        0x80010038: ("EFSSPECIFIC", "File system error.", nil),
        0x80010039: ("EOVERFLOW", "The value got too large.", nil),
        0x8001003A: ("ENOTMOUNTED", "The file system is not mounted.", "Is the drive connected and the game mounted?"),
        0x8001003B: ("ENOTSDATA", "Not SDATA.", nil),
        0x8001003C: ("ESDKVER", "Wrong SDK version.", "The game needs newer system software than the console has."),
        0x8001003D: ("ENOLICDISC", "The game wants its disc in the drive.",
                     "Insert the disc. For a copy: mount the game in webMAN first, then start it."),
        0x8001003E: ("ENOLICENT", "A license is missing, usually because the disc is not in the drive.",
                     "Insert the disc, or mount the copy in webMAN before the game starts."),
    ]

    /// The XMB's codes outside 0x8001xxxx that come up most, with a short tag in place of a name.
    static let xmbTable: [UInt32: (String, String, String?)] = [
        0x8001050B: ("DISC", "A game or demo on the hard drive will not start with a disc in the drive.",
                     "Eject the disc and restart the console."),
        0x80010514: ("DISC", "The disc cannot be read.",
                     "Clean the disc and try another. If no disc can be read, the Blu-ray drive is broken; games from the hard drive still work."),
        0x80010516: ("DISC", "The disc cannot be loaded.", "Insert it again or clean it."),
        0x8002291A: ("BLU-RAY", "The Blu-ray disc cannot be read.", "Clean the disc. If no disc reads, the drive needs repair."),
        0x80029906: ("BLU-RAY", "A home-burned BD-R is not accepted as a disc.", "Burn it again with an up-to-date program, e.g. ImgBurn."),
        0x8002990C: ("VIDEO", "The console cannot play this kind of video.", "Convert the file to MP4 (H.264)."),
        0x8002990D: ("VIDEO", "The video or disc cannot be played.", "Clean the disc. For a file, MP4 (H.264) plays best."),
        0x80710102: ("NETWORK", "No DNS server answers, or two devices have the same IP address.",
                     "Restart the router and set DNS yourself (1.1.1.1). If the PS3 has a fixed address, check that no other device has it."),
        0x80029519: ("ACCOUNT", "The account cannot be activated, and purchased PSN games stop working.",
                     "Common after HEN, a deactivation or a firmware change. PS3 Center changes nothing here: purchased games need the account's activation."),
    ]

    public static func info(_ code: UInt32) -> Info? {
        guard let entry = table[code] ?? xmbTable[code] else { return nil }
        return Info(code: code, name: entry.0, meaning: entry.1, advice: entry.2)
    }

    /// "80010006", "0x80010006" or "8001 0006".
    public static func parse(_ text: String) -> UInt32? {
        var hex = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        if hex.lowercased().hasPrefix("0x") { hex = String(hex.dropFirst(2)) }
        guard hex.count == 8 else { return nil }
        return UInt32(hex, radix: 16)
    }

    /// Every known code in `text`, explained: for an error message from the console.
    public static func explain(in text: String) -> [Info] {
        let pattern = #"(?:0x)?(80[0-9A-Fa-f]{6})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<UInt32>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: text), let code = UInt32(text[r], radix: 16),
                  seen.insert(code).inserted else { return nil }
            return info(code)
        }
    }

    /// `message` with an explanation for each system error code in it, one per line.
    public static func annotate(_ message: String) -> String {
        let explained = explain(in: message).map(describe)
        return explained.isEmpty ? message : ([message] + explained).joined(separator: "\n")
    }

    /// "80010006 (ENOENT): The file does not exist. Check …"
    public static func describe(_ info: Info) -> String {
        let hex = String(format: "%08X", info.code)
        return "\(hex) (\(info.name)): \(info.meaning)" + (info.advice.map { " \($0)" } ?? "")
    }
}
