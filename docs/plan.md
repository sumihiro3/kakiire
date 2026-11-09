# Kakiire 設計・実装計画書

## Context

Skitch は Intel 版のみで、今後の macOS では使えなくなる。そこで Skitch 相当の画像注釈アプリ **Kakiire** を Swift + AppKit で一から作る。仕様の正本は `docs/handoff.md`。
リポジトリには今 `docs/handoff.md` しかない(git 未初期化)。この計画で決めること:

- 設計の具体化:モジュール構成、型、描画、Undo、ファイル形式
- フェーズ1〜5 の実装順と完了条件。handoff の図は読めなかったため、完了条件はこちらで起案した
- フェーズ1(注釈して書き出す MVP)は、そのまま着手できる粒度まで分解する

前提として確かめた環境:macOS 26.6、Xcode 26.4、Swift 6.3、XcodeGen 2.45.3(`/opt/homebrew/bin/xcodegen`)。
ビルド構成は **XcodeGen(`project.yml`)+ ローカル SwiftPM パッケージ**に決めた(ユーザー回答済み)。XcodeGen は開発時に使うだけのツールで、実行時の依存は増えない。

---

## 1. リポジトリ構成

```
/opt/dev/Kakiire/
├── project.yml                 # XcodeGen。App ターゲット(+ フェーズ5で QL 拡張)
├── Package.swift               # KakiireCore / KakiireIO ライブラリとテスト
├── Sources/
│   ├── KakiireCore/            # UI 非依存(Foundation / CoreGraphics / CoreImage / CoreText のみ)
│   │   ├── Model/              # Document, Annotation, 各 Spec, Style, Geometry, JSONValue
│   │   ├── Edit/               # EditOperation, EditSession(ドラッグ集約), HitTesting, Handles
│   │   └── Render/             # Renderer, ArrowPath, ObscureRenderer(+キャッシュ), TextLayout
│   └── KakiireIO/              # Zip, KakiireArchive, ImageImport, ImageExport(ImageIO)
├── Tests/
│   ├── KakiireCoreTests/       # Swift Testing(`import Testing`)
│   └── KakiireIOTests/         # Fixtures/ に Finder 再圧縮 zip 等
├── App/
│   ├── Sources/                # AppKit:AppDelegate, KakiireDocument(NSDocument), EditorWindowController,
│   │                           #   CanvasView, Tools/*, StyleBar, TextEditOverlay, ExportController
│   ├── Resources/              # Assets.xcassets, Info.plist の素
│   └── Kakiire.entitlements    # Sandbox(user-selected read-write)
├── docs/ handoff.md, plan.md(本計画の写し), adr/
├── THIRD_PARTY_NOTICES.md      # Sitch(MIT)
├── CLAUDE.md                   # ビルド・テストコマンド、層の約束
└── .gitignore                  # *.xcodeproj は生成物なので無視(xcodegen generate で再生成)
```

層の約束:
- App → IO → Core の一方向。Core は AppKit を import しない
- App は `EditOperation` を Core に渡すだけ。`Document` を直接書き換えない
- Core と IO は `swift test` だけで検証できる状態を保つ
- Swift の言語モード:
  - Core と IO は Swift 6 の厳格な並行性チェックで書く
  - App ターゲットは project.yml で `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` にする(キー名は project.yml を書くときに確かめる)
- アーキテクチャ:当面は `ARCHS = arm64` のみ。Universal は任意なので後回しにする

## 2. Core の設計

### 2.1 文書モデル(値型・Codable・Sendable)

```swift
struct Document: Sendable, Equatable {
    var canvas: Canvas            // crop: CGRect?(nil=全体), outputScale: Double = 1
    var base: BaseImage           // asset: ImageAsset, rotation: Rotation(0/90/180/270), flipH, flipV
    var annotations: [Annotation] // 先頭が最背面
}
struct Annotation: Sendable, Equatable, Identifiable {
    let id: UUID; var name: String; var hidden: Bool; var locked: Bool
    var content: AnnotationContent
}
enum AnnotationContent {
    case arrow(ArrowSpec), line(LineSpec), rect(ShapeSpec), ellipse(ShapeSpec),
         text(TextSpec), obscure(ObscureSpec)          // フェーズ1
    // フェーズ3: highlighter, pen, stamp, imageOverlay
    case unknown(type: String, raw: JSONValue)          // 知らない type はそのまま保持して再保存
}
```

- `ImageAsset` は `final class`。中身は不変で、`CGImage` と元のエンコード済みデータ、SHA-256 を持つ。参照を共有するので、Undo 用に Document をコピーしても画像は複製されない。等値判定はハッシュで行う。macOS 26 SDK で `CGImage` が Sendable でなければ `@unchecked Sendable` にする(中身は不変なので安全。理由はコメントで残す)
- JSON は handoff の骨子に合わせる(`type` / `geometry` / `style` に分ける)。`Codable` は手書きにする。`JSONValue`(任意の JSON を表す enum)で、知らないフィールドと知らない type を往復させる
- 色は `RGBAColor`(`#RRGGBB[AA]` 形式の文字列でエンコード)。座標は元画像のピクセル座標で、Y 軸は下向き(画像座標)。描画時に CG の座標系へ変換する
- 回転・反転は base と全注釈の座標に同時に適用する(`Document.rotated(by:)`)。90° を4回かけると元に戻ることをテストで確かめる(フェーズ3)

### 2.2 編集操作と Undo

- `enum EditOperation { add, remove(ids), move(ids, delta), setGeometry(id, …), setStyle(ids, …), setText, reorder, setVisibility, setLock, rename, … }`
- `Document.applying(_:) -> Document` は純粋関数にする
- `EditSession`(Core)はドラッグを1つにまとめる:`begin()` の時点の Document を保存し、ドラッグ中の `update(op)` は現在値だけを更新し、`commit()` で `(before, after)` を返す
- Undo はスナップショット方式で、**NSDocument の `undoManager` に載せる**(App 側)。`commit` で得た `before` を `registerUndo` に登録する。メニューの「取り消す」、変更済み表示、自動保存は OS の仕組みがそのまま動く
- `HitTesting`(Core):点 → 注釈 id(前面から順に調べる。hidden と locked は除く)、選択中の注釈のハンドル判定、矩形での範囲選択。線系は太さに許容幅を足して判定する

### 2.3 描画(画面と書き出しで同じ Renderer を使う)

`Renderer.draw(document, in: CGContext, region: CGRect, scale: CGFloat, cache: RenderCache?)`

1. 回転・反転を適用した base を描く。変換後の CGImage は `RenderCache` に保持する
2. `obscure` 注釈:base の該当範囲を CIImage で切り出し、`CIPixellate` または `CIGaussianBlur`(端は `clampedToExtent` で処理)をかけて描く。結果は **(base のハッシュ, 範囲, mode, strength) をキーにキャッシュ**し、ドラッグ中は動かしている注釈の分だけ計算し直す。効果系は配列内の位置に関係なく、常に図形より先に描く
3. 図形を配列の順に描く:
   - 矢印は Skitch 風の先細り形。Sitch の実装を流用する候補(下の §5)。太さ・始点・終点から塗りつぶしの CGPath を作る
   - 線・矩形・楕円は stroke(必要なら fill)
   - テキストは CoreText で描く。Skitch 風に白フチ(縁取り)を付け、フォントサイズ・色・太さを持つ
4. crop で切り出し、`outputScale` で縮小する(書き出し時のみ)

- 書き出し用の `Renderer.makeImage(document) -> CGImage` は Core に置く。ImageIO で PNG/JPEG にエンコードする処理は IO に置く
- 60fps を出すための工夫:
  - CanvasView はレイヤーで構成する。base は下のレイヤーの contents に一度だけ載せる
  - 効果と図形は前面のサブレイヤーに描く。そのレイヤーの delegate が Renderer を呼び、ドラッグ中は dirty rect の分だけ描き直す
  - CIContext は Metal を使うものを1つ使い回す

## 3. IO の設計

- **Zip(フェーズ2)**:自前で最小限に実装する
  - 書き込み:Local File Header → データ → Central Directory → EOCD の順。PNG は stored、JSON は deflate
  - deflate は `Compression` の `COMPRESSION_ZLIB` を使う。これは zlib ヘッダの付かない raw deflate を出力し、zip の方式 8 にそのまま使える
  - CRC32 は `import zlib` の `crc32`。モジュールが見つからなければ 256 要素の表で自前計算する(着手時に確認)
  - 読み込み:EOCD を末尾から探す(コメント最大 64KB を考慮)→ Central Directory を読む → 各エントリへ。`__MACOSX/`、`._*`、知らないエントリは無視する。ZIP64、暗号化、stored/deflate 以外の方式はエラーにする。パスに `..` を含むエントリは拒否する
- **KakiireArchive**:`manifest.json`(formatVersion: 1, appVersion, createdAt, updatedAt)、`document.json`、`base.png`、`assets/<sha256>.png`、`preview.png`(長辺 1024px まで)を読み書きする。`formatVersion` がアプリより新しいファイルは `readOnly` フラグを付けて返す
- **ImageImport**:ImageIO で PNG/JPEG/HEIC/TIFF を読む。EXIF の向きを正しく反映し、色空間を保つ。`base.png` は取り込んだときの画像をそのまま PNG で持つ
- **ImageExport**:PNG / JPEG(品質を指定)。Display P3 などの色空間を保つ

## 4. App(AppKit)の設計

- `KakiireDocument: NSDocument`
  - フェーズ1:画像を開いて書き出せるところまで。保存は無効化する(`.kakiire` 保存はフェーズ2)
  - フェーズ2:`read(from:ofType:)` / `data(ofType:)` を KakiireArchive につなぐ。画像ファイルから開いた文書は未保存扱いにし、保存時に `.kakiire` を求める
  - 注意:画像を Viewer 型で登録すると、NSDocument は `fileURL` に元の PNG を設定する。そのままだと「保存」で PNG を上書きしてしまう。画像を取り込んだら `fileURL = nil` にして、無題の新規文書として扱う(または `NSDocumentController.makeDocument(withContentsOf:ofType:)` を画像型だけ上書きする)
- Info.plist(project.yml で生成):
  - `UTExportedTypeDeclarations` に `com.tep-lab.kakiire`(conforms: `public.data`, `public.content`、拡張子 `kakiire`)を宣言する。zip に準拠させないのは、Finder やアーカイブユーティリティに勝手に展開させないため
  - `CFBundleDocumentTypes` は `.kakiire` を Editor、画像を Viewer(取り込み用)として登録する
- 画面:
  - `NSScrollView` で拡大縮小する。CanvasView は画像のピクセル座標で描く
  - 上部にツールバー:ツール選択(V 選択 / A 矢印 / L 線 / R 矩形 / O 楕円 / T 文字 / M モザイク / B ぼかし)と、色・太さ・強さのスタイル欄
- ツール:`protocol Tool { mouseDown/Dragged/Up, keyDown, cursor }`。ツールは EditSession を通して EditOperation を出すだけ
- テキスト編集:注釈の上に `NSTextView` を重ねて直接編集する。確定時に `setText` を送る
- 入力:
  - ファイルを開く(⌘O)
  - 「クリップボードから新規」(⇧⌘N)。編集中に ⌘V で画像を貼ると、フェーズ1では base の差し替えを確認する。フェーズ3で画像オーバーレイとして追加する形に変える
  - ウィンドウや Dock アイコンへのドラッグ&ドロップ
- 書き出し:
  - 「書き出す…」(⇧⌘E):NSSavePanel に PNG/JPEG を選ぶ欄と JPEG 品質を付ける
  - 「画像をコピー」(⇧⌘C)
  - ツールバーのサムネイルからドラッグで持ち出す:`NSFilePromiseProvider` に PNG データも合わせて載せる
  - 書き出しは必ずモザイク・ぼかしを焼き込む(仕様どおり)
- Sandbox は有効にする(`com.apple.security.files.user-selected.read-write`)。署名はフェーズ1〜3は ad-hoc

## 5. Sitch の扱い

- 着手時に `git clone https://github.com/phalladar/Sitch /opt/dev/_ref/Sitch` で参照用に取得する。リポジトリの外に置き、フォークはしない。LICENSE が MIT であることを再確認する
- 読む資料:`docs/SPEC.md`(Skitch の操作仕様。ショートカットやハンドルの挙動を合わせる)、`docs/research/digest.md`
- 流用候補:先細り矢印の形状(フェーズ1)、モザイク・ぼかし(フェーズ1)、範囲キャプチャのオーバーレイとホットキー(フェーズ4)
  - 流用したファイルには冒頭に出典を書く
  - `THIRD_PARTY_NOTICES.md` に MIT 表記を載せる
  - Core に入れるときは値型の API に合わせて書き直す
- ShareX / Greenshot / Flameshot(GPL)のコードは見ない・写さない

## 6. フェーズと完了条件(起案)

| フェーズ | 中身 | 完了条件 |
| --- | --- | --- |
| 1 MVP | 画像入力、注釈7種、選択・移動・リサイズ・削除・Undo、PNG/JPEG・コピー・ドラッグ書き出し | ① macOS 標準スクショを ⌘V → 矢印・文字・モザイク → PNG 書き出しが1分以内でできる ② 書き出し PNG の伏せた範囲は、どの 8×8 ブロックも元画像と一致しない。また PNG に元画像のデータを含む補助チャンクがない(どちらもテストで確認)③ 4K 画像に注釈20個でドラッグが 60fps 前後(Instruments で確認)④ `swift test` が全件パス |
| 2 保存 | `.kakiire` の読み書き、自動保存・版の履歴、preview.png、バージョニング | ① 保存して開き直すと全注釈を再編集できる ② Finder で展開・再圧縮したファイルが開ける ③ 知らない type・フィールドが再保存で消えない ④ 新しすぎる形式を読み取り専用で開く ⑤ Google ドライブ経由で往復しても壊れない(実機で確認) |
| 3 編集強化 | レイヤーパネル、ハイライター・ペン・スタンプ(連番)・画像オーバーレイ、切り抜き・リサイズ・回転・反転 | ① レイヤーの並べ替え・表示切替・ロック・名前変更がすべて Undo できる ② 回転・反転・切り抜き・リサイズが非破壊で、元に戻せる ③ 未決事項「リサイズ時の線幅」を着手前に決めて ADR に残す |
| 4 キャプチャ | ScreenCaptureKit で範囲・ウィンドウ・全画面、グローバルホットキー、メニューバー常駐 | ① 着手前に Apple Developer Program へ加入し Developer ID 署名に切り替える ② ビルドし直しても画面収録の許可が維持される ③ マルチモニタ・Retina 混在で範囲がずれない |
| 5 仕上げ | Quick Look のサムネイル(QLThumbnailProvider が preview.png を返す)とプレビュー、アイコン、DMG、GitHub Actions で署名・公証 | ① Finder で `.kakiire` のサムネイルとスペースキーのプレビューが出る ② 公証済み DMG が社内の別 Mac で警告なしに開ける |

残っている未決事項は、決める時期に合わせて扱う:
- 「共有用に保存」:フェーズ2の後に必要か判断する
- 旧 Skitch 画像の取り込み:フェーズ3で判断する
- OSS 公開とライセンス:フェーズ5までに決める

## 7. フェーズ1 実装手順(TDD で進め、手順ごとにコミット)

1. **土台**
   - 最初に、この計画書を `docs/plan.md` に写す
   - Vault に記録する:`Projects/Kakiire/overview.md` と `Decisions/2026-11-07-kakiire-build-setup.md`(XcodeGen の採用と Swift の言語モード)
   - `git init`、`.gitignore`、`Package.swift`(swift-tools 6.0、`.macOS(.v15)`)、`project.yml`、空の App
   - `xcodegen generate && xcodebuild -scheme Kakiire build` が通るところまで
   - プロジェクトの CLAUDE.md を書き、Vault に `Projects/Kakiire/overview.md` を作る
2. **モデル**(テスト先行)
   - Document / Annotation / Spec / Style / JSONValue と、手書きの Codable
   - handoff の JSON 骨子をゴールデンファイルにして往復させる。unknown type の保持もここで確かめる
3. **編集**
   - `applying` を操作ごとにテストする
   - EditSession のまとめ方(ドラッグ中に update を100回送っても Undo は1回分になる)
   - HitTesting と範囲選択
4. **描画**
   - ArrowPath(Sitch を参照)、図形、テキスト、ObscureRenderer とキャッシュ
   - テストは小さな画像で行う。ピクセル単位で比べるより、性質で確かめる:モザイク範囲の外は1画素も変わらない、範囲内は元と違う、図形は効果より前面に描かれる
   - 性能テスト:3840×2160 に注釈20個で、全体描画とドラッグ時の部分描画を計測する
5. **App:キャンバスとツール**
   - CanvasView(拡大縮小、レイヤー分割)、選択ツールとハンドル、各作図ツール、スタイル欄、削除、undoManager との連携
6. **入力**:開く、クリップボードから新規、ドラッグ&ドロップ
7. **書き出し**:ImageExport(IO)、書き出しパネル、コピー、ドラッグで持ち出し
8. **仕上げ**:キーボードショートカットを Skitch / Sitch の SPEC に揃える。フェーズ1の完了条件を検証する。Vault に知見を記録する

フェーズ2以降は、フェーズ1の完了時に同じ粒度で `docs/plan.md` に追記してから着手する。

## 8. 検証方法

- `swift test`:Core と IO の単体テスト、ゴールデン JSON、描画の性質テスト、性能テスト
- `xcodegen generate && xcodebuild -scheme Kakiire -destination 'platform=macOS' build test`
- 実機:アプリを起動し、⇧⌘4 でクリップボードに撮ったスクショで「⌘V → 注釈 → ⇧⌘E 書き出し → プレビュー.app で確認」の流れを通す
- 性能:Instruments(Time Profiler / Animation Hitches)で 4K のドラッグを計測し、数値を記録に残す
- フェーズ2:`ditto -x -k` で展開し、`ditto -c -k` で再圧縮したファイルが開けることをテストの fixture で確かめる

---

## 進捗(2026-11-07)

フェーズ1 の手順1〜7 を実装した。

| 完了条件 | 状態 | 根拠 |
| --- | --- | --- |
| ① 貼り付け → 矢印・文字・モザイク → 書き出しが1分以内 | 一部確認済み | 自動操作で「画像を開く → 矢印・モザイク・文字 → 選択・移動 → ⌘Z → ⇧⌘C」を通した。コピーした PNG にはモザイクが焼き込まれていた。保存パネルは開くところまで確認(ファイルへの書き込みは手動で要確認)。⌘V 起点とドラッグでの持ち出しは未確認 |
| ② 伏せた範囲のどの 8×8 ブロックも元と一致しない/補助チャンクがない | 確認済み | `RenderTests.noOriginalBlockSurvives`、`ImageIOTests.exportedPNGHasNoAncillaryPayload` |
| ③ 4K・注釈20個で 60fps 前後 | 部分確認 | `RenderTests.performance4K`:効果をキャッシュした後の再描画は平均約 0.74ms(Debug)。モザイク3つの初回計算は 182ms(Debug)。Instruments での実測は未実施 |
| ④ `swift test` が全件パス | 確認済み | 34 件 |

### 残り

- ~~手動確認:⌘V からの起動、⇧⌘E で実際にファイルを書く、ドラッグで持ち出し、JPEG 書き出し~~ 2026-11-09 ユーザーが確認
- Instruments で 4K のドラッグを計測する(Release ビルド)
- フェーズ2(`.kakiire` の保存)の計画を、この文書に同じ粒度で追記する

---

## フェーズ2 実装計画(2026-11-07)

1. **Zip(IO)**:`ZipWriter` / `ZipReader`。stored と deflate(`COMPRESSION_ZLIB` = raw deflate)、CRC32 は `import zlib`(動作確認済み)。名前は UTF-8 フラグを立てる。読み込みは末尾の EOCD から。暗号化・ZIP64・その他の方式はエラー。`..` を含むパスは拒否する。`__MACOSX/`・`._*`・ディレクトリは無視する。展開時に CRC を検査する
2. **KakiireArchive(IO)**:`manifest.json`、`document.json`(整形・キー順固定)、`base.png`、`preview.png`(長辺 1024px まで)。Finder で「展開 → フォルダを圧縮」すると全エントリにフォルダ名が付くので、`manifest.json` が見つかった階層を基準に読む。`formatVersion` がアプリより新しければ `isReadOnly`。作成日時は保存しても変えない
3. **NSDocument**:`com.tep-lab.kakiire` を UTExportedType として宣言し、Editor 型にする。画像は従来どおり Viewer で取り込み、`fileType` を kakiire にした無題文書として開く(⌘S で保存パネル)。`autosavesInPlace = true`(版の履歴)。フェーズ1の「書き出していない変更」の独自確認はやめ、NSDocument 標準の確認に戻す。読み取り専用で開いた文書は編集・保存を止め、タイトルに表示する。版の復元などで `read` し直したときはウインドウを再読み込みする
4. **ツールバーの位置(追加要望)**:既定はウインドウの左。縦に並べる(ツールは2列、色は3列)。「設定…」(⌘,)で「左 / 上」を選べ、開いているウインドウにもすぐ反映する。UserDefaults に保存する
5. **確認**:単体テスト(zip の往復、`unzip -t` での検証、`ditto` での展開・再圧縮、知らない type・新しすぎる形式、壊れた zip)。実機で「画像を開く → 注釈 → ⌘S → 閉じる → 開き直す → 再編集できる」を通す

### フェーズ2 進捗(2026-11-07)

| 完了条件 | 状態 | 根拠 |
| --- | --- | --- |
| ① 保存して開き直すと全注釈を再編集できる | 確認済み | `ArchiveTests.roundTripKeepsEverythingEditable`。実機で、画像を開く → 矢印・モザイク → ⌘S → 閉じる → 開き直す → 矢印を選択できる、を確認した |
| ② Finder で展開・再圧縮したファイルが開ける | 確認済み | `ArchiveTests.reopensAfterFinderStyleExpandAndRecompress`(`ditto -x -k` で展開 → `ditto -c -k --keepParent` で再圧縮)。`unzip -t` でも正当な zip と判定された |
| ③ 知らない type・フィールドが再保存で消えない | 確認済み | `ArchiveTests.unknownAnnotationSurvivesResave` |
| ④ 新しすぎる形式は読み取り専用 | テストのみ | `ArchiveTests.newerFormatOpensReadOnly`。App は編集・保存を止め、タイトルに「(読み取り専用)」と出す(実機では未確認) |
| ⑤ Google ドライブ経由で往復しても壊れない | 未確認 | 手動で確認する |

- ツールバーは既定でウインドウの左。ツールは1列に並べ、色と太さは今の値を示すボタンにして、押すとメニューで選ぶ。「設定…」(⌘,)で上と切り替えると、開いているウインドウにもすぐ反映される(実機で確認)
- 自動保存と版の履歴は NSDocument の標準機能。「戻す」メニューの動作は 2026-11-09 にユーザーが確認

---

## フェーズ3 実装計画(2026-11-07)

方針は `docs/adr/0001-phase3-decisions.md`(線幅は画像と一緒に縮む/レイヤーは右サイドバー/Skitch 取り込みはしない/描画は4グループ)。

1. **画像操作(Core)**:`EditOperation` に `.rotate(clockwise:)`・`.flip(horizontal:)`・`.setCrop(CGRect?)`・`.setOutputScale(Double)` を足す。向きは「回転してから反転」の8状態(二面体群)として合成し、`rotation += 90` にしない。注釈と切り抜き範囲も同じ変換で移す。画像オーバーレイは元画像と同じく向きを持ち中身ごと回す(正立のままだと上のモザイクとずれて中身が見える)。テキスト・スタンプは外形の中心だけ移して正立のまま。テスト:8つの開始状態すべてで「文書を回してから描いた画像」と「描いた画像を回したもの」が画素で一致する。90° を4回で元に戻る
2. **新しい注釈(Core)**:`highlighter`・`pen`(点列)・`stamp`(連番の丸)・`image`(画像オーバーレイ)。JSON の往復、外形・移動・つまみ・当たり判定・描画。描画は「画像 → 効果 → ハイライター → 図形」の順で、効果は元画像と画像オーバーレイを合成したものから計算する(キャッシュのキーに重なる画像を含める)。ハイライターは乗算合成。連番は既存の最大値 + 1
3. **レイヤーの並び(Core)**:パネルの行(グループごとに前面が上)と配列の位置の対応を `LayerList` にまとめ、行の移動を `.reorder` に変換する。テスト先行
4. **素材(IO)**:`assets/<sha256>.png` を書き、読み込み時に `decoder.userInfo` で注釈に渡す。参照されない素材は書かない。`formatVersion` は 1 のまま(追加は互換扱い)
5. **キャンバス(App)**:下の層(元画像・画像・効果・ハイライター)と上の層(図形・選択枠)に分ける。乗算を画面でも書き出しと同じにするため、下の層は元画像も同じ context に描く
6. **ツール(App)**:ハイライター(H)・ペン(P)・スタンプ(N)・切り抜き(C)。編集中の ⌘V は画像オーバーレイとして追加し、元画像の置き換えはダイアログの別ボタンに残す
7. **画像メニュー(App)**:左に回転(⌘L)・右に回転(⌘R)・左右反転・上下反転・切り抜き・画像サイズ…(ピクセル指定・比率)。切り抜きは周りを暗くして8つのつまみで調整し、Return で確定、Esc で取り消す。確定後は切り抜いた範囲だけを表示する
8. **レイヤーパネル(App)**:右サイドバーの一覧(表示・ロック・名前の変更・ドラッグで並べ替え)。キャンバスの選択と連動する。操作はすべて `EditOperation` を通すので Undo できる
9. **確認**:完了条件①②を実機で通し、`swift test` を全件パスさせる

### フェーズ3 進捗(2026-11-07)

| 完了条件 | 状態 | 根拠 |
| --- | --- | --- |
| ① レイヤーの並べ替え・表示切替・ロック・名前変更がすべて Undo できる | 確認済み | `LayerListTests`(パネルの行と配列の対応、グループをまたがせない)。実機で、パネルから非表示・ロック・名前変更・ドラッグで並べ替え → それぞれ ⌘Z で戻ることを確認 |
| ② 回転・反転・切り抜き・リサイズが非破壊で、元に戻せる | 確認済み | `OrientationTests`(8つの開始状態 × 4操作で「文書を回して描く」=「描いてから回す」が画素で一致、90°×4・反転×2で元通り、切り抜き・倍率の切り詰め)。実機で右に回転 → 切り抜き → ⌘Z 2回で元に戻る、画像サイズ 50% でコピーした画像が 1200×750 になることを確認 |
| ③ 「リサイズ時の線幅」を ADR に残す | 済み | `docs/adr/0001-phase3-decisions.md`(画像と一緒に縮む)。`OrientationTests.outputScaleShrinksStrokesToo` |

- 新しい注釈:ハイライター(H、乗算)・ペン(P)・番号スタンプ(N、最大値 + 1)・画像オーバーレイ(編集中の ⌘V)。元画像の置き換えは「画像」メニューに移した
- 描画は「画像 → 効果 → ハイライター → 図形」。モザイクは貼った画像の上にも効く(`Phase3AnnotationTests.obscureCoversImageOverlay`)
- 実機で見つけて直したもの:
  - 画像オーバーレイを正立のまま回すと、上に掛けたモザイクとずれて伏せた文字が見えた → 画像オーバーレイにも向きを持たせ、中身ごと回すようにした(`OrientationTests.overlayUnderMosaicStaysCovered`)
  - 切り抜き範囲が画像全体のとき、内側をドラッグしても新しい範囲を作れなかった
  - 画像サイズの入力欄で、日本語入力の全角数字が連動しなかった(半角に直して読む。変換中は確定まで連動しないのは macOS 標準の動き)
  - レビューで発見:クリックで選ぶ順が配列順のままで、後から貼った画像が上に描かれた矢印を奪っていた → レイヤーの行の順(描く順)で当たり判定する(`LayerListTests.hitTestFollowsRenderOrder`)。複数選択の「最背面へ」で相対順が逆になっていたのも修正
- `.kakiire` は `assets/<sha256>.png` に貼った画像を入れる(`formatVersion` は 1 のまま)。保存して開き直す流れはテストのみ(実機の保存パネル経由は未確認)
- ツールバーを上に置いても12個が1行に収まることを実機で確認した
- 未確認:読み取り専用ファイルでのパネルとメニューの無効化。画面が下の層(元画像を CG で描く)と上の層の2枚になったので、フェーズ1の完了条件③(4K で 60fps)は測り直しが要る(`RenderTests.performance4K` は旧経路の `drawAnnotations` を測っている)

## フェーズ3.5 使い勝手の改善(2026-11-08)

フェーズ3の後に使ってみて出た要望を、小さく効くものから順に入れた。方針は `docs/adr/0002-phase3_5-decisions.md`。

| 要望 | 状態 | 根拠 |
| --- | --- | --- |
| 開いた直後にレイヤーが出ない | 修正 | 文書を開いたときにパネルを読み込んでいなかった。実機で開き直して全レイヤーが出ることを確認 |
| 文字の大きさ・袋文字 | 済み | スタイルボタンがテキストのとき 12〜72pt の9段と袋文字。⌥⌘+ / ⌥⌘-。実機で 56pt・72pt・袋文字なしを確認 |
| モザイクの強さ | 済み | 弱い/ふつう/強い(6/12/24px、ぼかしは 1.4 倍)。実機で強いに変えて ⌘Z で戻ることを確認 |
| リサイズのつまみを大きく | 済み | 8→12pt、つかめる半径 6→10pt、切り抜き 10→14pt |
| 線の種類 | 済み | 実線・破線・点線・一点鎖線。`LineDashTests`(JSON の往復、実線は書かない、破線に隙間ができる、実線の矢印は今と同じ)。実機で全図形に当てて保存し、開き直して残ることを確認 |
| ツールチップ | 済み | 各ツールに操作のヒント(Shift の効きなど)、レイヤーの目・鍵・行。実機で表示を確認 |
| 起動時の編集画面と取り込み | 済み | 空の編集画面に「スクリーンショットを撮る」「クリップボードから」「ファイルを開く…」。実機でクリップボードから取り込み、同じ枠で編集画面に切り替わることを確認 |
| スクリーンショット | 済み | 許可を入れたあとの撮影はフェーズ4で確認 |
| 多言語化 | 済み | 日本語・英語。英語環境で起動し、メニュー・パネルの見出しが英語になることを確認 |

- テスト 76 件パス
- ついでに直したもの:ファイルメニューの「最近使った項目」が二重に出ていた、ツールバーの独自ボタンがアクセシビリティに出ていなかった
- 既知の問題:System Events(AX)でメニュー項目をクリックして文書を初めて変えた直後に ⌘S すると、NSDocument の保存が待ちのまま固まることがある。実際のマウス・キーボード操作では4回とも起きなかった。VoiceOver で起きるかは未確認


## フェーズ4 キャプチャと使い勝手の修正(2026-11-09)

方針は `docs/adr/0003-phase4-decisions.md`。撮影は `screencapture` のまま、署名を Apple Development に替えた。

| 項目 | 状態 | 根拠 |
| --- | --- | --- |
| 撮影後に Kakiire が前面に戻らない | 修正 | `NSApp.hide` をやめ、ウインドウを `orderOut` する。実機で、撮影後に Kakiire が前面に戻り、撮る前のウインドウがキーに戻ることを確認 |
| ウインドウの端でリサイズのカーソルにならない | 修正 | キャンバスがカーソルを上書きしていた。ウインドウの縁から 6pt 以内では設定しない。実機で、下の辺と右の辺でリサイズのカーソルになることを確認 |
| ⌥⌘- が効かない | 修正 | 何も選んでいないときはメニューが無効だった。次に打つ文字の大きさを変えるようにした。実機で確認 |
| 作図ツールのまま同じ種類をつかむ | 済み | `HitTesting.annotation(where:)` を足した(テストあり)。実機で、矩形ツールでの矩形の移動と、矩形の中への新しい矩形、ハイライターでの移動、テキストツールでのドラッグ移動とクリック編集を確認 |
| テキストのリサイズ | 済み | `TextResizeTests`(右下・左上の固定、小さいほうの比、4pt で止まる)。実機で、右下のつまみで大きくなり ⌘Z で戻ることを確認 |
| 画像の挿入 | 済み | ファイルから・スクリーンショットから・Finder からのドロップが、どれも画像オーバーレイになることを実機で確認 |
| ① Apple Development 署名 | 済み | 指定要件が証明書名になったことを `codesign -d -r-` で確認。Developer ID はフェーズ5 |
| ② ビルドし直しても許可が残る | 確認済み | 許可を入れた後にビルドし直し、撮影できることを確認。ad-hoc の頃の登録は `tccutil reset` で消して入れ直した |
| ③ マルチモニタ・Retina 混在 | 未確認 | `screencapture` が OS 標準で扱う。外部モニタでの実機確認はしていない |
| グローバルショートカット | 済み | 既定 ⌃⇧⌘5。Finder が前面のときに押して撮影でき、撮影後に Kakiire が前面に来ることを確認 |
| メニューバー | 済み | アイコンとメニューを確認。設定で消す・戻すことを確認。ウインドウを全部閉じても終了しない |

- テスト 82 件パス
- 手動確認の残りのうち、⌘V から始める流れ・⇧⌘E での書き出し・ドラッグでの持ち出し・JPEG 書き出し・「戻す」(版の履歴)はユーザーが確認した(2026-11-09)

## 次の対応(2026-11-09)

- **済(2026-11-09)矢印の袋文字(白い縁取り)**:決めたことは ADR 0004。赤や暗い部分の多い画像でも矢印が埋もれないように。テキストの袋文字と同じ扱いで、スタイルボタンから切り替える。`ArrowSpec` に縁の有無を足す。ADR 0002 の dash と同じく、既定(縁なし)は書かずに省略可能にすれば `formatVersion` は 1 のまま(古い版で開いて保存すると縁が消えるだけ)。`Renderer` は塗る前に同じパスを太い線で描き、当たり判定も縁の分だけ広げる。アプリのアイコン(白縁の赤い矢印)はこの見た目に合わせる

## 0.4.0 切り抜きの px 指定・画像の枠線と影・スタンプの種類(2026-11-09)

方針は `docs/adr/0005-crop-size-image-frame-stamps.md`。矢印の白い縁取り(ADR 0004)も 0.4.0 に入れる。

| 項目 | 状態 | 根拠 |
| --- | --- | --- |
| 切り抜きの範囲を px で指定 | 済み | `CropMathTests`(丸め・中へずらす・画像の大きさで止める・縦横比)。実機で、シートに 500 × 400 を入れると案内に 500 × 400 px と出て、Return で確定・⌘Z / ⇧⌘Z で戻す・やり直すことを確認。案内のクリックでもシートが開く |
| 画像の枠線と影 | 済み | `ImageFrameTests`(保存・既定は書かない・描画範囲・内側と外側の枠・影・モザイクの下の枠)。実機で、貼り付けた画像に太い枠線と影を付けられること、枠線を内側・外側に切り替えられることを確認 |
| スタンプの種類 | 済み | `StampKindTests`(英字の変換・種類ごとの番号・保存・古い形・絵文字は丸なし)。実機で、数字 → 英字 → ✓ → 👍 → 数字と切り替え、数字が続きから進むこと、選択ツールで選んだスタンプを 👎 に変えて ⌘Z で戻ることを確認 |
| ウインドウの大きさに画像を合わせる | 済み | 「ウインドウに合わせる」(⌘9)の状態の間は、ウインドウ・レイヤーパネル・ツールバーの変化に合わせて倍率を合わせ直す。拡大・縮小・実寸・ピンチでこの状態をやめる。⌘9 は等倍を超えても拡大する(以前は等倍が上限で、大きなウインドウでは変化しなかった)。開いたときだけ、小さい画像は等倍のままにする。実機で、ウインドウを 1000 / 1600 幅に変えると画像が追従し、⌘0 の後は追従せず、⌘9 で戻ることを確認 |
| ドラッグ中の大きさの表示 | 済み | 切り抜き・矩形・楕円・モザイク・ぼかし・画像・テキストを描く/変形する間、カーソルの右下に「幅 × 高さ」(px)、矢印・線は長さを出す。見えている範囲の端では左上へ回す。実機で、矩形・切り抜き・矢印のドラッグ中に出て、離すと消えること、右下の角で回り込むことを確認 |

- テスト 108 件パス
- 英語環境での新しい文言の表示は未確認(英訳は入れた)

