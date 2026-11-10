import CoreGraphics
import Foundation
import ImageIO
import Testing
import KakiireCore
@testable import KakiireIO

/// Quick Look 拡張が使う、`.kakiire` からのプレビュー取り出し。
@Suite struct PreviewDataTests {
    let archive = ArchiveTests()

    func size(_ png: Data) throws -> (Int, Int) {
        let src = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        return (img.width, img.height)
    }

    @Test func returnsStoredPreview() throws {
        let doc = try archive.document()
        let data = try KakiireArchive.write(doc, manifest: archive.manifest)
        let zip = try ZipReader(data)
        let stored = try zip.data(for: try #require(zip.entry(named: "preview.png")))
        #expect(try KakiireArchive.previewData(data) == stored)
    }

    @Test func findsPreviewAfterFinderRecompress() throws {
        let dir = try ZipTests.tempDir()
        let file = dir.appendingPathComponent("example.kakiire")
        try KakiireArchive.write(archive.document(), manifest: archive.manifest).write(to: file)
        let folder = dir.appendingPathComponent("example")
        #expect(try ZipTests.run("/usr/bin/ditto", ["-x", "-k", file.path, folder.path]).status == 0)
        let rezipped = dir.appendingPathComponent("example 2.kakiire")
        #expect(try ZipTests.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, rezipped.path]).status == 0)
        let png = try KakiireArchive.previewData(Data(contentsOf: rezipped))
        #expect(try size(png) == (200, 150))
    }

    @Test func rendersWhenPreviewIsMissing() throws {
        // preview.png を除いた zip を作る。
        let full = try ZipReader(KakiireArchive.write(archive.document(), manifest: archive.manifest))
        var w = ZipWriter()
        for e in full.entries where e.name != "preview.png" {
            try w.add(e.name, full.data(for: e), compress: false)
        }
        let png = try KakiireArchive.previewData(w.finalize())
        #expect(try size(png) == (200, 150))
    }

    @Test func notAKakiireFileThrows() {
        #expect(throws: (any Error).self) { try KakiireArchive.previewData(Data("hello".utf8)) }
        #expect(throws: (any Error).self) {
            var w = ZipWriter()
            try w.add("hello.txt", Data("x".utf8), compress: false)
            return try KakiireArchive.previewData(w.finalize())
        }
    }
}
