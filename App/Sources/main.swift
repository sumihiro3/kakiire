import AppKit

let app = NSApplication.shared
// 最初に生成した NSDocumentController が shared になるので、AppKit より先に作る。
_ = KakiireDocumentController()
let delegate = AppDelegate()
app.delegate = delegate
app.run()
