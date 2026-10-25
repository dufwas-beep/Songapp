import Foundation

enum ZipError: LocalizedError {
    case notAZip
    case unsupportedMethod(UInt16)
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notAZip: return "Filen är inget zip-arkiv."
        case .unsupportedMethod: return "Arkivet är packat på ett sätt som inte stöds."
        case .corrupt: return "Arkivet verkar vara skadat."
        }
    }
}

/// Läser filer ur ett zip-arkiv (en OnSong-backup är ett zip-arkiv med ändelsen .backup).
/// Bara innehållsförteckningen läses in; varje fil packas upp först när den behövs.
struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: UInt64
        let localHeaderOffset: UInt64
    }

    let url: URL
    /// Filerna i arkivet, med namnet (normaliserat så att å/ä/ö jämförs rätt) som nyckel.
    private(set) var entries: [String: Entry] = [:]

    init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // Slutet av arkivet: "end of central directory" ligger inom de sista 64 kB.
        let fileSize = try handle.seekToEnd()
        let tailSize = min(fileSize, 65_557)
        try handle.seek(toOffset: fileSize - tailSize)
        let tail = try handle.read(upToCount: Int(tailSize)) ?? Data()
        guard let eocd = tail.lastIndex(ofSignature: 0x0605_4b50) else { throw ZipError.notAZip }

        var count = UInt64(tail.u16(eocd + 10))
        var directorySize = UInt64(tail.u32(eocd + 12))
        var directoryOffset = UInt64(tail.u32(eocd + 16))

        // Stora arkiv (ZIP64) har de riktiga värdena i en egen post.
        if directoryOffset == 0xFFFF_FFFF || count == 0xFFFF, eocd >= 20, tail.u32(eocd - 20) == 0x0706_4b50 {
            let zip64Offset = tail.u64(eocd - 20 + 8)
            try handle.seek(toOffset: zip64Offset)
            let record = try handle.read(upToCount: 56) ?? Data()
            guard record.count == 56, record.u32(0) == 0x0606_4b50 else { throw ZipError.corrupt }
            count = record.u64(32)
            directorySize = record.u64(40)
            directoryOffset = record.u64(48)
        }

        try handle.seek(toOffset: directoryOffset)
        let directory = try handle.read(upToCount: Int(directorySize)) ?? Data()
        var pos = 0
        for _ in 0..<count {
            guard pos + 46 <= directory.count, directory.u32(pos) == 0x0201_4b50 else { throw ZipError.corrupt }
            let flags = directory.u16(pos + 8)
            let method = directory.u16(pos + 10)
            var compressedSize = UInt64(directory.u32(pos + 20))
            var uncompressedSize = UInt64(directory.u32(pos + 24))
            let nameLength = Int(directory.u16(pos + 28))
            let extraLength = Int(directory.u16(pos + 30))
            let commentLength = Int(directory.u16(pos + 32))
            var localOffset = UInt64(directory.u32(pos + 42))
            let nameStart = pos + 46
            guard nameStart + nameLength + extraLength <= directory.count else { throw ZipError.corrupt }
            let nameData = directory.subdata(in: nameStart..<(nameStart + nameLength))

            // ZIP64-tillägg: de värden som är 0xFFFFFFFF står här i stället, i ordning.
            var extra = nameStart + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = directory.u16(extra)
                let size = Int(directory.u16(extra + 2))
                if id == 0x0001 {
                    var field = extra + 4
                    if uncompressedSize == 0xFFFF_FFFF { uncompressedSize = directory.u64(field); field += 8 }
                    if compressedSize == 0xFFFF_FFFF { compressedSize = directory.u64(field); field += 8 }
                    if localOffset == 0xFFFF_FFFF { localOffset = directory.u64(field) }
                }
                extra += 4 + size
            }

            let name = Self.decodeName(nameData, utf8Flag: flags & 0x0800 != 0)
            if !name.hasSuffix("/") {
                entries[name] = Entry(name: name, method: method, compressedSize: compressedSize, localHeaderOffset: localOffset)
            }
            pos = nameStart + nameLength + extraLength + commentLength
        }
    }

    /// Hittar en fil på namnet, även om den ligger i en undermapp i arkivet.
    func entry(named name: String) -> Entry? {
        let key = name.precomposedStringWithCanonicalMapping
        if let entry = entries[key] { return entry }
        let last = (key as NSString).lastPathComponent
        return entries.values.first { ($0.name as NSString).lastPathComponent == last }
    }

    /// Packar upp en fil ur arkivet.
    func data(for entry: Entry) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: entry.localHeaderOffset)
        let header = try handle.read(upToCount: 30) ?? Data()
        guard header.count == 30, header.u32(0) == 0x0403_4b50 else { throw ZipError.corrupt }
        let skip = UInt64(header.u16(26)) + UInt64(header.u16(28))
        try handle.seek(toOffset: entry.localHeaderOffset + 30 + skip)
        let packed = try handle.read(upToCount: Int(entry.compressedSize)) ?? Data()
        switch entry.method {
        case 0:
            return packed
        case 8:
            // Apples "zlib" i Foundation är rå deflate, precis det zip använder.
            return try (packed as NSData).decompressed(using: .zlib) as Data
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    /// Filnamn är UTF-8 (ofta med å/ä/ö som bokstav + ring/prickar) eller äldre kodning.
    private static func decodeName(_ data: Data, utf8Flag: Bool) -> String {
        let name = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return name.precomposedStringWithCanonicalMapping
    }
}

private extension Data {
    func byte(_ i: Int) -> UInt64 {
        UInt64(self[startIndex + i])
    }

    func u16(_ i: Int) -> UInt16 {
        UInt16(byte(i) | byte(i + 1) << 8)
    }

    func u32(_ i: Int) -> UInt32 {
        UInt32(byte(i) | byte(i + 1) << 8 | byte(i + 2) << 16 | byte(i + 3) << 24)
    }

    func u64(_ i: Int) -> UInt64 {
        UInt64(u32(i)) | UInt64(u32(i + 4)) << 32
    }

    func lastIndex(ofSignature signature: UInt32) -> Int? {
        guard count >= 22 else { return nil }
        var i = count - 22
        while i >= 0 {
            if u32(i) == signature { return i }
            i -= 1
        }
        return nil
    }
}
