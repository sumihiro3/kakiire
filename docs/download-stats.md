# ダウンロード数を記録する

アプリ(DMG)と CLI(zip)のダウンロード数と、LP の訪問数を、手元の Mac で毎日記録する。方針は ADR 0008 の追記(数は GitHub Releases のファイルごとの `download_count`。brew で入れた分も含む)。

## 何を記録するか

`scripts/download-stats.py <出力先>` が、出力先に4つのファイルを書く。同じ日に何度実行しても、その日の行を置き換えるだけ。

| ファイル | 中身 |
|---|---|
| `assets.csv` | 日付・タグ・ファイル名・種類(`app` / `cli`)・その時点の累計ダウンロード数。Releases のすべてのファイル |
| `traffic.csv` | 日付・リポジトリ・`clones` / `views`・回数・人数。本体と tap(`sumihiro3/homebrew-tap`)。GitHub は 14 日分しか持たないので、毎日写して残す |
| `web.csv` | 日付・LP のパス・参照元のホスト・ページビュー・訪問数。Cloudflare Web Analytics から。数は後から少し増えることがあるので、毎回直近 7 日分を取り直して置き換える |
| `summary.md` | 最新の累計と、1日前・7日前からの増え方、版ごとの数、直近 14 日の traffic、LP の訪問(7日・30日)と参照元、7日のダウンロード数 ÷ 訪問数 |

- 種類はファイル名で分ける。小文字の `kakiire-` で始まるものが CLI、それ以外がアプリ
- 数は回数で、人数ではない。`brew upgrade` や入れ直し、自分の確認も1回に数える
- tap の clones は、`brew tap`(初回の `brew install sumihiro3/tap/...` を含む)と `brew update` の目安
- GitHub への問い合わせは `gh`(認証済み)を使う。traffic は push 権限が要る

## LP の訪問数(Cloudflare Web Analytics)

LP には Cloudflare Web Analytics を入れている(Pages の設定で、配信時にビーコンが足される。`site/` の HTML には書かない。手元のプレビューで数えないため)。Cookie は使わない。LP のフッターにそう書いている。

数を取るには、最初に1回、次の3つを用意する。どれかがないと `web.csv` は書かず、ダウンロード数の記録だけ続ける。

1. **Web Analytics を有効にする**:Cloudflare のダッシュボードで **Workers & Pages** → `kakiire` → **Metrics** → Web Analytics の **Enable**。次のデプロイからビーコンが入る
2. **API トークンを作り、キーチェーンに入れる**:**My Profile** → **API Tokens** → **Create Token** → **Custom token**。権限は **Account** → **Account Analytics** → **Read** だけ。できたトークンを次で入れる(`-w` の後ろを空にすると、入力を求められる。履歴に残さないため)

```bash
security add-generic-password -U -s kakiire-cloudflare-analytics -a "$USER" -w
```

3. **アカウントとサイトの ID を書く**:出力先に `cloudflare.json` を置く。`account_tag` はダッシュボードの URL の `dash.cloudflare.com/<ここ>/...`。`site_tag` は **Analytics & Logs** → **Web Analytics** で `kakiire.tep-lab.com` を開いたときの URL の `siteTag~in=<ここ>`

```bash
cat > ~/Library/Application\ Support/Kakiire/download-stats/cloudflare.json <<'JSON'
{"account_tag": "<アカウント ID>", "site_tag": "<サイトのタグ>"}
JSON
```

- 訪問は、ほかのサイトから来た(またはアドレスを打って開いた)回数。ページビューは再読み込みなども1回に数える。bot は除く
- 参照元はホスト名だけ(X から来ると `t.co`)。ない場合は `(direct)`
- 「7日のダウンロード ÷ 訪問」は目安。ダウンロードには brew や GitHub から直接落とした分も入る
- 問い合わせに失敗したときは、ログに `web: failed: …` と出して、ほかの記録は続ける

## 毎日動かす(launchd)

```bash
mkdir -p ~/Library/LaunchAgents && sed "s|/Users/YOU|$HOME|g" scripts/download-stats.plist > ~/Library/LaunchAgents/com.tep-lab.kakiire.download-stats.plist && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.tep-lab.kakiire.download-stats.plist
```

毎朝 9:00 に `~/Library/Application Support/Kakiire/download-stats` へ書く。リポジトリは `/opt/dev/Kakiire` にある前提(違うなら plist の `ProgramArguments` を直す)。ログは `~/Library/Logs/kakiire-download-stats.log`。

すぐ1回動かして確かめる:

```bash
launchctl kickstart gui/$(id -u)/com.tep-lab.kakiire.download-stats && sleep 5 && cat ~/Library/Logs/kakiire-download-stats.log
```

止める:

```bash
launchctl bootout gui/$(id -u)/com.tep-lab.kakiire.download-stats
```

### iCloud 上のフォルダには直接書けない

launchd から動かしたプロセスは、iCloud Drive にある別のアプリのフォルダ(Obsidian の Vault など)に書くと `Operation not permitted` で拒まれる(2026-11-16 に確認。macOS の保護。許可を求める画面も出ない)。そのため出力先はローカルにし、Vault へは別の仕組みで写す(作者の環境では、Claude Code の定期タスクが毎朝コピーしている)。
