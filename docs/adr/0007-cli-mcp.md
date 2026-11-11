# CLI と MCP サーバー(試作)

使い方は `docs/cli.md`、配り方は ADR 0008。

## 決定

| 項目 | 決定 |
|---|---|
| 作るもの | 実行ファイル `kakiire` を1つ。サブコマンド `info` / `annotate` / `export` / `mcp`。`mcp` は標準入出力の MCP サーバー |
| 層 | `KakiireTooling`(ライブラリ。IO に依存)に処理をすべて置き、`Sources/kakiire/main.swift` は引数と標準入出力をつなぐだけ。テストは `KakiireTooling` を直接呼ぶ(プロセスを起動しない) |
| 依存 | 外部パッケージは使わない。引数解析と JSON-RPC 2.0(改行区切り)は自前。MCP は `initialize` / `tools/list` / `tools/call` / `ping` だけを扱う |
| 注釈の入力 | document.json の `annotations` と同じ形(`AnnotationCoding.swift`)。`id` と `name` は省略できる。知らない `type` と `image`(素材が要る)はエラーにする(黙って描かれない注釈を作らない) |
| スタンプの番号 | `number` を省いたスタンプには、文書にある同じ種類のスタンプの続きから番号を振る |
| 入力 | 画像ファイル(PNG / JPEG / HEIC など)か `.kakiire`。撮影はしない(`screencapture` の画面収録の許可がターミナルに付くため) |
| 出力 | 拡張子で決める。`.png` / `.jpg` / `.jpeg` / `.kakiire`。入力と同じパスへの書き込みは `--force` なしでは断る(App が画像を無題文書で開くのと同じく、元画像を守る) |
| MCP の戻り値 | 文字の要約と、注釈を焼き込んだプレビュー(`KakiireArchive.previewPNG`、長辺 1024px)。原寸を返すとエージェントの文脈を圧迫するため。プレビューの縮小率も文字で返す |
| 文言 | 英語だけ。使うのはスクリプトとエージェントで、画面の文言ではないため(App の String Catalog の外) |
| `Manifest.appVersion` | `KakiireTool.appVersion` に定数で持つ。`project.yml` の `MARKETING_VERSION` と同じであることをテストで確かめる |

## 理由

- Core / IO は AppKit を使わないので、描画・保存をそのまま CLI から呼べる。画面と書き出しで同じ `Renderer` を使う約束も CLI まで延びる
- 依存を増やさないため。試作の範囲なら JSON-RPC の手書きは数十行で済む

## 確認のしかた

- `swift test`
- `swift build` の後、`.build/debug/kakiire annotate in.png -o out.png --annotations a.json`
- MCP は `initialize` などを1行ずつ `.build/debug/kakiire mcp` に流して応答を見る。Claude Code には `claude mcp add kakiire -- <絶対パス>/kakiire mcp` で登録する
