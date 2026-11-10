# Quick Look のサムネイルとプレビュー(フェーズ5)

## 決定

| 項目 | 決定 |
|---|---|
| 作るもの | App に埋め込む Quick Look 拡張を2つ。`KakiireThumbnail`(`com.apple.quicklook.thumbnail`、Finder のアイコン)と `KakiirePreview`(`com.apple.quicklook.preview`、スペースキー。データで返す `QLIsDataBasedPreview`) |
| 見せる中身 | 保存のたびに `.kakiire` に入る `preview.png`(注釈を焼き込み済み、長辺 1024px まで)。取り出しは `KakiireArchive.previewData`(IO) |
| preview.png がないとき | 文書を読み、`previewPNG` と同じ描画で作り直す(古いファイルや、プレビューを書けなかったファイル向け) |
| Finder で作り直した zip | `read` と同じく、`manifest.json` のある階層を基準に探す(`KakiireArchive.root(of:)` を共有) |
| サムネイルの大きさ | 縦横比を保って `maximumSize` に収める。拡大はしない |
| 依存 | 拡張は `KakiireCore` と `KakiireIO` だけに依存し、App のコードは使わない。App Sandbox は必須(ないと読み込まれない)。署名は App と同じ Apple Development・Hardened Runtime。`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` は付けない(呼び出しはメインスレッドの外から来る) |

## 理由

- 拡張の中で文書を描き直すより、保存時に作った PNG を返す方が速く、描画コードの違いで見た目がずれることもない。描き直すのは preview.png がない場合だけ
- 署名は今は Apple Development のまま。Developer ID と公証は、Apple Developer Program に入ってから(フェーズ5の後半)

## 確認のしかた

- `pluginkit -m -v -A | grep kakiire` で2つの拡張が DerivedData の App から登録されていることを見る(App を一度起動すると登録される)
- `qlmanage -x -t -s 512 -o <dir> x.kakiire` でサムネイルを作る。`-x` を付けないと qlmanage はプロセス内の古い generator だけを探し、拡張を使わずに止まる
- `qlmanage -p x.kakiire` でプレビューのウインドウが出る。`-p` と `-o` を一緒に使うと、qlmanage 自身が拡張に接続する前に例外で落ちる(macOS 側の問題。拡張は呼ばれていない)
