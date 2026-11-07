import Foundation
import Testing
@testable import KakiireIO

@Suite struct ZipTests {
    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kakiire-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (p.terminationStatus, out)
    }

    func sample() throws -> Data {
        var w = ZipWriter()
        try w.add("a.json", Data(String(repeating: "{\"k\": 1}\n", count: 200).utf8), compress: true)
        try w.add("dir/日本語.txt", Data("こんにちは".utf8), compress: true)
        try w.add("empty", Data(), compress: true)
        try w.add("raw.bin", Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 7919) }), compress: false)
        return w.finalize()
    }

    @Test func roundTrip() throws {
        let r = try ZipReader(sample())
        #expect(r.entries.map(\.name) == ["a.json", "dir/日本語.txt", "empty", "raw.bin"])
        #expect(try r.data(for: r.entry(named: "a.json")!) == Data(String(repeating: "{\"k\": 1}\n", count: 200).utf8))
        #expect(try String(decoding: r.data(for: r.entry(named: "dir/日本語.txt")!), as: UTF8.self) == "こんにちは")
        #expect(try r.data(for: r.entry(named: "empty")!).isEmpty)
        #expect(try r.data(for: r.entry(named: "raw.bin")!).count == 5000)
        #expect(r.entry(named: "a.json")?.method == 8)
        #expect(r.entry(named: "raw.bin")?.method == 0)
    }

    @Test func standardToolsAcceptOurZip() throws {
        let dir = try Self.tempDir()
        let file = dir.appendingPathComponent("t.zip")
        try sample().write(to: file)
        let test = try Self.run("/usr/bin/unzip", ["-t", file.path])
        #expect(test.status == 0, "\(test.output)")
        let out = dir.appendingPathComponent("x")
        #expect(try Self.run("/usr/bin/ditto", ["-x", "-k", file.path, out.path]).status == 0)
        #expect(try String(contentsOf: out.appendingPathComponent("dir/日本語.txt"), encoding: .utf8) == "こんにちは")
    }

    @Test func readsDittoArchiveWithResourceForks() throws {
        let dir = try Self.tempDir()
        let folder = dir.appendingPathComponent("pkg")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: folder.appendingPathComponent("a.txt"))
        let zip = dir.appendingPathComponent("pkg.zip")
        #expect(try Self.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, zip.path]).status == 0)
        let r = try ZipReader(Data(contentsOf: zip))
        #expect(r.entries.map(\.name) == ["pkg/a.txt"])
        #expect(try r.data(for: r.entries[0]) == Data("hello".utf8))
    }

    @Test func rejectsGarbageAndTraversal() throws {
        #expect(throws: ZipError.notAZip) { try ZipReader(Data(repeating: 0, count: 100)) }
        var w = ZipWriter()
        try w.add("../evil", Data("x".utf8), compress: false)
        #expect(throws: ZipError.unsafePath("../evil")) { try ZipReader(w.finalize()) }
    }

    @Test func detectsCorruption() throws {
        var d = try sample()
        // raw.bin の中身(stored)を1バイト書き換える。
        let r = try ZipReader(d)
        let e = r.entry(named: "raw.bin")!
        let at = e.localOffset + 30 + "raw.bin".utf8.count + 10
        d[at] ^= 0xFF
        let broken = try ZipReader(d)
        #expect(throws: ZipError.corrupted("crc raw.bin")) { try broken.data(for: broken.entry(named: "raw.bin")!) }
    }
}
