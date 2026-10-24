import Foundation

/// Cover art for the game webMAN has mounted. A mounted PS3 game (ISO or folder) appears as
/// /dev_bdvd, so its ICON0.PNG (320×176) and PIC1.PNG (the XMB background) can be read over
/// FTP without opening the ISO. PS1, PS2 and PSP images have no PS3_GAME folder and get nil.
public struct GameArt: Sendable {
    public var icon: Data?
    public var background: Data?

    public static func mounted(host: String) async -> GameArt {
        let result = try? await TransferService(host: host).withFTP { ftp -> GameArt in
            let icon = try await ftp.download("/dev_bdvd/PS3_GAME/ICON0.PNG", limit: 2 << 20)
            let background = try await ftp.download("/dev_bdvd/PS3_GAME/PIC1.PNG", limit: 8 << 20)
            return GameArt(icon: icon, background: background)
        }
        return result ?? GameArt()
    }
}
