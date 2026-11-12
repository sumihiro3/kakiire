# 版を上げて出す

変更履歴は `CHANGELOG.md`、タグは `v<版>`(例 `v0.8.0`)。方針は ADR 0010。

## ふだん(PR ごと)

PR 本文の「## 変更履歴」の欄に、使う人から見える変化を「- 」で1行ずつ書く(`.github/pull_request_template.md` に欄がある)。

| 欄の中身 | 版を上げるときの扱い |
| --- | --- |
| 「- 」の行 | 1行ずつ項目にする。末尾に `(#PR番号)` が付く |
| 「なし」 | 載せない(LP・CI・文書だけの変更など) |
| 空・欄がない | PR の件名を項目にする |

あとから欄を直してもよい。読むのは版を上げるときだけ。

## 版を上げる

1. 最新の main からブランチを切る(機能の PR に版上げを入れてもよい)
2. 何が入るかを見る

   ```bash
   ./scripts/bump-version.sh 0.8.0 --dry-run
   ```

3. 書き換える。`CHANGELOG.md` に `## 0.8.0 — 日付` の節ができ、版の表記(`project.yml`・`KakiireTool.appVersion`・LP 2つ・`docs/install.md`)が変わる

   ```bash
   ./scripts/bump-version.sh 0.8.0
   ```

4. `CHANGELOG.md` の節を読んで直す(言い回し・並び・まとめる)。`docs/plan.md` に版の節を足すのは今までどおり
5. `swift test`(`KakiireTool.appVersion` と `MARKETING_VERSION` の一致を確かめる)を通して、コミットし PR を出す
6. マージすると、Actions(`.github/workflows/release.yml`)がタグ `v0.8.0` と GitHub Release を作る。本文は `CHANGELOG.md` の節
7. 配布用 zip を Release に付ける(CI では署名できないので手元で作る)

   ```bash
   git switch main && git pull && ./scripts/package.sh
   ```

   ```bash
   gh release upload v0.8.0 dist/Kakiire-0.8.0.zip
   ```

## うまくいかないとき

- 前の版のタグがない:`--since <コミット>` で起点を指定する
- Release を作り直したい:GitHub で Release とタグを消してから、Actions の「Release」を「Run workflow」で手で動かす(タグがなければ作る)
- `CHANGELOG.md` に節がないまま版を上げてマージした:Actions が失敗する。節を足してマージし直せば作られる
