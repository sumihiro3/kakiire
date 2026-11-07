import CoreGraphics
import Foundation
import ImageIO
import Testing
import KakiireCore
@testable import KakiireIO

@Suite struct ArchiveTests {
    func document() throws -> Document {
        let base = try ImageImport.asset(from: ImageIOTests.noise(300, 200))
        return Document(base: BaseImage(asset: base), canvas: Canvas(crop: CGRect(x: 10, y: 10, width: 200, height: 150), outputScale: 0.5), annotations: [
            Annotation(name: "矢印 1", content: .arrow(ArrowSpec(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 80), color: .pink, width: 20))),
            Annotation(name: "モザイク 1", locked: true, content: .obscure(ObscureSpec(rect: CGRect(x: 50, y: 50, width: 80, height: 40), mode: .pixelate, strength: 10))),
            Annotation(name: "テキスト 1", hidden: true, content: .text(TextSpec(origin: CGPoint(x: 5, y: 120), text: "メモ\n2行目", color: .blue, fontSize: 24))),
        ])
    }

    let manifest = Manifest(appVersion: "0.2.0", createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: Date(timeIntervalSince1970: 1_800_000_500))

    @Test func roundTripKeepsEverythingEditable() throws {
        let doc = try document()
        let loaded = try KakiireArchive.read(KakiireArchive.write(doc, manifest: manifest))
        #expect(loaded.document == doc)
        #expect(loaded.document.base.asset.data == doc.base.asset.data)
        #expect(loaded.manifest == manifest)
        #expect(!loaded.isReadOnly)
    }

    @Test func layoutMatchesSpec() throws {
        let zip = try ZipReader(KakiireArchive.write(document(), manifest: manifest))
        #expect(zip.entries.map(\.name) == ["manifest.json", "document.json", "base.png", "preview.png"])
        #expect(zip.entry(named: "base.png")?.method == 0)
        #expect(zip.entry(named: "document.json")?.method == 8)

        let preview = try zip.data(for: zip.entry(named: "preview.png")!)
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(preview as CFData, nil)!, 0, nil)!
        // 切り抜き 200×150 を、出力倍率 0.5 ではなく原寸(1024 以下なので)で。
        #expect(img.width == 200 && img.height == 150)
    }

    @Test func previewIsCappedAt1024() throws {
        let big = try ImageImport.asset(from: ImageIOTests.noise(3000, 1500))
        let data = try KakiireArchive.previewPNG(Document(base: BaseImage(asset: big)))
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
        #expect(img.width == 1024 && img.height == 512)
    }

    @Test func reopensAfterFinderStyleExpandAndRecompress() throws {
        let dir = try ZipTests.tempDir()
        let file = dir.appendingPathComponent("example.kakiire")
        let doc = try document()
        try KakiireArchive.write(doc, manifest: manifest).write(to: file)
        let folder = dir.appendingPathComponent("example")
        #expect(try ZipTests.run("/usr/bin/ditto", ["-x", "-k", file.path, folder.path]).status == 0)
        let rezipped = dir.appendingPathComponent("example 2.kakiire")
        #expect(try ZipTests.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, rezipped.path]).status == 0)
        let loaded = try KakiireArchive.read(Data(contentsOf: rezipped))
        #expect(loaded.document == doc)
    }

    @Test func newerFormatOpensReadOnly() throws {
        var m = manifest
        m.formatVersion = KakiireArchive.formatVersion + 1
        let loaded = try KakiireArchive.read(KakiireArchive.write(document(), manifest: m))
        #expect(loaded.isReadOnly)
    }

    @Test func unknownAnnotationSurvivesResave() throws {
        let doc = try document()
        let zip = try ZipReader(KakiireArchive.write(doc, manifest: manifest))
        // document.json に未来の type を足した zip を作る。
        var json = try JSONSerialization.jsonObject(with: zip.data(for: zip.entry(named: "document.json")!)) as! [String: Any]
        var anns = json["annotations"] as! [[String: Any]]
        anns.append(["id": UUID().uuidString, "type": "sticker", "name": "ステッカー 1", "geometry": ["center": [1, 2]], "style": ["number": 7]])
        json["annotations"] = anns
        var w = ZipWriter()
        try w.add("manifest.json", zip.data(for: zip.entry(named: "manifest.json")!), compress: true)
        try w.add("document.json", JSONSerialization.data(withJSONObject: json), compress: true)
        try w.add("base.png", zip.data(for: zip.entry(named: "base.png")!), compress: false)

        let once = try KakiireArchive.read(w.finalize())
        let twice = try KakiireArchive.read(KakiireArchive.write(once.document, manifest: manifest))
        guard case .unknown(let type, let raw) = twice.document.annotations.last?.content else { Issue.record(); return }
        #expect(type == "sticker")
        guard case .object(let o) = raw else { Issue.record(); return }
        #expect(o["style"] == .object(["number": .number(7)]))
    }

    @Test func imageOverlaysAreStoredOnceAsAssets() throws {
        let overlay = try ImageImport.asset(from: ImageIOTests.noise(30, 20))
        var doc = try document()
        doc.annotations += [
            Annotation(name: "画像 1", content: .image(ImageSpec(asset: overlay, rect: CGRect(x: 0, y: 0, width: 30, height: 20)))),
            Annotation(name: "画像 2", hidden: true, content: .image(ImageSpec(asset: overlay, rect: CGRect(x: 40, y: 40, width: 60, height: 40)))),
            Annotation(name: "スタンプ 1", content: .stamp(StampSpec(center: CGPoint(x: 9, y: 9), number: 2, color: .red, diameter: 30))),
            Annotation(name: "ペン 1", content: .pen(StrokeSpec(points: [CGPoint(x: 1, y: 1), CGPoint(x: 8, y: 3)], color: .blue, width: 4))),
        ]
        let data = try KakiireArchive.write(doc, manifest: manifest)
        let zip = try ZipReader(data)
        let path = "assets/\(overlay.sha256).png"
        #expect(zip.entries.filter { $0.name.hasPrefix("assets/") }.map(\.name) == [path])
        #expect(zip.entry(named: path)?.method == 0)
        let loaded = try KakiireArchive.read(data)
        #expect(loaded.document == doc)
        guard case .image(let im) = loaded.document.annotations[3].content else { Issue.record(); return }
        #expect(im.asset.data == overlay.data)
    }

    @Test func overlaysSurviveFinderRecompress() throws {
        let overlay = try ImageImport.asset(from: ImageIOTests.noise(30, 20))
        var doc = try document()
        doc.annotations.append(Annotation(name: "画像 1", content: .image(ImageSpec(asset: overlay, rect: CGRect(x: 0, y: 0, width: 30, height: 20)))))
        let dir = try ZipTests.tempDir()
        let file = dir.appendingPathComponent("o.kakiire")
        try KakiireArchive.write(doc, manifest: manifest).write(to: file)
        let folder = dir.appendingPathComponent("o")
        #expect(try ZipTests.run("/usr/bin/ditto", ["-x", "-k", file.path, folder.path]).status == 0)
        let rezipped = dir.appendingPathComponent("o2.kakiire")
        #expect(try ZipTests.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, rezipped.path]).status == 0)
        #expect(try KakiireArchive.read(Data(contentsOf: rezipped)).document == doc)
    }

    @Test func missingPartsAreReported() throws {
        var w = ZipWriter()
        try w.add("hello.txt", Data("x".utf8), compress: false)
        #expect(throws: KakiireArchiveError.self) { try KakiireArchive.read(w.finalize()) }
    }
}
