# 「ショートカット」対応(App Intents)

## 決定

| 項目 | 決定 |
|---|---|
| 作るアクション | 範囲を撮って開く(`CaptureScreenshotIntent`)/画像を開く(`OpenImageIntent`)/`.kakiire` を画像に書き出す(`ExportDocumentIntent`)/編集中の画像を取得(`CurrentImageIntent`)の4つ |
| 作らないもの | 枠・矢印・モザイクを付けるアクション。座標をショートカットの画面で入れるのは使いにくく、CLI / MCP(ADR 0007)が受け持つ |
| 置き場所 | App の `App/Sources/Intents`。処理は IO を呼ぶだけ。`.kakiire` → 画像は `ImageExport.data(ofArchive:format:scale:)`(IO、テストあり) |
| アプリを前に出すか | 撮る・開くは出す(`openAppWhenRun`)。書き出し・取得は出さない |
| 倍率 | 書き出しの「倍率(%)」は省略可。渡すと文書の「画像サイズ」(`outputScale`)を置き換える。MCP の export と同じ意味 |
| 取り消し | 撮影を Esc で取り消したら、エラーにせず何もせずに終える |
| 文書がないとき | 「編集中の画像を取得」はエラー(「Kakiire で開いている画像がありません。」)を返す |
| Spotlight / Siri | `AppShortcutsProvider` で「範囲を撮る」「編集中の画像」を出す。フレーズの英訳は `AppShortcuts.xcstrings` |
| ファイルの受け渡し | `IntentFile` のデータで受け渡す。サンドボックスの entitlements は変えない(実機で、`.kakiire` を読んで JPEG を返せることを確かめた) |
| 署名 | 今の Apple Development 署名のまま。Developer ID に替えてもコードは変わらない |

## 見直す条件

- Apple が App Intents を MCP として外に出す仕組みを公開したとき(ADR 0008)
- 「最新のスクショに枠を付けたい」など、注釈を付けるアクションを求める声が続いたとき
