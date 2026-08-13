import Foundation
import Compression


struct ZipEntry {
    var path: String
    var data: Data
}

enum ZipArchive {
    static func create(entries: [ZipEntry]) throws -> Data {
        var central: [Data] = []
        var output = Data()
        var localHeaderOffset: UInt32 = 0
        for entry in entries {
            let nameData = entry.path.data(using: .utf8) ?? Data(entry.path.utf8)
            guard nameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max) else { throw ZipError.tooLarge }
            let crc = CRC32.compute(entry.data)
            let packed = compressRawDeflate(entry.data)
            let compressed = packed.data
            let method = packed.method
            var localHeader = Data()
            var lh = Data()
            lh.appendUInt32(0x04034b50)
            lh.appendUInt16(20)
            lh.appendUInt16(0)
            lh.appendUInt16(method)
            lh.appendUInt16(0)
            lh.appendUInt16(0)
            lh.appendUInt32(crc)
            lh.appendUInt32(UInt32(compressed.count))
            lh.appendUInt32(UInt32(entry.data.count))
            lh.appendUInt16(UInt16(nameData.count))
            lh.appendUInt16(0)
            localHeader.append(lh)
            localHeader.append(nameData)
            localHeader.append(compressed)
            output.append(localHeader)

            var centralData = Data()
            var ch = Data()
            ch.appendUInt32(0x02014b50)
            ch.appendUInt16(20)
            ch.appendUInt16(20)
            ch.appendUInt16(0)
            ch.appendUInt16(method)
            ch.appendUInt16(0)
            ch.appendUInt16(0)
            ch.appendUInt32(crc)
            ch.appendUInt32(UInt32(compressed.count))
            ch.appendUInt32(UInt32(entry.data.count))
            ch.appendUInt16(UInt16(nameData.count))
            ch.appendUInt16(0)
            ch.appendUInt16(0)
            ch.appendUInt16(0)
            ch.appendUInt16(0)
            ch.appendUInt32(0)
            ch.appendUInt32(localHeaderOffset)
            centralData.append(ch)
            centralData.append(nameData)
            central.append(centralData)
            localHeaderOffset += UInt32(localHeader.count)
        }
        let centralStart = UInt32(output.count)
        for c in central {
            output.append(c)
        }
        let centralEnd = UInt32(output.count)
        var eocd = Data()
        eocd.appendUInt32(0x06054b50)
        eocd.appendUInt16(0)
        eocd.appendUInt16(0)
        eocd.appendUInt16(UInt16(central.count))
        eocd.appendUInt16(UInt16(central.count))
        eocd.appendUInt32(centralEnd - centralStart)
        eocd.appendUInt32(centralStart)
        eocd.appendUInt16(0)
        output.append(eocd)
        return output
    }

    static func extract(_ data: Data) throws -> [String: Data] {
        var entries: [String: Data] = [:]
        let eocd = try findEOCD(data)
        let centralStart = Int(eocd.centralStart)
        let centralCount = Int(eocd.centralCount)
        var offset = centralStart
        for _ in 0..<centralCount {
            guard offset + 46 <= data.count else { throw ZipError.invalid }
            let sig = data.readUInt32(at: offset)
            guard sig == 0x02014b50 else { throw ZipError.invalid }
            let method = Int(data.readUInt16(at: offset + 10))
            let expectedCrc = data.readUInt32(at: offset + 16)
            let compSize = Int(data.readUInt32(at: offset + 20))
            let uncompSize = Int(data.readUInt32(at: offset + 24))
            let nameLen = Int(data.readUInt16(at: offset + 28))
            let extraLen = Int(data.readUInt16(at: offset + 30))
            let commentLen = Int(data.readUInt16(at: offset + 32))
            let localOffset = Int(data.readUInt32(at: offset + 42))
            guard offset + 46 + nameLen + extraLen + commentLen <= data.count else { throw ZipError.invalid }
            let name = String(data: data.subdata(in: (offset + 46)..<(offset + 46 + nameLen)), encoding: .utf8) ?? ""
            offset += 46 + nameLen + extraLen + commentLen

            guard localOffset + 30 <= data.count else { throw ZipError.invalid }
            let lSig = data.readUInt32(at: localOffset)
            guard lSig == 0x04034b50 else { throw ZipError.invalid }
            let lNameLen = Int(data.readUInt16(at: localOffset + 26))
            let lExtraLen = Int(data.readUInt16(at: localOffset + 28))
            let dataStart = localOffset + 30 + lNameLen + lExtraLen
            guard dataStart + compSize <= data.count else { throw ZipError.invalid }
            let raw = data.subdata(in: dataStart..<(dataStart + compSize))

            let result: Data
            if method == 0 {
                result = raw
            } else if method == 8 {
                result = try decompressDeflate(raw, expectedSize: uncompSize)
            } else {
                throw ZipError.unsupportedMethod
            }
            guard result.count == uncompSize else { throw ZipError.invalid }
            guard CRC32.compute(result) == expectedCrc else { throw ZipError.checksumMismatch }
            entries[name] = result
        }
        return entries
    }

    private static func findEOCD(_ data: Data) throws -> (centralStart: UInt32, centralCount: UInt16) {
        let minOffset = max(0, data.count - 22 - 65535)
        guard data.count >= 22 else { throw ZipError.invalid }
        for i in stride(from: data.count - 22, through: minOffset, by: -1) {
            if data.readUInt32(at: i) == 0x06054b50 {
                let count = data.readUInt16(at: i + 10)
                let start = data.readUInt32(at: i + 16)
                return (start, count)
            }
        }
        throw ZipError.invalid
    }

    // MARK: - Raw deflate (PKZIP method 8，与 ArkTS/标准 unzip 互通)

    /// 标准 zip method 8 数据流：raw deflate。
    /// 实测 Apple Compression 框架的 COMPRESSION_ZLIB 输出本身就是 raw deflate（无 zlib 头），
    /// 直接写入即为标准 zip 流，任何标准解压器（python / ArkTS / 系统工具）均可读取；
    /// 压缩失败时退回 method 0（store）。
    private static func compressRawDeflate(_ data: Data) -> (data: Data, method: UInt16) {
        guard !data.isEmpty else { return (Data(), 0) }
        let srcSize = data.count
        let dstCapacity = srcSize + srcSize / 8 + 1024
        var dst = Data(count: dstCapacity)
        let encoded: Int = dst.withUnsafeMutableBytes { dstPtr in
            data.withUnsafeBytes { srcPtr in
                compression_encode_buffer(dstPtr.bindMemory(to: UInt8.self).baseAddress!, dstCapacity,
                                          srcPtr.bindMemory(to: UInt8.self).baseAddress!, srcSize,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard encoded > 0, encoded < data.count else { return (data, 0) }
        return (dst.subdata(in: 0..<encoded), 8)
    }

    /// 解压 method 8 数据流：Compression 框架原生解 raw deflate；
    /// 失败且带 zlib 头时剥掉 2 字节头 + 4 字节 adler32 尾重试（兼容 zlib 包装流）。
    private static func decompressDeflate(_ raw: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        if let decoded = decodeCompression(raw, expectedSize: expectedSize) {
            return decoded
        }
        let isZlibWrapped = raw.count >= 6 && (raw[raw.startIndex] & 0x0F) == 0x08 &&
            ((UInt32(raw[raw.startIndex]) << 8) | UInt32(raw[raw.startIndex + 1])) % 31 == 0
        if isZlibWrapped {
            var stripped = raw
            stripped.removeFirst(2)
            stripped.removeLast(4)
            if let decoded = decodeCompression(stripped, expectedSize: expectedSize) {
                return decoded
            }
        }
        throw ZipError.invalid
    }

    private static func decodeCompression(_ raw: Data, expectedSize: Int) -> Data? {
        var output = Data(count: expectedSize)
        let decoded: Int = output.withUnsafeMutableBytes { dstPtr in
            raw.withUnsafeBytes { srcPtr in
                compression_decode_buffer(dstPtr.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                                          srcPtr.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard decoded == expectedSize else { return nil }
        return output
    }
}

enum ZipError: Error {
    case invalid
    case unsupportedMethod
    case tooLarge
    case checksumMismatch
}

enum CRC32 {
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 == 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }

    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8) |
               (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }
}
