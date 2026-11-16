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

3. 書き換える。`CHANGELOG.md` に `## 0.8.0 — 日付` の節ができ、版の表記(`project.yml`・`KakiireTool.appVersion`・LP 2つ・`docs/cli.md`)が変わる

   ```bash
   ./scripts/bump-version.sh 0.8.0
   ```

4. `CHANGELOG.md` の節を読んで直す(言い回し・並び・まとめる)。`docs/plan.md` に版の節を足すのは今までどおり
5. `swift test`(`KakiireTool.appVersion` と `MARKETING_VERSION` の一致を確かめる)を通して、コミットし PR を出す
6. マージすると、Actions(`.github/workflows/release.yml`)が **下書き**の GitHub Release `v0.8.0` を作る。本文は `CHANGELOG.md` の節。下書きのうちは「最新版」が前の版のままなので、LP の「ダウンロード」(`releases/latest/download/Kakiire.dmg`)は前の版の DMG を落とし続ける
7. 配布物を作って下書きの Release に付ける(CI では署名できないので手元で作る)。アプリの DMG は `package.sh`、CLI の zip は `package-cli.sh` が、Developer ID の署名から公証までを行う(どちらも1分ほど)

   ```bash
   git switch main && git pull && ./scripts/package.sh && ./scripts/package-cli.sh
   ```

   ```bash
   gh release upload v0.8.0 dist/Kakiire.dmg dist/kakiire-0.8.0-macos-arm64.zip
   ```

   DMG の名前は版を含まない `Kakiire.dmg`(LP が最新版を直接指すため。ADR 0013)。版はタグで分かる

8. Release を公開する。このときタグ `v0.8.0` ができ、「最新版」と LP のダウンロードが新しい版に切り替わる

   ```bash
   gh release edit v0.8.0 --draft=false --latest
   ```

   公証が通ってから数分(2026-11-16 は約6分)は、ブラウザでダウンロードした CLI(隔離属性つき)を Gatekeeper が「未公証」として止める(終了コード 137)。DMG は staple してあるので止まらない。Releases に付けたら、数分おいてから `spctl -a -vv -t install <展開した kakiire>` が `source=Notarized Developer ID` になるのを確かめる

9. Homebrew tap([sumihiro3/homebrew-tap](https://github.com/sumihiro3/homebrew-tap))の版と sha256 を書き換えてプッシュする。`Casks/kakiire.rb`(アプリ)は `version` と `sha256`(`url` は `v#{version}/Kakiire.dmg` なので触らない)、`Formula/kakiire.rb`(CLI)は `url` の版と `sha256`。sha256 は:

   ```bash
   shasum -a 256 dist/Kakiire.dmg dist/kakiire-0.8.0-macos-arm64.zip
   ```

   確かめる:

   ```bash
   brew update && brew upgrade --cask sumihiro3/tap/kakiire && brew upgrade sumihiro3/tap/kakiire && kakiire --version
   ```

## 署名の準備(Mac ごとに1回)

`package.sh` と `package-cli.sh` には、次の2つが要る。方針は ADR 0013。

- キーチェーンに「Developer ID Application: Sumihiro Kagawa (EBBVRDHK5Z)」の証明書と秘密鍵。ほかの Mac には、作った Mac で `.p12` に書き出して読み込む(1Password に保管してある)。確かめる:

  ```bash
  security find-identity -v -p codesigning
  ```

- 公証用の App Store Connect API キーを、`notarytool` のプロファイル `kakiire-notary` として登録しておく。キーは App Store Connect › ユーザとアクセス › 統合 › チームキー(Developer 権限)で作る。`.p8` は1度しかダウンロードできない(1Password に保管してある)

  ```bash
  xcrun notarytool store-credentials kakiire-notary --key ~/.appstoreconnect/private_keys/AuthKey_<KeyID>.p8 --key-id <KeyID> --issuer <IssuerID>
  ```

  確かめる(エラーにならなければよい):

  ```bash
  xcrun notarytool history --keychain-profile kakiire-notary
  ```

公証せずに中身だけ確かめたいときは `./scripts/package.sh --no-notarize`。この DMG は、ほかの Mac では Gatekeeper に止められる。

## うまくいかないとき

- 前の版のタグがない:`--since <コミット>` で起点を指定する
- Release を作り直したい:GitHub で Release とタグを消してから、Actions の「Release」を「Run workflow」で手で動かす(タグがなければ作る)
- `CHANGELOG.md` に節がないまま版を上げてマージした:Actions が失敗する。節を足してマージし直せば作られる
- 公証が通らない:`package.sh` が出す `xcrun notarytool log <id> --keychain-profile kakiire-notary` で理由を読む
- `package.sh` が「get-task-allow が付いている」で止まる:前のビルドの拡張が署名し直されずに残っている。`rm -rf build/DerivedData/Build/Products/Release` してから作り直す
- 下書きの Release を消したい・作り直したい:下書きにはタグがないので、GitHub で Release を消してから、Actions の「Release」を「Run workflow」で動かす
