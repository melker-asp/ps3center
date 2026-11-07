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
    /// PS3 Center will not do it (a running game, an installed game), with the reason.
    case refused(String)
    case gameRunning
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unreachable(let host):
            return "The PS3 is not answering at \(host). Is it on, and is HEN enabled? (Try `ps3 discover` if the IP address has changed.)"
        case .noHost:
            return "No PS3 found on the network. Enable HEN and run `ps3 discover`, or set the address with `ps3 config set host <ip>`."
        case .http(let status, let command):
            return "webMAN answered \(status) to \(command)."
        case .ftp(let code, let message):
            return "FTP error \(code): \(message)"
        case .ftpProtocol(let message):
            return "Unexpected FTP reply: \(message)"
        case .timeout(let what):
            return "Timed out: \(what)"
        case .notEnoughSpace(let needed, let free):
            return "Not enough space on the PS3: needs \(Format.bytes(needed)), \(Format.bytes(free)) free. Use --force to try anyway."
        case .unsupportedFile(let message), .invalidFile(let message), .github(let message), .incompatible(let message),
             .refused(let message):
            return message
        case .gameRunning:
            return "A game or app is running on the PS3."
        case .cancelled:
            return "Cancelled."
        }
    }
}
