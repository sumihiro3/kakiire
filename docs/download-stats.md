# ダウンロード数を記録する

アプリ(DMG)と CLI(zip)のダウンロード数を、手元の Mac で毎日記録する。方針は ADR 0008 の追記(数は GitHub Releases のファイルごとの `download_count`。brew で入れた分も含む)。

## 何を記録するか

`scripts/download-stats.py <出力先>` が、出力先に3つのファイルを書く。同じ日に何度実行しても、その日の行を置き換えるだけ。

| ファイル | 中身 |
|---|---|
| `assets.csv` | 日付・タグ・ファイル名・種類(`app` / `cli`)・その時点の累計ダウンロード数。Releases のすべてのファイル |
| `traffic.csv` | 日付・リポジトリ・`clones` / `views`・回数・人数。本体と tap(`sumihiro3/homebrew-tap`)。GitHub は 14 日分しか持たないので、毎日写して残す |
| `summary.md` | 最新の累計と、1日前・7日前からの増え方、版ごとの数、直近 14 日の traffic |

- 種類はファイル名で分ける。小文字の `kakiire-` で始まるものが CLI、それ以外がアプリ
- 数は回数で、人数ではない。`brew upgrade` や入れ直し、自分の確認も1回に数える
- tap の clones は、`brew tap`(初回の `brew install sumihiro3/tap/...` を含む)と `brew update` の目安
- GitHub への問い合わせは `gh`(認証済み)を使う。traffic は push 権限が要る

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
