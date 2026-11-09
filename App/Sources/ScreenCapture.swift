import AppKit
import KakiireCore
import KakiireIO

/// macOS 標準の `screencapture -i` で範囲(Space でウインドウ)を選んでもらい、撮った画像を返す。
///
/// 範囲選択の操作・Esc での取り消し・画面収録の許可の扱いは OS 標準のものをそのまま使う。
/// 撮る間は自分のウインドウを画面から外し、写り込まないようにする。
/// `NSApp.hide` は使わない。隠すと別のアプリが前面になり、撮影後の `activate()` は前面のアプリが譲らない限り通らない(macOS 14 以降)。
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
        let windows = NSApp.windows.filter { $0.isVisible }
        windows.forEach { $0.orderOut(nil) }
        let restore: @MainActor () -> Void = {
            windows.forEach { $0.orderFront(nil) }
            NSApp.activate()
        }
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                let asset = try? ImageImport.asset(contentsOf: url)
                try? FileManager.default.removeItem(at: url)
                restore()
                completion(asset)
            }
        }
        do {
            try process.run()
        } catch {
            restore()
            NSApp.presentError(error)
            completion(nil)
        }
    }

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private static func explainPermission() {
        let alert = NSAlert()
        alert.messageText = String(localized: "画面収録の許可が必要です")
        alert.informativeText = String(localized: "「システム設定 › プライバシーとセキュリティ › 画面とシステムオーディオの録音」で Kakiire をオンにしてから、もう一度撮ってください。許可したあと Kakiire の再起動を求められることがあります。")
        alert.addButton(withTitle: String(localized: "システム設定を開く"))
        alert.addButton(withTitle: String(localized: "キャンセル"))
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(settingsURL) }
    }
}
