import Foundation

/// PARAM.SFO: the key/value table every PS3 title and homebrew app carries.
public struct ParamSFO: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case string(String)
        case int(UInt32)
    }

    public let values: [String: Value]

    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 20, bytes[0] == 0, bytes[1] == 0x50, bytes[2] == 0x53, bytes[3] == 0x46 else { return nil }
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let keyTable = u32(8), dataTable = u32(12), count = u32(16)
        var values: [String: Value] = [:]
        for i in 0..<count {
            let entry = 20 + i * 16
            guard entry + 16 <= bytes.count else { return nil }
            let keyOffset = keyTable + u16(entry)
            let format = u16(entry + 2)
            let length = u32(entry + 4)
            let dataOffset = dataTable + u32(entry + 12)
            guard keyOffset < bytes.count, dataOffset + length <= bytes.count,
                  let keyEnd = bytes[keyOffset...].firstIndex(of: 0) else { return nil }
            let key = String(decoding: bytes[keyOffset..<keyEnd], as: UTF8.self)
            let raw = bytes[dataOffset..<(dataOffset + length)]
            if format == 0x0404, length >= 4 {
                values[key] = .int(UInt32(raw[raw.startIndex]) | UInt32(raw[raw.startIndex + 1]) << 8
                                   | UInt32(raw[raw.startIndex + 2]) << 16 | UInt32(raw[raw.startIndex + 3]) << 24)
            } else {
                let trimmed = raw.prefix { $0 != 0 }
                values[key] = .string(String(decoding: trimmed, as: UTF8.self))
            }
        }
        self.values = values
    }

    /// A minimal PARAM.SFO with string values (fixtures and tests).
    package static func encode(_ values: [String: String]) -> Data {
        let keys = values.keys.sorted()
        var keyTable = Data()
        var dataTable = Data()
        var index = Data()
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func le32(_ v: Int) -> Data { le16(v & 0xFFFF) + le16(v >> 16) }
        for key in keys {
            let value = Data(values[key]!.utf8) + Data([0])
            index += le16(keyTable.count) + le16(0x0204) + le32(value.count) + le32(value.count) + le32(dataTable.count)
            keyTable += Data(key.utf8) + Data([0])
            dataTable += value
        }
        let keyStart = 20 + index.count
        let dataStart = keyStart + keyTable.count
        var header = Data([0x00, 0x50, 0x53, 0x46]) + le32(0x101)
        header += le32(keyStart) + le32(dataStart) + le32(keys.count)
        return header + index + keyTable + dataTable
    }

    public func string(_ key: String) -> String? {
        if case .string(let s) = values[key], !s.isEmpty { return s }
        return nil
    }

    public var titleID: String? { string("TITLE_ID") }
    public var title: String? { string("TITLE")?.replacingOccurrences(of: "\n", with: " ") }
    public var category: String? { string("CATEGORY") }
    /// Installed version: APP_VER when present (games/updates), else VERSION.
    public var appVersion: String? { string("APP_VER") ?? string("VERSION") }
}
