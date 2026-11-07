# Kakiire

Skitch 代替の画像注釈アプリ(Swift + AppKit、macOS 15+、Apple Silicon)。仕様の正本は `docs/handoff.md`、計画と進捗は `docs/plan.md`。

## コマンド

```bash
swift test                                   # Core / IO の単体テスト
xcodegen generate                            # project.yml から Kakiire.xcodeproj を生成(xcodeproj はコミットしない)
xcodebuild -project Kakiire.xcodeproj -scheme Kakiire -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Kakiire.app
```

## 層の約束

- App → IO → Core の一方向。Core(`Sources/KakiireCore`)は AppKit を import しない
- 文書は値型 `Document`。App は `EditOperation` を通してだけ変更し、Undo は `KakiireDocument.setContent` がスナップショットを NSUndoManager に積む
- ドラッグ中は `EditSession` の途中結果を表示だけし、マウスを離したときに確定する(Undo 1回分)
- 描画は画面と書き出しで同じ `Renderer`。効果(モザイク・ぼかし)を先、図形を後に描く
- 座標は元画像のピクセル座標(左上原点・y 下向き)
- Core / IO は Swift 6 の厳格な並行性チェック、App は `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

## 注意

- `NSWindowController` の init で `self.document` を自分で設定しない(`addWindowController` が登録しなくなり、ウインドウが出ない)
- 画像は fileURL を持たない無題文書として開く(`KakiireDocumentController.makeDocument`)。元画像の上書きを防ぐため
- PNG 書き出しでは ImageIO が付ける `eXIf` などの補助チャンクを `ImageExport.stripPNGMetadata` で除く
- Sitch(MIT)から流用したファイルは冒頭に出典を書き、`THIRD_PARTY_NOTICES.md` に載せる。GPL の ShareX / Greenshot / Flameshot は写さない
