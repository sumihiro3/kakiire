# インストールする

Kakiire は Developer ID で署名し、Apple の公証を受けた DMG で配る(ADR 0013)。Apple Silicon の macOS 15 以降で動く。

## 1. 入れる

1. `Kakiire-0.11.0.dmg` をダウンロードして開く
2. 開いたウインドウで、`Kakiire.app` を「Applications」へドラッグする
3. 「アプリケーション」フォルダから Kakiire を開く。初回は「インターネットからダウンロードされたアプリケーションです」と出るので「開く」を押す

公証済みなので、`xattr` で隔離属性を外す必要はない。「Apple は検証できませんでした」と出たら、公証されていない DMG を開いている(`./scripts/package.sh --no-notarize` で作ったものなど)。

ターミナルで入れるときは:

```bash
hdiutil attach -nobrowse ~/Downloads/Kakiire-0.11.0.dmg && ditto /Volumes/Kakiire/Kakiire.app /Applications/Kakiire.app && hdiutil detach /Volumes/Kakiire && open /Applications/Kakiire.app
```

`ditto` が `ditto: /Applications: Operation not permitted` で止まることがある(2026-11-12、MBP で発生)。`Permission denied` ではないので、ファイルの権限ではなく macOS の保護(「App 管理」)か、管理者でないユーザーが疑わしい。原因は確かめていない。Finder でドラッグして入れるか、自分用の `~/Applications` に入れる(Launchpad・Spotlight・Quick Look 拡張はそのまま使える)。ターミナルのまま `/Applications` に入れたいときは、「システム設定 › プライバシーとセキュリティ › App 管理」で使っているターミナルをオンにする(既存の `Kakiire.app` を上書きする場合に効くはず。未確認)。

## 2. スクリーンショットの許可

撮影(⌃⇧⌘5・メニューバー・カメラのボタン)には画面収録の許可が要る。「システム設定 › プライバシーとセキュリティ › 画面とシステムオーディオの録音」で Kakiire をオンにして、Kakiire を起動し直す。

0.11.0 以前(Apple Development 署名・ad-hoc 署名)の版で許可を入れていた場合、その登録は Developer ID 署名の版には当てはまらない。一覧に Kakiire が出ているのに撮れないときは、一度消してから入れ直す:

```bash
tccutil reset ScreenCapture com.tep-lab.kakiire
```

Developer ID 署名の版どうしなら、更新しても許可は残る(指定要件がチーム ID で決まるため)。

## 別案:その Mac でビルドする

Xcode と XcodeGen(`brew install xcodegen`)があれば、リポジトリを clone してビルドできる。自分でビルドしたアプリには隔離属性が付かないので、公証は要らない。

Release 構成は「Developer ID Application: Sumihiro Kagawa」の証明書(チーム EBBVRDHK5Z)で署名する。その Mac のキーチェーンになければ、署名を上書きしてビルドする:

```bash
xcodegen generate && xcodebuild -project Kakiire.xcodeproj -scheme Kakiire -configuration Release -derivedDataPath build/DerivedData build CODE_SIGN_IDENTITY="Apple Development"
```

Apple Development の証明書もないときは、ad-hoc 署名にする(画面収録の許可はビルドのたびに外れる):

```bash
xcodegen generate && xcodebuild -project Kakiire.xcodeproj -scheme Kakiire -configuration Release -derivedDataPath build/DerivedData build CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

できたアプリは `build/DerivedData/Build/Products/Release/Kakiire.app`。

## 更新するとき

新しい版の DMG から、同じ手順で `/Applications/Kakiire.app` を置き換える。

### 置き換えた後、⌘Tab と Dock のアイコンが出ないとき

アプリの中のアイコンは正しくても、その Mac に残っている古いアイコンのキャッシュが使われることがある(2026-11-15 に MBP で起きた。Finder では出て、起動中の ⌘Tab と Dock だけ空になった)。Kakiire を終了してから、上から順に試す。

1. 同じアプリのコピーが `/Applications` 以外(`~/Downloads` など)に残っていないか確かめ、あれば消す

   ```bash
   mdfind "kMDItemCFBundleIdentifier == 'com.tep-lab.kakiire'"
   ```

2. アプリを登録し直して Dock を起動し直す

   ```bash
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Kakiire.app && killall Dock
   ```

3. アイコンのキャッシュを消し、アイコンを扱うプロセスと Dock を起動し直す(管理者のパスワードが要る。MBP ではこれで直った。OS の再起動は要らなかった)

   ```bash
   sudo rm -rf /Library/Caches/com.apple.iconservices.store
   ```

   ```bash
   sudo killall iconservicesd; killall Dock
   ```
