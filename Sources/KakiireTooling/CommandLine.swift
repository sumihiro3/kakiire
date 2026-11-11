import CoreGraphics
import Foundation

/// `kakiire` のサブコマンド。
public enum CLICommand: Equatable, Sendable {
    case help
    case version
    case info(path: String)
    /// `annotations` はファイルのパス。`-` なら標準入力。`outputs` は `-o` を重ねた順。
    case annotate(input: String, outputs: [String], annotations: String?, crop: CGRect?, scale: Double?, force: Bool)
    case mcp
}

public enum CLI {
    public static let usage = """
    Usage:
      kakiire info <file>
          Print pixel size, crop, output size and annotations as JSON.
      kakiire annotate <input> -o <output> [-o <output>...] [-a <annotations.json|->] [--crop x,y,w,h] [--scale s] [--force]
          Add annotations (document.json format) and write .png / .jpg / .kakiire by extension.
          Repeat -o to write several formats at once.
      kakiire export <file> -o <output> [-o <output>...] [--crop x,y,w,h] [--scale s] [--force]
          Same as annotate without annotations.
      kakiire mcp
          Run as an MCP server over stdio.
      kakiire --version

    Coordinates are image pixels, top-left origin, y down.
    """

    public static func parse(_ args: [String]) throws -> CLICommand {
        guard let sub = args.first else { return .help }
        var rest = Array(args.dropFirst())
        switch sub {
        case "-h", "--help", "help": return .help
        case "-v", "--version", "version": return .version
        case "mcp": return .mcp
        case "info":
            guard rest.count == 1 else { throw ToolError.usage("info takes exactly one file\n\n\(usage)") }
            return .info(path: rest[0])
        case "annotate", "export":
            var input: String?, outputs: [String] = [], annotations: String?, crop: CGRect?, scale: Double?, force = false
            while !rest.isEmpty {
                let a = rest.removeFirst()
                func value() throws -> String {
                    guard !rest.isEmpty else { throw ToolError.usage("\(a) needs a value") }
                    return rest.removeFirst()
                }
                switch a {
                case "-o", "--output": outputs.append(try value())
                case "-a", "--annotations":
                    guard sub == "annotate" else { throw ToolError.usage("export does not take annotations; use annotate") }
                    annotations = try value()
                case "--crop": crop = try parseRect(value())
                case "--scale":
                    let v = try value()
                    guard let s = Double(v), s > 0 else { throw ToolError.usage("--scale must be a positive number: \(v)") }
                    scale = s
                case "--force", "-f": force = true
                default:
                    guard input == nil, !a.hasPrefix("-") || a == "-" else { throw ToolError.usage("unexpected argument: \(a)\n\n\(usage)") }
                    input = a
                }
            }
            guard let input, !outputs.isEmpty else { throw ToolError.usage("\(sub) needs <input> and -o <output>\n\n\(usage)") }
            return .annotate(input: input, outputs: outputs, annotations: annotations, crop: crop, scale: scale, force: force)
        default:
            throw ToolError.usage("unknown command: \(sub)\n\n\(usage)")
        }
    }

    /// `x,y,w,h` を読む。
    public static func parseRect(_ s: String) throws -> CGRect {
        let v = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard v.count == 4, v[2] > 0, v[3] > 0 else { throw ToolError.usage("expected x,y,w,h with positive w and h: \(s)") }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }
}
