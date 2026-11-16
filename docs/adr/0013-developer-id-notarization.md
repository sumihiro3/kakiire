# Developer ID 署名・公証した DMG で配る

手順は `docs/release.md`(作る側)と `docs/install.md`(入れる側)。

## 決定

| 項目 | 決定 |
|---|---|
| 配り方 | 最初の公開は、Developer ID で署名し公証した DMG にする。Mac App Store には今は出さない |
| 署名 | Release 構成だけ「Developer ID Application」(チーム EBBVRDHK5Z)。Debug は「Apple Development」のまま。App と Quick Look 拡張2つとも同じ |
| 公証の条件 | Hardened Runtime(前から有効)、安全なタイムスタンプ(`OTHER_CODE_SIGN_FLAGS: --timestamp`)、`get-task-allow` を付けない(`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`)。`scripts/package.sh` が提出の前にこの3つを確かめる |
| 作り方 | `xcodebuild build`(Release)のアプリをそのまま使う。アーカイブと書き出し(`-exportArchive`)は使わない |
| 配布物 | `dist/Kakiire-<版>.dmg`。中身はアプリと /Applications へのリンク。DMG にも署名し、DMG を公証に出して DMG に staple する |
| 公証の認証 | App Store Connect API キー(チームキー、Developer 権限)。`notarytool` のキーチェーンのプロファイル `kakiire-notary` に入れ、スクリプトは名前だけを使う |
| どこで作るか | 手元の Mac。GitHub Actions での署名・公証は後で検討する |

## 理由

- App Store を先にしない:CLI / MCP はストア版に同梱できず(ADR 0008)、どのみち別に配る。無料・OSS なので、ストアの課金の仕組みは要らない。審査を待たずに出せる。サンドボックスはもう有効なので、App Store 版は後から足せる
- Release だけ Developer ID にする:公証できるのは Developer ID の署名だけ。Debug まで変えると、Developer ID の証明書を持たない Mac で開発できなくなる
- `get-task-allow` を明示的に止める:`xcodebuild build` は、Release でも `get-task-allow` を付けた(2026-11-16 に確認)。アーカイブして書き出せば外れるが、ビルドの設定で止めるほうが手順が少ない。設定を変えた直後は、前のビルドの拡張が署名し直されずに残ることがあったので、スクリプトで entitlements を読んで確かめる
- アプリには staple しない:DMG を公証すると中のアプリも公証済みになり、Gatekeeper はアプリの分のチケットをネットから取りに行く。アプリにも staple するには、アプリを先に公証してから DMG を作り直し、もう一度公証する必要がある。2回出す手間に見合わないので、DMG だけにした
- DMG にした:ダウンロードしてドラッグするだけで入る。zip のように展開した場所(`~/Downloads`)にアプリが残ることもない

## 影響

- 指定要件が変わる。Apple Development のときは証明書の名前(`leaf[subject.CN]`)で決まっていたが、Developer ID ではチーム ID(`leaf[subject.OU] = EBBVRDHK5Z`)で決まる。そのため、0.11.0 以前の版で入れた画面収録の許可は、一度だけ外れる。これから先は、版を上げても、証明書を作り直しても、許可は残る
- 証明書を持たない Mac で Release ビルドするときは、`CODE_SIGN_IDENTITY` を上書きする(`docs/install.md`)

## 見直す条件

- GitHub Actions で署名・公証するとき。証明書(.p12)と API キー(.p8)を Secrets に入れる
- App Store 版を足すとき
- 自動更新(Sparkle など)を入れるとき
