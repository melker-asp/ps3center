import Foundation

/// The console's system error codes (0x8001xxxx), in Swedish. The names and meanings come from
/// RPCS3's rpcs3/Emu/Cell/ErrorCodes.h; the advice is PS3 Center's own, for the cases that come up
/// with HEN and webMAN.
public enum ConsoleErrorCode {
    public struct Info: Sendable {
        public let code: UInt32
        public let name: String
        public let meaning: String
        public let advice: String?
    }

    static let table: [UInt32: (String, String, String?)] = [
        0x80010001: ("EAGAIN", "Resursen är tillfälligt upptagen.", "Försök igen om en stund."),
        0x80010002: ("EINVAL", "Ett ogiltigt värde skickades.", nil),
        0x80010003: ("ENOSYS", "Funktionen finns inte.", nil),
        0x80010004: ("ENOMEM", "Minnet tog slut.", "Starta om konsolen och försök igen."),
        0x80010005: ("ESRCH", "Det som efterfrågades finns inte.", nil),
        0x80010006: ("ENOENT", "Filen finns inte.", "Kontrollera att spelet är komplett, eller skicka det igen."),
        0x80010007: ("ENOEXEC", "Filen har ett okänt format.", "Ofta en trasig eller ofullständig EBOOT.BIN eller SELF-fil."),
        0x80010008: ("EDEADLK", "Ett dödläge undveks.", nil),
        0x80010009: ("EPERM", "Åtgärden är inte tillåten.", "Är HEN aktiverat? Utan HEN startar inte homebrew."),
        0x8001000A: ("EBUSY", "Enheten eller resursen är upptagen.", "Vänta tills det som körs är klart."),
        0x8001000B: ("ETIMEDOUT", "Tiden tog slut.", nil),
        0x8001000C: ("EABORT", "Åtgärden avbröts.", nil),
        0x8001000D: ("EFAULT", "Ogiltig minnesåtkomst.", nil),
        0x8001000E: ("ENOCHILD", "Processen har inga barnprocesser.", nil),
        0x8001000F: ("ESTAT", "Tråden är i fel tillstånd.", nil),
        0x80010010: ("EALIGN", "Fel justering i minnet.", nil),
        0x80010011: ("EKRESOURCE", "Kärnans resurser räcker inte.", nil),
        0x80010012: ("EISDIR", "Det är en mapp, inte en fil.", nil),
        0x80010013: ("ECANCELED", "Åtgärden avbröts.", nil),
        0x80010014: ("EEXIST", "Det finns redan.", nil),
        0x80010015: ("EISCONN", "Porten är redan ansluten.", nil),
        0x80010016: ("ENOTCONN", "Porten är inte ansluten.", nil),
        0x80010017: ("EAUTHFAIL", "Programmet kunde inte verifieras.", "Programmet är inte signerat för konsolen. Aktivera HEN, eller installera om programmet."),
        0x80010018: ("ENOTMSELF", "Filen är ingen MSELF.", nil),
        0x80010019: ("ESYSVER", "Fel systemversion.", "Spelet eller programmet kräver en annan systemprogramvara än konsolens."),
        0x8001001A: ("EAUTHFATAL", "Allvarligt systemfel vid verifiering.", nil),
        0x8001001B: ("EDOM", "Matematiskt definitionsfel.", nil),
        0x8001001C: ("ERANGE", "Värdet är utanför tillåtet intervall.", nil),
        0x8001001D: ("EILSEQ", "Ogiltig teckensekvens.", nil),
        0x8001001E: ("EFPOS", "Fel position i filen.", nil),
        0x8001001F: ("EINTR", "Anropet avbröts.", nil),
        0x80010020: ("EFBIG", "Filen är för stor.", "FAT32-diskar klarar inte filer över 4 GB; dela ISO:n (ps3 usb prepare)."),
        0x80010021: ("EMLINK", "För många länkar.", nil),
        0x80010022: ("ENFILE", "Filtabellen är full.", nil),
        0x80010023: ("ENOSPC", "Det finns inget utrymme kvar.", "Frigör plats på hårddisken (Underhåll → Lagring)."),
        0x80010024: ("ENOTTY", "Inte en terminal.", nil),
        0x80010025: ("EPIPE", "Anslutningen bröts.", nil),
        0x80010026: ("EROFS", "Filsystemet är skrivskyddat.", nil),
        0x80010027: ("ESPIPE", "Ogiltig sökning i filen.", nil),
        0x80010028: ("E2BIG", "För många argument.", nil),
        0x80010029: ("EACCES", "Åtkomst nekad.", nil),
        0x8001002A: ("EBADF", "Ogiltig filreferens.", nil),
        0x8001002B: ("EIO", "In- eller utmatningsfel.", "Disken eller skivan kan vara trasig, eller filen ofullständig."),
        0x8001002C: ("EMFILE", "För många öppna filer.", nil),
        0x8001002D: ("ENODEV", "Enheten finns inte.", "Är USB-disken ansluten?"),
        0x8001002E: ("ENOTDIR", "Det är ingen mapp.", nil),
        0x8001002F: ("ENXIO", "Enheten finns inte eller svarar inte.", nil),
        0x80010030: ("EXDEV", "Kan inte länka mellan enheter.", nil),
        0x80010031: ("EBADMSG", "Felaktigt meddelande.", nil),
        0x80010032: ("EINPROGRESS", "Pågår redan.", nil),
        0x80010033: ("EMSGSIZE", "Meddelandet har fel storlek.", nil),
        0x80010034: ("ENAMETOOLONG", "Namnet är för långt.", "Korta av fil- eller mappnamnet."),
        0x80010035: ("ENOLCK", "Inget lås tillgängligt.", nil),
        0x80010036: ("ENOTEMPTY", "Mappen är inte tom.", nil),
        0x80010037: ("ENOTSUP", "Stöds inte.", nil),
        0x80010038: ("EFSSPECIFIC", "Fel i filsystemet.", nil),
        0x80010039: ("EOVERFLOW", "Värdet blev för stort.", nil),
        0x8001003A: ("ENOTMOUNTED", "Filsystemet är inte monterat.", "Är disken ansluten och spelet monterat?"),
        0x8001003B: ("ENOTSDATA", "Inte SDATA.", nil),
        0x8001003C: ("ESDKVER", "Fel SDK-version.", "Spelet kräver en nyare systemprogramvara än konsolens."),
        0x8001003D: ("ENOLICDISC", "Licens saknas för skivan.", nil),
        0x8001003E: ("ENOLICENT", "Licens saknas.", nil),
    ]

    public static func info(_ code: UInt32) -> Info? {
        guard let entry = table[code] else { return nil }
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
        let pattern = #"(?:0x)?(8001[0-9A-Fa-f]{4})"#
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

    /// "80010006 (ENOENT): Filen finns inte. Kontrollera …"
    public static func describe(_ info: Info) -> String {
        let hex = String(format: "%08X", info.code)
        return "\(hex) (\(info.name)): \(info.meaning)" + (info.advice.map { " \($0)" } ?? "")
    }
}
