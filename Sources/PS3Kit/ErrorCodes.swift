import Foundation

/// The console's error codes, in Swedish. The system codes (0x8001xxxx) and their names come from
/// RPCS3's rpcs3/Emu/Cell/ErrorCodes.h. The XMB's own codes for discs, Blu-ray, video, the network
/// and the account (`xmbTable`) are the ones ps3.world/error-codes lists as common, with the
/// meaning checked there (Nov 2026). The advice is PS3 Center's own, for HEN and webMAN.
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
        0x8001003D: ("ENOLICDISC", "Spelet vill ha sin skiva i spelaren.",
                     "Sätt i skivan. För en kopia: montera spelet i webMAN först och starta det sedan."),
        0x8001003E: ("ENOLICENT", "Licens saknas, oftast för att skivan inte sitter i.",
                     "Sätt i skivan, eller montera kopian i webMAN innan spelet startas."),
    ]

    /// The XMB's codes outside 0x8001xxxx that come up most, with a short tag in place of a name.
    static let xmbTable: [UInt32: (String, String, String?)] = [
        0x8001050B: ("SKIVA", "Ett spel eller en demo på hårddisken startar inte med en skiva i spelaren.",
                     "Mata ut skivan och starta om konsolen."),
        0x80010514: ("SKIVA", "Skivan går inte att läsa.",
                     "Rengör skivan och prova en annan. Går ingen skiva att läsa är Blu-ray-läsaren trasig; spel från hårddisken fungerar ändå."),
        0x80010516: ("SKIVA", "Skivan går inte att ladda.", "Sätt i den igen eller rengör den."),
        0x8002291A: ("BLU-RAY", "Blu-ray-skivan går inte att läsa.", "Rengör skivan. Läser ingen skiva behöver läsaren lagas."),
        0x80029906: ("BLU-RAY", "En hembränd BD-R godtas inte som skiva.", "Bränn den igen med ett aktuellt program, t.ex. ImgBurn."),
        0x8002990C: ("VIDEO", "Konsolen kan inte spela den här sortens video.", "Konvertera filen till MP4 (H.264)."),
        0x8002990D: ("VIDEO", "Videon eller skivan går inte att spela.", "Rengör skivan. Är det en fil spelar MP4 (H.264) bäst."),
        0x80710102: ("NÄTVERK", "Ingen DNS-server svarar, eller två enheter har samma IP-adress.",
                     "Starta om routern och ange DNS själv (1.1.1.1). Har PS3:an en fast adress, kontrollera att ingen annan enhet har den."),
        0x80029519: ("KONTO", "Kontot kan inte aktiveras, och köpta PSN-spel slutar fungera.",
                     "Vanligt efter HEN, en avaktivering eller byte av firmware. PS3 Center ändrar inget här: köpta spel behöver kontots aktivering."),
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

    /// "80010006 (ENOENT): Filen finns inte. Kontrollera …"
    public static func describe(_ info: Info) -> String {
        let hex = String(format: "%08X", info.code)
        return "\(hex) (\(info.name)): \(info.meaning)" + (info.advice.map { " \($0)" } ?? "")
    }
}
