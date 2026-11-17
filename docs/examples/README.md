# 使用例

Claude Code などの AI エージェントに、Kakiire の MCP サーバーで画像の注釈を頼んだ例。どれも元の画像・頼んだ文・付けた注釈(JSON)を置いているので、CLI で同じものを作ったり、`.kakiire` をアプリで開いて直したりできる。AI がずれや隠し漏れに気づいて直した所も、それぞれの例に書いている。

元の画面は、どれもこの例のために作った架空のもの([screens/](screens/))。MCP サーバーの入れ方と注釈の形は [docs/cli.md](../cli.md) にある。

| 例 | すること | 主に使うもの |
|---|---|---|
| [設定画面に、操作の手順を番号で書き入れる](settings-steps/README.md) | 押す場所を赤枠で囲み、①②③と吹き出しで手順を示す | `rect`・`stamp`・`bubble` |
| [必要な所だけ切り抜いて、新機能を知らせる](settings-crop/README.md) | サイドバーだけ切り抜き、「新機能」を丸と吹き出しで強調する | `crop`・`ellipse`・`bubble` |
| [メール画面の個人情報を、ひと言で隠す](mail-privacy/README.md) | 名前・アドレス・電話番号・名前入りのアイコンの20か所を隠す | `obscure` |
| [フォルダのスクショを、まとめて隠して縮める](mail-batch/README.md) | 3枚から自分のアドレスを隠し、半分の大きさで書き出す | `obscure`・`scale` |
| [ニュースサイトのスクショに、まとめてモザイクをかける](news-mosaic/README.md) | 記事の写真・ロゴ・媒体のアイコン・地名など16か所を隠す | `obscure` |

| 手順書 | 切り抜き |
|---|---|
| ![手順書の例](settings-steps/after.png) | ![切り抜きの例](settings-crop/after.png) |
| **個人情報を隠す** | **ニュースサイトのモザイク** |
| ![個人情報を隠す例](mail-privacy/after.png) | ![ニュースサイトのモザイクの例](news-mosaic/after.png) |
