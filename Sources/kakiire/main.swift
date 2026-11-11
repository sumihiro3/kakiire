import Foundation
import KakiireTooling

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func url(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

do {
    switch try CLI.parse(Array(CommandLine.arguments.dropFirst())) {
    case .help:
        print(CLI.usage)
    case .version:
        print(KakiireTool.appVersion)
    case .info(let path):
        print(try KakiireTool.infoJSON(KakiireTool.load(url(path)).document))
    case .annotate(let input, let outputs, let annotations, let crop, let scale, let force):
        let json: Data? = try annotations.map {
            $0 == "-" ? FileHandle.standardInput.readDataToEndOfFile() : try Data(contentsOf: url($0))
        }
        let doc = try KakiireTool.annotate(AnnotateRequest(
            input: url(input), outputs: outputs.map(url), annotations: json, crop: crop, scale: scale, force: force))
        let info = KakiireTool.info(doc)
        for output in outputs {
            FileHandle.standardError.write(Data("Wrote \(output) (\(info.outputWidth)x\(info.outputHeight) px, \(doc.annotations.count) annotations)\n".utf8))
        }
    case .mcp:
        // stdout は JSON-RPC だけに使う。ログは stderr へ。
        let server = MCPServer()
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = server.handle(line: line) {
                FileHandle.standardOutput.write(Data((response + "\n").utf8))
            }
        }
    }
} catch let e as ToolError {
    fail(e.localizedDescription, code: 2)
} catch {
    fail(error.localizedDescription)
}
