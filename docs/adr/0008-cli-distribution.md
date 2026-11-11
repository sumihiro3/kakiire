# CLI と MCP サーバーの配り方

CLI と MCP サーバーそのものの方針は ADR 0007、使い方は `docs/cli.md`。

## 決定

| 項目 | 決定 |
|---|---|
| 配り方 | `kakiire`(CLI と MCP サーバー)は **App とは別に配る**。App は CLI を同梱せず、インストールもしない |
| App から CLI への案内 | 設定などに、入手先へのリンクと、入れるコマンド・Claude Code に登録するコマンドをコピーするボタンだけを置く(ファイルは書かない)。作るかどうか、いつ作るかは別に決める |
| CLI の署名 | Developer ID と Hardened Runtime で署名し、公証する。**サンドボックスは付けない**(引数で受け取ったパスを読むため)。Apple Developer Program に入るまでは、ソースからビルドする |
| 入手先 | 主な入手先は Homebrew tap。同じ zip を GitHub Releases にも置く。このリポジトリは private なので、tap と配布物は公開の場所に置く(置き場所は公開するときに決める) |
| バージョン | App と同じ `MARKETING_VERSION` を使い、同じタグで出す(`KakiireTool.appVersion` はテストで合わせてある) |
| App Intents | AI から使う道としては採らない。ショートカット・Siri・Spotlight から使う機能として、別に検討する |

## 理由

- App Store で出す道を残すため。App Store の App は、共有の場所にコードを置けない(ガイドライン 2.4.5 の (ii)(viii) で却下された例がある)。サンドボックスの CLI は引数のパスを読めないので、同梱しても役に立たない。TextWrangler は App Store 版からコマンドラインツールを外し、別のインストーラーを配っていた
- 今の配り方(Developer ID の zip・DMG、handoff.md)でも、別に配れば困らない。CLI は Core / IO だけに依存し、App を必要としない
- App Intents を MCP として外に出す公式の仕組みは見当たらない(2026-11 時点)。WWDC26 で MCP が出てきたのは Xcode だけで、Omni Group も「App Intents には MCP が来なかった」と書いている。手元の SDK(Xcode 26.4)の AppIntents.framework にも MCP の記述はない。非公式の橋渡し(intents-mcp)は、ショートカットをツールごとに手で登録する必要があり、画像の受け渡しも説明されていない

## 見直す条件

- Apple が App Intents を外部の MCP クライアントに開いたとき。App Intents で同じことができるなら、CLI を別に配る必要は減る
- App Store で出すと決めたとき。App の案内(リンクとコマンドのコピー)が審査で問題にならないかを確かめる
