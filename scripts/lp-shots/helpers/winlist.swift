import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Kakiire" {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print(w[kCGWindowNumber as String] ?? "", w[kCGWindowLayer as String] ?? "", w[kCGWindowName as String] ?? "(no name)", b["X"] ?? "", b["Y"] ?? "", b["Width"] ?? "", b["Height"] ?? "")
}
