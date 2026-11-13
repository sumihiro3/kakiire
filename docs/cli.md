# CLI と MCP サーバー(試作)

`kakiire` コマンドで、画像に注釈(矢印・枠・文字・番号スタンプ・モザイクなど)を付けて、PNG / JPEG / `.kakiire` に書き出す。`kakiire mcp` で MCP サーバーとして動き、Claude Code などのエージェントから同じことができる。

描画はアプリと同じ `Renderer` を使うので、見た目はアプリで描いたものと変わらない。`.kakiire` で書き出せば、AI が付けた注釈をアプリで開いて直せる。方針は `docs/adr/0007-cli-mcp.md`。

## 入れる

CLI は App とは別に配る(App には入っていない。方針は `docs/adr/0008-cli-distribution.md`)。Homebrew tap と、署名・公証済みの zip で配る予定で、まだ用意していない。今はソースからビルドする:

```bash
swift build -c release
```

`.build/release/kakiire` ができる。パスの通った場所に置く:

```bash
mkdir -p ~/.local/bin && cp .build/release/kakiire ~/.local/bin/
```

入れ直すときは、先に `rm ~/.local/bin/kakiire` で消してからコピーする。実行ファイルを上書きコピーすると、macOS が覚えている署名と中身が食い違い、起動した途端に強制終了される(終了コード 137)。登録した MCP サーバーも同じファイルを使うので、入れ直すまでは古いまま動く。

アプリ(`Kakiire.app`)がなくても動く。撮影はしないので、画面収録の許可も要らない。

## コマンド

| コマンド | すること |
|---|---|
| `kakiire info <file>` | 画像の大きさ・切り抜き・書き出しの大きさ・注釈とその描かれる範囲・大きさの目安・プレビューの大きさを JSON で出す |
| `kakiire annotate <input> -o <output> [-o <output>...] [-a <json>] [--crop x,y,w,h] [--scale s] [--force]` | 注釈を足して書き出す |
| `kakiire export <input> -o <output> [-o <output>...] [--crop x,y,w,h] [--scale s] [--force]` | 注釈を足さずに書き出す(`.kakiire` → PNG など) |
| `kakiire mcp` | 標準入出力の MCP サーバーとして動く |
| `kakiire --version` / `--help` | バージョン / 使い方 |

- `<input>` は画像(PNG・JPEG・HEIC・TIFF・GIF・BMP)か `.kakiire`。`.kakiire` を入れると、元の注釈に足していく
- `<output>` の形式は拡張子で決まる。`.png` / `.jpg`(`.jpeg`)/ `.kakiire`。JPEG は白地に合成する
- `-o` を重ねると、同じ結果を複数の形式に書く(例:`-o shot.png -o shot.kakiire`)。書き出し先をすべて確かめてから書くので、1つでも誤りがあれば何も書かない
- `-a -` で注釈の JSON を標準入力から読む
- `--crop` は切り抜き(元画像のピクセル)、`--scale` は書き出しの倍率(線や文字も一緒に縮む)。`.kakiire` に書くとどちらも非破壊のまま残る
- 入力と同じファイルには、`--force` を付けないと書かない(元画像を守るため)
- 失敗すると標準エラーに英語で理由を出す。終了コードは引数・注釈の誤りが 2、読み書きの失敗が 1

### 例

```bash
kakiire info shot.png
```

```bash
kakiire annotate shot.png -o shot.kakiire -a notes.json
```

```bash
kakiire export shot.kakiire -o shot.png --scale 0.5
```

```bash
echo '[{"type":"obscure","geometry":{"rect":[40,300,520,48]},"style":{"mode":"pixelate","strength":16}}]' | kakiire annotate shot.png -o shot-masked.png -a -
```

## 座標

- すべて**元画像のピクセル**。左上が原点で、y は下向き
- Retina のスクリーンショットは、画面上の大きさ(ポイント)の 2 倍のピクセルになる。先に `kakiire info` で `width` / `height` を見る
- `.kakiire` が回転・反転されていれば、回転した後の画像の座標になる(`info` の `width` / `height` もそれに合わせて出る)

## 注釈の JSON

`.kakiire` の中の document.json にある `annotations` と同じ形の配列。`id` と `name` は省ける(`name` を省くと type 名になる)。`hidden` / `locked` も省ける。

- 点は `[x, y]`、矩形は `[x, y, 幅, 高さ]`
- 色は `"#RRGGBB"` か `"#RRGGBBAA"`
- 線の種類 `dash` は `"solid"`(既定)/ `"dashed"` / `"dotted"` / `"dashDot"`

| type | geometry | style(`?` は省略可) | ほか |
|---|---|---|---|
| `arrow` | `from`, `to` | `color`, `width`, `arrow?`(`"tapered"` 既定 / `"open"`), `dash?`, `outline?`(白い縁取り) | |
| `line` | `from`, `to` | `color`, `width`, `dash?` | |
| `rect` / `ellipse` | `rect` | `color`, `width`, `fill?`(塗りの色), `dash?` | |
| `text` | `origin`(文字の左上) | `color`, `fontSize`, `bold?`(既定 true), `outline?`(袋文字、既定 true) | `"text": "..."`(改行は `\n`) |
| `obscure` | `rect` | `mode`(`"pixelate"` / `"blur"`), `strength`(ブロックの一辺か半径、px) | |
| `highlighter` / `pen` | `points`(`[[x, y], ...]`) | `color`, `width`, `dash?` | ハイライターは乗算 |
| `stamp` | `center` | `color`, `diameter`, `kind?`(`"letter"` / `"symbol"` / `"emoji"`。省くと数字) | `"number"`(省くと続き番号)、`"symbol"`(記号・絵文字の文字) |

- 番号を省いたスタンプは、文書にある同じ種類(数字・英字)のスタンプの続きから振る。`.kakiire` に足していくと 3, 4, … と続く
- 知らない type(`rectangle` など)と `image`(画像の貼り付け)はエラーにする。黙って描かれない注釈は作らない
- 描く順は、配列の順ではなくグループ順(モザイク・ぼかし → ハイライター → 図形)。グループの中では配列の後ろほど上

パレットの色:赤 `#E82A2A`、ピンク `#E5306B`、オレンジ `#F58A1F`、黄 `#FFD60A`、緑 `#2EB84E`、青 `#1E7CF0`、紫 `#8E44D9`、黒 `#1D1D1F`、白 `#FFFFFF`。

線の太さや文字の大きさは、`kakiire info` の `suggested` を目安にする。画像(切り抜き後)の幅に比例させた値で、幅 2000px なら矢印 `arrowWidth` 16、枠 `rectWidth` 6、線 `lineWidth` 6、文字 `fontSize` 40、スタンプ `stampDiameter` 56、モザイク `mosaicStrength` 16。

`info` の `bounds` は、注釈ごとに描かれる範囲 `[x, y, w, h]`(線の太さ・矢じり・白フチを含む)。文字には、白フチの余白を除いた文字だけの範囲 `glyphs` も付く。下線や矢印を文字に合わせるときに使う。

### 例(notes.json)

```json
[
  {"type": "rect", "geometry": {"rect": [120, 120, 500, 400]}, "style": {"color": "#E82A2A", "width": 6}},
  {"type": "arrow", "geometry": {"from": [900, 900], "to": [600, 560]}, "style": {"color": "#E82A2A", "width": 16, "outline": true}},
  {"type": "text", "geometry": {"origin": [560, 880]}, "text": "ここを押す", "style": {"color": "#E82A2A", "fontSize": 40}},
  {"type": "stamp", "geometry": {"center": [100, 900]}, "style": {"color": "#E82A2A", "diameter": 56}},
  {"type": "stamp", "geometry": {"center": [220, 900]}, "style": {"color": "#E82A2A", "diameter": 56}},
  {"type": "obscure", "geometry": {"rect": [700, 80, 250, 40]}, "style": {"mode": "pixelate", "strength": 16}}
]
```

## MCP サーバー

`kakiire mcp` は標準入出力で JSON-RPC 2.0(1行に1メッセージ)を話す。標準出力は JSON-RPC だけに使う。ローカルで動くので、画像を外に送らない。

### Claude Code に登録する

```bash
claude mcp add kakiire -- ~/.local/bin/kakiire mcp
```

すべてのプロジェクトで使うなら `-s user` を付ける。登録した後に起動したセッションから使える(起動中のセッションには入らない)。

Claude Desktop など、設定ファイルに書く場合:

```json
{
  "mcpServers": {
    "kakiire": {"command": "/Users/<you>/.local/bin/kakiire", "args": ["mcp"]}
  }
}
```

### ツール

| ツール | 引数 | 返すもの |
|---|---|---|
| `get_image_info` | `path`(絶対パス)、`preview?`(既定 true)、`preview_region?` | `info` と同じ JSON(1行)と、プレビュー画像 |
| `annotate_image` | `input`(絶対パス)、`output`(絶対パスか、その配列)、`annotations?`(上の JSON 配列)、`crop?`(`[x, y, w, h]`)、`scale?`、`force?`、`preview_region?` | 書き出した大きさと注釈の数、渡した注釈の描かれた範囲(`bounds` と同じ形)、注釈を焼き込んだプレビュー画像 |

- パスは絶対パス(`~` は使える)。相対パスはエラーにする
- `output` に配列を渡すと、1回の呼び出しで PNG と `.kakiire` などを両方書く
- プレビューは長辺 1024px に縮めてある(原寸はエージェントの文脈を圧迫するため)。縮めたときは、プレビューの座標から元画像の座標への換算式を一緒に返す
- `preview_region`(`[x, y, w, h]`、元画像のピクセル)を渡すと、全体の代わりにその範囲を長辺 1024px まで拡大して返す(4倍まで)。数 px のずれを確かめるときに使う。出力の範囲と重ならなければエラー
- エラーはツールの結果(`isError: true`)として英語の理由を返す。エージェントはそれを読んで直せる
- 扱うメソッドは `initialize` / `tools/list` / `tools/call` / `ping` だけ。プロトコルの版は `2025-06-18` / `2025-03-26` / `2024-11-05` を知っていて、クライアントが知らない版を求めたら `2025-06-18` を返す

### 頼み方の例

> `~/Desktop/shot.png` の「保存」ボタンを赤枠で囲んで、メールアドレスにモザイクをかけて、`~/Desktop/shot.kakiire` に書き出して

エージェントは `get_image_info` で大きさと中身を見てから `annotate_image` を呼ぶ。`.kakiire` で書き出せば、ずれた枠をアプリで直せる。

### 手で確かめる

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | kakiire mcp
```

## 試作の範囲

- 撮影はしない(`screencapture` の画面収録の許可がターミナルに付くため)。入力はファイルだけ
- 画像の貼り付け(`image`)、回転・反転、注釈の削除・移動はできない(足すことと切り抜き・倍率だけ)
- AI が画像を見て決める座標は数十 px ずれることがある。`preview_region` で拡大して確かめ、それでも合わなければ `.kakiire` で書き出してアプリで直す
- 文言は英語だけ
- `annotate_image` の `output` は、文字列か配列を受け付けるので、スキーマで型を `["string", "array"]` と書いている。Claude Code では使えたが、この書き方を受け付けない MCP クライアントもありうる
