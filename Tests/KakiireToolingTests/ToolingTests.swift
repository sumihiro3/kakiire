import CoreGraphics
import Foundation
import ImageIO
import Testing
import KakiireCore
import KakiireIO
@testable import KakiireTooling

enum Fixture {
    static func png(_ w: Int, _ h: Int) throws -> Data {
        let px = [UInt8](repeating: 200, count: w * h * 4)
        let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: CGDataProvider(data: Data(px) as CFData)!, decode: nil,
                          shouldInterpolate: false, intent: .defaultIntent)!
        return try ImageExport.data(img, format: .png)
    }

    static func dir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("kakiire-tooling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func pixelSize(_ data: Data) -> (Int, Int) {
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
        return (img.width, img.height)
    }

    static let annotations = """
    [
      {"type": "arrow", "geometry": {"from": [10, 10], "to": [100, 60]}, "style": {"color": "#E82A2A", "width": 12}},
      {"type": "rect", "name": "box", "geometry": {"rect": [20, 20, 80, 40]}, "style": {"color": "#1E7CF0", "width": 4}},
      {"type": "stamp", "geometry": {"center": [150, 30]}, "style": {"color": "#E82A2A", "diameter": 40}},
      {"type": "stamp", "geometry": {"center": [150, 90]}, "style": {"color": "#E82A2A", "diameter": 40}}
    ]
    """
}

@Suite struct DecodeAnnotationsTests {
    let doc = Document(base: BaseImage(asset: try! ImageImport.asset(from: Fixture.png(200, 120))))

    @Test func readsDocumentJSONShapeWithoutIdsOrNames() throws {
        let a = try KakiireTool.decodeAnnotations(Data(Fixture.annotations.utf8), continuingFrom: doc)
        #expect(a.map(\.content.typeName) == ["arrow", "rect", "stamp", "stamp"])
        #expect(a[0].name == "arrow")
        #expect(a[1].name == "box")
        #expect(Set(a.map(\.id)).count == 4)
    }

    @Test func numbersStampsContinuingFromTheDocument() throws {
        let existing = Annotation(name: "s", content: .stamp(StampSpec(center: .zero, number: 3, color: .red, diameter: 40)))
        var d = doc
        d.annotations = [existing]
        let a = try KakiireTool.decodeAnnotations(Data(Fixture.annotations.utf8), continuingFrom: d)
        let numbers = a.compactMap { if case .stamp(let s) = $0.content { s.number } else { nil } }
        #expect(numbers == [4, 5])
    }

    @Test func explicitStampNumberMovesTheCounter() throws {
        let json = """
        [{"type":"stamp","number":7,"geometry":{"center":[1,1]},"style":{"color":"#E82A2A","diameter":40}},
         {"type":"stamp","geometry":{"center":[1,1]},"style":{"color":"#E82A2A","diameter":40}},
         {"type":"stamp","geometry":{"center":[1,1]},"style":{"color":"#E82A2A","diameter":40,"kind":"letter"}}]
        """
        let a = try KakiireTool.decodeAnnotations(Data(json.utf8), continuingFrom: doc)
        let numbers = a.compactMap { if case .stamp(let s) = $0.content { s.number } else { nil } }
        #expect(numbers == [7, 8, 1])
    }

    @Test func rejectsUnknownType() {
        let json = ##"[{"type":"rectangle","geometry":{"rect":[0,0,1,1]},"style":{"color":"#000000","width":1}}]"##
        #expect(throws: ToolError.self) { try KakiireTool.decodeAnnotations(Data(json.utf8), continuingFrom: doc) }
    }

    @Test func rejectsImageType() {
        let json = ##"[{"type":"image","asset":"assets/x.png","geometry":{"rect":[0,0,1,1]}}]"##
        #expect(throws: ToolError.self) { try KakiireTool.decodeAnnotations(Data(json.utf8), continuingFrom: doc) }
    }

    @Test func reportsMissingKeyReadably() {
        let json = ##"[{"type":"arrow","geometry":{"from":[0,0],"to":[1,1]},"style":{"width":3}}]"##
        do {
            _ = try KakiireTool.decodeAnnotations(Data(json.utf8), continuingFrom: doc)
            Issue.record("should throw")
        } catch {
            #expect(error.localizedDescription.contains("[0] arrow: missing \"color\" in style"))
        }
    }

    @Test func rejectsNonArray() {
        #expect(throws: ToolError.self) { try KakiireTool.decodeAnnotations(Data("{}".utf8), continuingFrom: doc) }
    }
}

@Suite struct AnnotateTests {
    @Test func writesPNGWithCropAndScale() throws {
        let dir = try Fixture.dir()
        let input = dir.appendingPathComponent("in.png"), output = dir.appendingPathComponent("out.png")
        try Fixture.png(200, 120).write(to: input)
        try KakiireTool.annotate(AnnotateRequest(input: input, output: output, annotations: Data(Fixture.annotations.utf8),
                                                 crop: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 0.5))
        let (w, h) = Fixture.pixelSize(try Data(contentsOf: output))
        #expect(w == 50 && h == 50)
    }

    @Test func kakiireRoundTripKeepsAnnotationsAndAddsMore() throws {
        let dir = try Fixture.dir()
        let input = dir.appendingPathComponent("in.png"), first = dir.appendingPathComponent("a.kakiire")
        let second = dir.appendingPathComponent("b.kakiire")
        try Fixture.png(200, 120).write(to: input)
        let written = try KakiireTool.annotate(AnnotateRequest(input: input, output: first, annotations: Data(Fixture.annotations.utf8)))
        let loaded = try KakiireTool.load(first)
        #expect(loaded.document == written)
        #expect(loaded.manifest?.appVersion == KakiireTool.appVersion)

        let more = ##"[{"type":"stamp","geometry":{"center":[10,10]},"style":{"color":"#E82A2A","diameter":40}}]"##
        let doc = try KakiireTool.annotate(AnnotateRequest(input: first, output: second, annotations: Data(more.utf8)))
        #expect(doc.annotations.count == 5)
        if case .stamp(let s) = doc.annotations.last?.content { #expect(s.number == 3) } else { Issue.record("not a stamp") }
        #expect(try KakiireTool.load(second).manifest?.createdAt == loaded.manifest?.createdAt)
    }

    @Test func refusesToOverwriteInputUnlessForced() throws {
        let dir = try Fixture.dir()
        let input = dir.appendingPathComponent("in.png")
        try Fixture.png(20, 20).write(to: input)
        #expect(throws: ToolError.wouldOverwriteInput(input.path)) {
            try KakiireTool.annotate(AnnotateRequest(input: input, output: input))
        }
        try KakiireTool.annotate(AnnotateRequest(input: input, output: input, force: true))
    }

    @Test func rejectsUnknownOutputExtension() throws {
        let dir = try Fixture.dir()
        let input = dir.appendingPathComponent("in.png")
        try Fixture.png(20, 20).write(to: input)
        #expect(throws: ToolError.self) {
            try KakiireTool.annotate(AnnotateRequest(input: input, output: dir.appendingPathComponent("out.gif")))
        }
    }

    @Test func infoReportsOutputSize() throws {
        var doc = Document(base: BaseImage(asset: try ImageImport.asset(from: Fixture.png(200, 120))))
        doc = doc.applying([.setCrop(CGRect(x: 10, y: 10, width: 101, height: 50)), .setOutputScale(0.5)])
        let info = KakiireTool.info(doc)
        #expect(info.width == 200 && info.height == 120)
        #expect(info.crop == [10, 10, 101, 50])
        #expect(info.outputWidth == 51 && info.outputHeight == 25)
    }

    @Test func appVersionMatchesProjectYml() throws {
        let yml = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("project.yml")
        let text = try String(contentsOf: yml, encoding: .utf8)
        #expect(text.contains("MARKETING_VERSION: \"\(KakiireTool.appVersion)\""))
    }
}

@Suite struct CLIParseTests {
    @Test func parsesAnnotate() throws {
        let c = try CLI.parse(["annotate", "in.png", "-o", "out.kakiire", "-a", "-", "--crop", "1,2,3,4", "--scale", "0.5", "--force"])
        #expect(c == .annotate(input: "in.png", output: "out.kakiire", annotations: "-",
                               crop: CGRect(x: 1, y: 2, width: 3, height: 4), scale: 0.5, force: true))
    }

    @Test func exportIsAnnotateWithoutAnnotations() throws {
        #expect(try CLI.parse(["export", "a.kakiire", "-o", "a.png"])
            == .annotate(input: "a.kakiire", output: "a.png", annotations: nil, crop: nil, scale: nil, force: false))
        #expect(throws: ToolError.self) { try CLI.parse(["export", "a.kakiire", "-o", "a.png", "-a", "x.json"]) }
    }

    @Test func rejectsBadArguments() {
        #expect(throws: ToolError.self) { try CLI.parse(["annotate", "in.png"]) }
        #expect(throws: ToolError.self) { try CLI.parse(["annotate", "in.png", "-o", "o.png", "--scale", "-1"]) }
        #expect(throws: ToolError.self) { try CLI.parse(["annotate", "in.png", "-o", "o.png", "--crop", "1,2,3"]) }
        #expect(throws: ToolError.self) { try CLI.parse(["nope"]) }
    }
}

@Suite struct MCPServerTests {
    let server = MCPServer()

    func call(_ obj: [String: Any]) throws -> [String: Any] {
        let line = String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
        let out = try #require(server.handle(line: line))
        return try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    }

    @Test func initializeEchoesKnownVersion() throws {
        let r = try call(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                          "params": ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "t", "version": "1"]]])
        let result = try #require(r["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "kakiire")
        #expect(r["id"] as? Int == 1)
    }

    @Test func initializeFallsBackForUnknownVersion() throws {
        let r = try call(["jsonrpc": "2.0", "id": "a", "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        #expect((r["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.protocolVersions[0])
        #expect(r["id"] as? String == "a")
    }

    @Test func notificationsGetNoResponse() {
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func unknownMethodAndParseError() throws {
        let r = try call(["jsonrpc": "2.0", "id": 2, "method": "resources/list"])
        #expect((r["error"] as? [String: Any])?["code"] as? Int == -32601)
        let p = try #require(server.handle(line: "{not json"))
        #expect(p.contains("-32700"))
    }

    @Test func listsTools() throws {
        let r = try call(["jsonrpc": "2.0", "id": 3, "method": "tools/list"])
        let tools = try #require((r["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["get_image_info", "annotate_image"])
    }

    @Test func annotateImageWritesFileAndReturnsPreview() throws {
        let dir = try Fixture.dir()
        let input = dir.appendingPathComponent("in.png"), output = dir.appendingPathComponent("out.png")
        try Fixture.png(2000, 1000).write(to: input)
        let annotations = try JSONSerialization.jsonObject(with: Data(Fixture.annotations.utf8))
        let r = try call(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": [
            "name": "annotate_image",
            "arguments": ["input": input.path, "output": output.path, "annotations": annotations],
        ]])
        let result = try #require(r["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["text", "text", "image"])
        #expect((content[1]["text"] as? String)?.contains("scaled by 0.5120") == true)
        let png = try #require(Data(base64Encoded: content[2]["data"] as? String ?? ""))
        #expect(Fixture.pixelSize(png) == (1024, 512))
        #expect(Fixture.pixelSize(try Data(contentsOf: output)) == (2000, 1000))
    }

    @Test func toolErrorsAreReportedAsIsError() throws {
        let r = try call(["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": [
            "name": "annotate_image", "arguments": ["input": "relative.png", "output": "/tmp/x.png"],
        ]])
        let result = try #require(r["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String
        #expect(text?.contains("absolute path") == true)
    }

    @Test func getImageInfoReturnsJSON() throws {
        let dir = try Fixture.dir()
        let input = dir.appendingPathComponent("in.png")
        try Fixture.png(30, 20).write(to: input)
        let r = try call(["jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": [
            "name": "get_image_info", "arguments": ["path": input.path, "preview": false],
        ]])
        let content = try #require((r["result"] as? [String: Any])?["content"] as? [[String: Any]])
        #expect(content.count == 1)
        let info = try #require(JSONSerialization.jsonObject(with: Data((content[0]["text"] as? String ?? "").utf8)) as? [String: Any])
        #expect(info["width"] as? Int == 30 && info["height"] as? Int == 20)
    }
}
