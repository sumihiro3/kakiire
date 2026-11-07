import Compression
import Foundation
import zlib

public enum ZipError: Error, LocalizedError, Equatable {
    case notAZip
    case unsupported(String)
    case corrupted(String)
    case unsafePath(String)

    public var errorDescription: String? {
        switch self {
        case .notAZip: "zip 形式ではありません。"
        case .unsupported(let s): "対応していない zip です(\(s))。"
        case .corrupted(let s): "ファイルが壊れています(\(s))。"
        case .unsafePath(let s): "不正なパスを含んでいます(\(s))。"
        }
    }
}

/// 最小限の zip 書き込み。stored と deflate のみ、ZIP64 は使わない(1ファイル 4GB 未満)。
public struct ZipWriter {
    private struct Entry {
        let name: Data
        let crc: UInt32
        let method: UInt16
        let compressedSize: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var out = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    public init(date: Date = Date()) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        dosTime = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        dosDate = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
    }

    /// エントリを追加する。`compress` が true でも、縮まなければ stored で格納する。
    public mutating func add(_ name: String, _ data: Data, compress: Bool) throws {
        let nameData = Data(name.utf8)
        guard data.count < Int(UInt32.max), out.count < Int(UInt32.max) else { throw ZipError.unsupported("4GB 以上") }
        let crc = ZipCRC.crc32(data)
        var method: UInt16 = 0
        var body = data
        if compress, let deflated = Deflate.compress(data), deflated.count < data.count {
            method = 8
            body = deflated
        }
        let offset = UInt32(out.count)
        out.appendLE(UInt32(0x0403_4B50))
        out.appendLE(UInt16(20))       // version needed
        out.appendLE(UInt16(0x0800))   // UTF-8 names
        out.appendLE(method)
        out.appendLE(dosTime)
        out.appendLE(dosDate)
        out.appendLE(crc)
        out.appendLE(UInt32(body.count))
        out.appendLE(UInt32(data.count))
        out.appendLE(UInt16(nameData.count))
        out.appendLE(UInt16(0))
        out.append(nameData)
        out.append(body)
        entries.append(Entry(name: nameData, crc: crc, method: method, compressedSize: UInt32(body.count),
                             size: UInt32(data.count), offset: offset))
    }

    /// セントラルディレクトリと終端レコードを付けて zip を完成させる。
    public func finalize() -> Data {
        var d = out
        let cdStart = UInt32(d.count)
        for e in entries {
            d.appendLE(UInt32(0x0201_4B50))
            d.appendLE(UInt16(0x0314))     // made by: Unix, 2.0
            d.appendLE(UInt16(20))
            d.appendLE(UInt16(0x0800))
            d.appendLE(e.method)
            d.appendLE(dosTime)
            d.appendLE(dosDate)
            d.appendLE(e.crc)
            d.appendLE(e.compressedSize)
            d.appendLE(e.size)
            d.appendLE(UInt16(e.name.count))
            d.appendLE(UInt16(0))          // extra
            d.appendLE(UInt16(0))          // comment
            d.appendLE(UInt16(0))          // disk
            d.appendLE(UInt16(0))          // internal attrs
            d.appendLE(UInt32(0o100644) << 16) // 通常ファイル rw-r--r--
            d.appendLE(e.offset)
            d.append(e.name)
        }
        let cdSize = UInt32(d.count) - cdStart
        d.appendLE(UInt32(0x0605_4B50))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(entries.count))
        d.appendLE(UInt16(entries.count))
        d.appendLE(cdSize)
        d.appendLE(cdStart)
        d.appendLE(UInt16(0))
        return d
    }
}

/// 最小限の zip 読み込み。末尾のセントラルディレクトリから読むので、Finder 等で作り直した zip も開ける。
public struct ZipReader {
    public struct Entry {
        public let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let localOffset: Int
    }

    private let bytes: [UInt8]
    /// 意味のあるエントリ(`__MACOSX/`・`._*`・ディレクトリを除く)。
    public let entries: [Entry]

    public init(_ data: Data) throws {
        let b = [UInt8](data)
        bytes = b
        guard b.count >= 22 else { throw ZipError.notAZip }

        // EOCD はコメント(最大 65535 バイト)の手前にある。
        var eocd = -1
        var i = b.count - 22
        let lowest = max(0, b.count - 22 - 65535)
        while i >= lowest {
            if b.u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(b.u16(eocd + 10))
        let cdSize = Int(b.u32(eocd + 12))
        let cdOffset = Int(b.u32(eocd + 16))
        if count == 0xFFFF || cdOffset == 0xFFFF_FFFF || cdSize == 0xFFFF_FFFF { throw ZipError.unsupported("ZIP64") }
        guard cdOffset + cdSize <= eocd else { throw ZipError.corrupted("central directory") }

        var list: [Entry] = []
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= b.count, b.u32(p) == 0x0201_4B50 else { throw ZipError.corrupted("central entry") }
            let flags = b.u16(p + 8)
            let method = b.u16(p + 10)
            let crc = b.u32(p + 16)
            let csize = Int(b.u32(p + 20))
            let size = Int(b.u32(p + 24))
            let nlen = Int(b.u16(p + 28)), xlen = Int(b.u16(p + 30)), clen = Int(b.u16(p + 32))
            let local = Int(b.u32(p + 42))
            guard p + 46 + nlen <= b.count else { throw ZipError.corrupted("name") }
            let nameBytes = Array(b[(p + 46)..<(p + 46 + nlen)])
            let name = String(bytes: nameBytes, encoding: .utf8) ?? String(decoding: nameBytes, as: UTF8.self)
            p += 46 + nlen + xlen + clen

            if Self.isIgnorable(name) { continue }
            try Self.checkPath(name)
            if flags & 0x0001 != 0 { throw ZipError.unsupported("暗号化") }
            if method != 0 && method != 8 { throw ZipError.unsupported("圧縮方式 \(method)") }
            list.append(Entry(name: name, method: method, crc: crc, compressedSize: csize, size: size, localOffset: local))
        }
        entries = list
    }

    static func isIgnorable(_ name: String) -> Bool {
        name.hasPrefix("__MACOSX/") || name.hasSuffix("/") || (name.split(separator: "/").last?.hasPrefix("._") ?? false)
    }

    static func checkPath(_ name: String) throws {
        if name.hasPrefix("/") || name.split(separator: "/").contains("..") { throw ZipError.unsafePath(name) }
    }

    public func entry(named name: String) -> Entry? { entries.first { $0.name == name } }

    /// エントリを展開する。CRC が合わなければエラー。
    public func data(for e: Entry) throws -> Data {
        let b = bytes
        let p = e.localOffset
        guard p + 30 <= b.count, b.u32(p) == 0x0403_4B50 else { throw ZipError.corrupted("local header \(e.name)") }
        // ローカルヘッダの名前・拡張の長さはセントラル側と違うことがあるので、こちらを使う。
        let start = p + 30 + Int(b.u16(p + 26)) + Int(b.u16(p + 28))
        guard start + e.compressedSize <= b.count else { throw ZipError.corrupted("data \(e.name)") }
        let raw = Data(b[start..<(start + e.compressedSize)])
        let out: Data
        if e.method == 0 {
            out = raw
        } else {
            guard let d = Deflate.decompress(raw, size: e.size) else { throw ZipError.corrupted("deflate \(e.name)") }
            out = d
        }
        guard out.count == e.size, ZipCRC.crc32(out) == e.crc else { throw ZipError.corrupted("crc \(e.name)") }
        return out
    }
}

enum ZipCRC {
    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw in
            UInt32(zlib.crc32(0, raw.bindMemory(to: UInt8.self).baseAddress, uInt(raw.count)))
        }
    }
}

/// zip の deflate(方式 8)は zlib ヘッダなしの raw deflate。Compression の ZLIB はちょうどそれを扱う。
enum Deflate {
    static func compress(_ data: Data) -> Data? {
        if data.isEmpty { return nil }
        let capacity = data.count + 1024
        var dst = [UInt8](repeating: 0, count: capacity)
        let n = data.withUnsafeBytes { src in
            compression_encode_buffer(&dst, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return n == 0 ? nil : Data(dst[0..<n])
    }

    static func decompress(_ data: Data, size: Int) -> Data? {
        if size == 0 { return Data() }
        if data.isEmpty { return nil }
        var dst = [UInt8](repeating: 0, count: size)
        let n = data.withUnsafeBytes { src in
            compression_decode_buffer(&dst, size, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return n == size ? Data(dst) : nil
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) }
    }
}

private extension [UInt8] {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
