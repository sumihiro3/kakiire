import AppKit
import Carbon.HIToolbox

/// 撮影のグローバルショートカットの候補。自由に記録する UI は作らず、システムと衝突しにくいものから選ばせる。
enum CaptureShortcut: String, CaseIterable {
    case off
    case controlShiftCommand5
    case controlOptionCommandS
    case optionShiftCommand2

    var title: String {
        switch self {
        case .off: String(localized: "使わない")
        case .controlShiftCommand5: "⌃⇧⌘5"
        case .controlOptionCommandS: "⌃⌥⌘S"
        case .optionShiftCommand2: "⌥⇧⌘2"
        }
    }

    /// Carbon のキーコードと修飾キー。
    fileprivate var carbon: (key: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .controlShiftCommand5: (UInt32(kVK_ANSI_5), UInt32(controlKey | shiftKey | cmdKey))
        case .controlOptionCommandS: (UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey | cmdKey))
        case .optionShiftCommand2: (UInt32(kVK_ANSI_2), UInt32(optionKey | shiftKey | cmdKey))
        }
    }
}

/// Carbon の `RegisterEventHotKey` でグローバルショートカットを1つ登録する。
///
/// Sandbox の中でも、アクセシビリティの許可なしに使える(キー入力を監視するのではなく、OS に登録したキーだけが届く)。
@MainActor
final class HotKey {
    static let shared = HotKey()

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    /// `shortcut` を登録し直す。`.off` なら外す。登録できなければ false(他のアプリが使っているなど)。
    @discardableResult
    func register(_ shortcut: CaptureShortcut, action: @escaping () -> Void) -> Bool {
        unregister()
        guard let (key, modifiers) = shortcut.carbon else { return true }
        self.action = action
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4B4B_4945), id: 1) // 'KKIE'
        return RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon のイベントはメインスレッドで届く。
            MainActor.assumeIsolated { HotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
