import AppKit
import KakiireCore

/// メニューバー。nib を使わずコードで組む。
///
/// 修飾キーなしのショートカット(ツール切替・削除)はメニューに登録しない。登録すると文字入力中のキーを横取りするため、
/// キャンバスの keyDown で扱う。
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(imageMenu()))
        main.addItem(submenu(toolMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(windowMenu()))
        return main
    }

    static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.tag = tag
        return i
    }

    private static func appMenu() -> NSMenu {
        let m = NSMenu(title: "Kakiire")
        m.addItem(item(String(localized: "Kakiire について"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        m.addItem(.separator())
        m.addItem(item(String(localized: "設定…"), #selector(AppDelegate.showSettings(_:)), ","))
        m.addItem(.separator())
        m.addItem(item(String(localized: "Kakiire を隠す"), #selector(NSApplication.hide(_:)), "h"))
        m.addItem(item(String(localized: "ほかを隠す"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        m.addItem(item(String(localized: "すべてを表示"), #selector(NSApplication.unhideAllApplications(_:))))
        m.addItem(.separator())
        m.addItem(item(String(localized: "Kakiire を終了"), #selector(NSApplication.terminate(_:)), "q"))
        return m
    }

    private static func fileMenu() -> NSMenu {
        let m = NSMenu(title: String(localized: "ファイル"))
        m.addItem(item(String(localized: "開く…"), #selector(NSDocumentController.openDocument(_:)), "o"))
        m.addItem(item(String(localized: "クリップボードから新規"), #selector(AppDelegate.newFromClipboard(_:)), "n", [.command, .shift]))
        m.addItem(item(String(localized: "スクリーンショットから新規"), #selector(AppDelegate.newFromScreenshot(_:)), "n", [.command, .shift, .control]))
        // 「最近使った項目を開く」は NSDocumentController が「開く…」の下に自動で足す(自前で作ると二重になる)。
        m.addItem(.separator())
        m.addItem(item(String(localized: "閉じる"), #selector(NSWindow.performClose(_:)), "w"))
        m.addItem(item(String(localized: "保存…"), #selector(NSDocument.save(_:)), "s"))
        m.addItem(item(String(localized: "複製"), #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        m.addItem(item(String(localized: "名称変更…"), #selector(NSDocument.rename(_:))))
        m.addItem(item(String(localized: "移動…"), #selector(NSDocument.move(_:))))
        m.addItem(item(String(localized: "戻す"), #selector(NSDocument.revertToSaved(_:))))
        m.addItem(.separator())
        m.addItem(item(String(localized: "書き出す…"), #selector(EditorWindowController.exportImage(_:)), "e", [.command, .shift]))
        return m
    }

    private static func editMenu() -> NSMenu {
        let m = NSMenu(title: String(localized: "編集"))
        m.addItem(item(String(localized: "取り消す"), Selector(("undo:")), "z"))
        m.addItem(item(String(localized: "やり直す"), Selector(("redo:")), "z", [.command, .shift]))
        m.addItem(.separator())
        m.addItem(item(String(localized: "カット"), #selector(NSText.cut(_:)), "x"))
        m.addItem(item(String(localized: "コピー"), #selector(NSText.copy(_:)), "c"))
        m.addItem(item(String(localized: "画像をコピー"), #selector(EditorWindowController.copyImage(_:)), "c", [.command, .shift]))
        m.addItem(item(String(localized: "ペースト"), #selector(NSText.paste(_:)), "v"))
        m.addItem(item(String(localized: "削除"), #selector(NSText.delete(_:))))
        m.addItem(item(String(localized: "すべてを選択"), #selector(NSText.selectAll(_:)), "a"))
        m.addItem(item(String(localized: "注釈を複製"), #selector(EditorWindowController.duplicateAnnotations(_:)), "d"))
        m.addItem(.separator())
        m.addItem(item(String(localized: "最前面へ"), #selector(EditorWindowController.bringToFront(_:)), "]", [.command, .shift]))
        m.addItem(item(String(localized: "最背面へ"), #selector(EditorWindowController.sendToBack(_:)), "[", [.command, .shift]))
        m.addItem(submenu(arrangeMenu()))
        return m
    }

    /// 整列・等間隔配置。tag は `Alignment` / `Distribution` の rawValue。
    static func arrangeMenu() -> NSMenu {
        let m = NSMenu(title: String(localized: "整列"))
        let align: [(String, Alignment)] = [
            (String(localized: "左揃え"), .left), (String(localized: "左右中央揃え"), .centerX), (String(localized: "右揃え"), .right),
            (String(localized: "上揃え"), .top), (String(localized: "上下中央揃え"), .centerY), (String(localized: "下揃え"), .bottom),
        ]
        for (i, (title, a)) in align.enumerated() {
            if i == 3 { m.addItem(.separator()) }
            m.addItem(item(title, #selector(EditorWindowController.alignSelection(_:)), tag: a.rawValue))
        }
        m.addItem(.separator())
        m.addItem(item(String(localized: "左右に等間隔で配置"), #selector(EditorWindowController.distributeSelection(_:)), tag: Distribution.horizontal.rawValue))
        m.addItem(item(String(localized: "上下に等間隔で配置"), #selector(EditorWindowController.distributeSelection(_:)), tag: Distribution.vertical.rawValue))
        return m
    }

    private static func imageMenu() -> NSMenu {
        let m = NSMenu(title: String(localized: "画像"))
        m.addItem(item(String(localized: "左に回転"), #selector(EditorWindowController.rotateLeft(_:)), "l"))
        m.addItem(item(String(localized: "右に回転"), #selector(EditorWindowController.rotateRight(_:)), "r"))
        m.addItem(item(String(localized: "左右反転"), #selector(EditorWindowController.flipHorizontal(_:))))
        m.addItem(item(String(localized: "上下反転"), #selector(EditorWindowController.flipVertical(_:))))
        m.addItem(.separator())
        m.addItem(item(String(localized: "切り抜く…"), #selector(EditorWindowController.startCrop(_:)), "k"))
        m.addItem(item(String(localized: "切り抜きの範囲を指定…"), #selector(EditorWindowController.showCropSize(_:)), "k", [.command, .option]))
        m.addItem(item(String(localized: "切り抜きを確定"), #selector(EditorWindowController.applyCrop(_:))))
        m.addItem(item(String(localized: "切り抜きを解除"), #selector(EditorWindowController.clearCrop(_:))))
        m.addItem(item(String(localized: "画像サイズ…"), #selector(EditorWindowController.showImageSize(_:)), "i", [.command, .option]))
        m.addItem(.separator())
        m.addItem(item(String(localized: "元画像をクリップボードの画像で置き換え"), #selector(EditorWindowController.replaceBaseFromClipboard(_:))))
        m.addItem(.separator())
        let insert = NSMenu(title: String(localized: "画像を挿入"))
        insert.addItem(item(String(localized: "ファイルから…"), #selector(EditorWindowController.insertImageFromFile(_:)), "i", [.command, .shift]))
        insert.addItem(item(String(localized: "スクリーンショットから…"), #selector(EditorWindowController.insertScreenshot(_:))))
        m.addItem(submenu(insert))
        return m
    }

    private static func toolMenu() -> NSMenu {
        let m = NSMenu(title: String(localized: "ツール"))
        for tool in Tool.allCases {
            let i = item("\(tool.title)  (\(tool.key.uppercased()))", #selector(EditorWindowController.selectToolFromMenu(_:)), tag: tool.rawValue)
            m.addItem(i)
        }
        m.addItem(.separator())
        m.addItem(item(String(localized: "文字を大きく"), #selector(EditorWindowController.biggerText(_:)), "+", [.command, .option]))
        m.addItem(item(String(localized: "文字を小さく"), #selector(EditorWindowController.smallerText(_:)), "-", [.command, .option]))
        return m
    }

    private static func viewMenu() -> NSMenu {
        let m = NSMenu(title: String(localized: "表示"))
        m.addItem(item(String(localized: "拡大"), #selector(EditorWindowController.zoomIn(_:)), "+"))
        m.addItem(item(String(localized: "縮小"), #selector(EditorWindowController.zoomOut(_:)), "-"))
        m.addItem(item(String(localized: "実寸"), #selector(EditorWindowController.zoomActual(_:)), "0"))
        m.addItem(item(String(localized: "ウインドウに合わせる"), #selector(EditorWindowController.zoomFit(_:)), "9"))
        m.addItem(.separator())
        m.addItem(item(String(localized: "グリッドを表示"), #selector(EditorWindowController.toggleGrid(_:)), "g", [.control, .command]))
        m.addItem(item(String(localized: "レイヤーを隠す"), #selector(EditorWindowController.toggleLayerPanel(_:)), "l", [.command, .option]))
        return m
    }

    private static func windowMenu() -> NSMenu {
        let m = NSMenu(title: String(localized: "ウインドウ"))
        m.addItem(item(String(localized: "しまう"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        m.addItem(item(String(localized: "拡大/縮小"), #selector(NSWindow.performZoom(_:))))
        m.addItem(.separator())
        m.addItem(item(String(localized: "すべてを手前に移動"), #selector(NSApplication.arrangeInFront(_:))))
        return m
    }
}
