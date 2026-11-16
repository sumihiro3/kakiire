// 使い方: act <ox> <oy> <命令…>
// 命令: move x y ms | click x y | drag x1 y1 x2 y2 ms | wait ms | esc | return | cmdreturn | type 文字列
// 座標はウインドウの左上 (ox, oy) からの相対。マウスはなめらかに動かす。
import CoreGraphics
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
let ox = Double(args.removeFirst())!, oy = Double(args.removeFirst())!
let src = CGEventSource(stateID: .hidSystemState)
var cur = CGEvent(source: nil)!.location

func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func post(_ t: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func glide(to p: CGPoint, ms: Double, type: CGEventType) {
    let from = cur
    let n = max(1, Int(ms / 8))
    for i in 1...n {
        let t = ease(Double(i) / Double(n))
        post(type, CGPoint(x: from.x + (p.x - from.x) * t, y: from.y + (p.y - from.y) * t))
        usleep(8_000)
    }
    cur = p
}
func pt(_ x: String, _ y: String) -> CGPoint { CGPoint(x: ox + Double(x)!, y: oy + Double(y)!) }
func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}
func typeText(_ s: String) {
    for ch in s.utf16 {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)!
            var c = ch
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e.post(tap: .cghidEventTap)
        }
        usleep(70_000)
    }
}

var i = 0
while i < args.count {
    let op = args[i]
    switch op {
    case "move":
        glide(to: pt(args[i + 1], args[i + 2]), ms: Double(args[i + 3])!, type: .mouseMoved); i += 4
    case "click":
        glide(to: pt(args[i + 1], args[i + 2]), ms: 450, type: .mouseMoved)
        usleep(120_000); post(.leftMouseDown, cur); usleep(80_000); post(.leftMouseUp, cur); i += 3
    case "drag":
        glide(to: pt(args[i + 1], args[i + 2]), ms: 450, type: .mouseMoved)
        usleep(150_000); post(.leftMouseDown, cur); usleep(100_000)
        glide(to: pt(args[i + 3], args[i + 4]), ms: Double(args[i + 5])!, type: .leftMouseDragged)
        usleep(100_000); post(.leftMouseUp, cur); i += 6
    case "wait":
        usleep(useconds_t(Double(args[i + 1])! * 1000)); i += 2
    case "esc": key(53); i += 1
    case "return": key(36); i += 1
    case "cmdreturn": key(36, .maskCommand); i += 1
    case "type": typeText(args[i + 1]); i += 2
    default: fatalError("unknown op \(op)")
    }
}
