import Foundation

/// Skriver ett enkelt zip-arkiv (okomprimerat) direkt till fil, en fil i taget, så att
/// även stora bibliotek inte behöver ligga i minnet. Läses med `ZipArchive`.
final class ZipWriter {
    private let handle: FileHandle
    private var central = Data()
    private var count: UInt16 = 0
    private var offset: UInt32 = 0

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func add(name: String, data: Data) throws {
        let nameData = Data(name.utf8)
        let crc = CRC32.checksum(data)
        let size = UInt32(data.count)
        var local = Data()
        local.append(le32: 0x0403_4b50)
        local.append(le16: 20)          // version
        local.append(le16: 0x0800)      // UTF-8-namn
        local.append(le16: 0)           // okomprimerat
        local.append(le16: 0); local.append(le16: 0)
        local.append(le32: crc)
        local.append(le32: size); local.append(le32: size)
        local.append(le16: UInt16(nameData.count)); local.append(le16: 0)
        local.append(nameData)
        try handle.write(contentsOf: local)
        try handle.write(contentsOf: data)

        central.append(le32: 0x0201_4b50)
        central.append(le16: 20); central.append(le16: 20)
        central.append(le16: 0x0800); central.append(le16: 0)
        central.append(le16: 0); central.append(le16: 0)
        central.append(le32: crc)
        central.append(le32: size); central.append(le32: size)
        central.append(le16: UInt16(nameData.count))
        central.append(le16: 0); central.append(le16: 0); central.append(le16: 0); central.append(le16: 0)
        central.append(le32: 0)
        central.append(le32: offset)
        central.append(nameData)

        offset += UInt32(local.count) + size
        count += 1
    }

    func finish() throws {
        var end = Data()
        end.append(le32: 0x0605_4b50)
        end.append(le16: 0); end.append(le16: 0)
        end.append(le16: count); end.append(le16: count)
        end.append(le32: UInt32(central.count))
        end.append(le32: offset)
        end.append(le16: 0)
        try handle.write(contentsOf: central)
        try handle.write(contentsOf: end)
        try handle.close()
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
