import Foundation

public enum PS3Error: LocalizedError, Equatable {
    case unreachable(host: String)
    case noHost
    case http(status: Int, command: String)
    case ftp(code: Int, message: String)
    case ftpProtocol(String)
    case timeout(String)
    case notEnoughSpace(needed: Int64, free: Int64)
    case unsupportedFile(String)
    case invalidFile(String)
    case github(String)
    case incompatible(String)
    case gameRunning
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unreachable(let host):
            return "PS3:an svarar inte på \(host). Är den på och är HEN aktiverat? (Prova `ps3 discover` om IP-adressen har ändrats.)"
        case .noHost:
            return "Ingen PS3 hittades på nätverket. Aktivera HEN och kör `ps3 discover`, eller ange adressen med `ps3 config set host <ip>`."
        case .http(let status, let command):
            return "webMAN svarade \(status) på \(command)."
        case .ftp(let code, let message):
            return "FTP-fel \(code): \(message)"
        case .ftpProtocol(let message):
            return "Oväntat FTP-svar: \(message)"
        case .timeout(let what):
            return "Tidsgränsen gick ut: \(what)"
        case .notEnoughSpace(let needed, let free):
            return "Inte tillräckligt med plats på PS3:an: behöver \(Format.bytes(needed)), ledigt \(Format.bytes(free)). Använd --force för att försöka ändå."
        case .unsupportedFile(let message), .invalidFile(let message), .github(let message), .incompatible(let message):
            return message
        case .gameRunning:
            return "Ett spel eller program körs på PS3:an."
        case .cancelled:
            return "Avbrutet."
        }
    }
}
