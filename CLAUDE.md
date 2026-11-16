# Kakiire

Skitch 代替の画像注釈アプリ(Swift + AppKit、macOS 15+、Apple Silicon)。仕様の正本は `docs/handoff.md`、計画と進捗は `docs/plan.md`。

## コマンド

```bash
swift test                                   # Core / IO / Tooling の単体テスト
swift build && .build/debug/kakiire --help   # CLI(info / annotate / export / mcp)。MCP は `kakiire mcp` を stdio で。使い方は docs/cli.md
xcodegen generate                            # project.yml から Kakiire.xcodeproj を生成(xcodeproj はコミットしない)
xcodebuild -project Kakiire.xcodeproj -scheme Kakiire -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Kakiire.app
./scripts/package.sh                         # Release ビルド → Developer ID 署名 → dist/Kakiire-<version>.dmg → 公証・staple(準備は docs/release.md、入れ方は docs/install.md。--no-notarize で公証を省く)
./scripts/package-cli.sh                     # CLI を Developer ID 署名 → dist/kakiire-<version>-macos-arm64.zip → 公証(Homebrew tap sumihiro3/homebrew-tap の formula が使う。手順は docs/release.md)
python3 scripts/download-stats.py <出力先>    # Releases のダウンロード数と traffic を CSV に記録する(毎日 launchd で動かす。docs/download-stats.md)
./scripts/bump-version.sh 0.8.0 --dry-run    # 版を上げる。前の版のタグ以降の PR から CHANGELOG.md の節を作り、版の表記を書き換える(--dry-run を外すと書き換える。手順は docs/release.md)
swift scripts/make-icon.swift                # アプリアイコンを作り直す(AppIcon.appiconset と docs/icon/ の原図。図形はこのスクリプトだけが持つ)
./scripts/build-site.sh                      # LP(site/)を build/site に組み立てる。バージョン表記は project.yml の MARKETING_VERSION から入る(公開は Cloudflare Pages。docs/site.md)
./scripts/og/render.sh                       # LP の OGP 画像(site/assets/og.png・en/og.png)を作り直す
```

## 層の約束

- App → IO → Core の一方向。Core(`Sources/KakiireCore`)は AppKit を import しない
- 文書は値型 `Document`。App は `EditOperation` を通してだけ変更し、Undo は `KakiireDocument.setContent` がスナップショットを NSUndoManager に積む
- ドラッグ中は `EditSession` の途中結果を表示だけし、マウスを離したときに確定する(Undo 1回分)
- 描画は画面と書き出しで同じ `Renderer`。グループ順に「画像オーバーレイ → 効果(モザイク・ぼかし)→ ハイライター → 図形」。画面は下の層(`BackdropView`:元画像〜ハイライター)と上の層(`AnnotationOverlay`:図形・選択枠)に分ける。ハイライターの乗算のため元画像も下の層の context に描く
- 効果は元画像と画像オーバーレイを合わせたものから計算する。画像オーバーレイは回転・反転で中身ごと回す(正立のままだとモザイクとずれて中身が見える)
- 画面の文言は App だけが持つ(`String(localized:)`、カタログは `App/Resources/Localizable.xcstrings`、日本語がキーで英訳を付ける)。Core / IO は表示名やエラー文を持たず、App の `Localization.swift` で訳す。文字列を足したら `xcodebuild -exportLocalizations -localizationPath build/loc -project Kakiire.xcodeproj -exportLanguage en` でキーを取り出し、英訳を入れる
- Quick Look 拡張(`Extensions/Thumbnail`・`Extensions/Preview`)は Core / IO だけに依存し、`KakiireArchive.previewData` で preview.png を返す。App のコードは使わない
- 「ショートカット」のアクション(App Intents)は `App/Sources/Intents` に置き、IO の処理を呼ぶだけにする(ADR 0011)。`@Parameter` の `supportedContentTypes` は `[.image]` や `UTType(exportedAs:)` をその場で書く(変数や自前の定数だとメタデータに載らない)
- CLI と MCP サーバー(`Sources/KakiireTooling`・`Sources/kakiire`)は Core / IO だけに依存する。処理は `KakiireTooling` に置き、`main.swift` は入出力をつなぐだけ。文言は英語だけ。`KakiireTool.appVersion` は `MARKETING_VERSION` と合わせる(テストあり)
- 方針の記録は `docs/adr/`
- 座標は元画像のピクセル座標(左上原点・y 下向き)
- Core / IO は Swift 6 の厳格な並行性チェック、App は `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

## 注意

- `NSWindowController` の init で `self.document` を自分で設定しない(`addWindowController` が登録しなくなり、ウインドウが出ない)
- 画像は fileURL を持たない無題文書として開く(`KakiireDocumentController.makeDocument`)。元画像の上書きを防ぐため
- PNG 書き出しでは ImageIO が付ける `eXIf` などの補助チャンクを `ImageExport.stripPNGMetadata` で除く
- Sitch(MIT)から流用したファイルは冒頭に出典を書き、`THIRD_PARTY_NOTICES.md` に載せる。GPL の ShareX / Greenshot / Flameshot は写さない
- PR 本文には「## 変更履歴」の欄を置き、使う人から見える変化を「- 」で書く(載せない変更は「なし」)。版を上げるときに `CHANGELOG.md` へ写し、マージで Actions がタグ `v<版>` と Release を作る(ADR 0010)
