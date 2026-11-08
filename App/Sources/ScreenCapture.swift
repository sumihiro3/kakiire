import AppKit
import KakiireCore
import KakiireIO

/// macOS 標準の `screencapture -i` で範囲(Space でウインドウ)を選んでもらい、撮った画像を返す。
///
/// 範囲選択の操作・Esc での取り消し・画面収録の許可の扱いは OS 標準のものをそのまま使う。
/// 撮る間は Kakiire を隠し、自分のウインドウが写り込まないようにする。
enum ScreenCapture {
    /// 撮影を始める。取り消し・失敗のときは nil を渡す。完了はメインスレッドで呼ぶ。
    /// 画面収録の許可がなければ、撮らずに許可の入れ方を案内する。
    static func interactive(completion: @escaping @MainActor (ImageAsset?) -> Void) {
        guard CGPreflightScreenCaptureAccess() else {
            // 一度要求すると、システム設定の一覧に Kakiire が載る(ダイアログは OS が出す)。
            CGRequestScreenCaptureAccess()
            explainPermission()
            completion(nil)
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        NSApp.hide(nil)
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                let asset = try? ImageImport.asset(contentsOf: url)
                try? FileManager.default.removeItem(at: url)
                NSApp.unhide(nil)
                NSApp.activate()
                completion(asset)
            }
        }
        do {
            try process.run()
        } catch {
            NSApp.unhide(nil)
            NSApp.presentError(error)
            completion(nil)
        }
    }

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private static func explainPermission() {
        let alert = NSAlert()
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = "「システム設定 › プライバシーとセキュリティ › 画面とシステムオーディオの録音」で Kakiire をオンにしてから、もう一度撮ってください。許可したあと Kakiire の再起動を求められることがあります。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(settingsURL) }
    }
}
