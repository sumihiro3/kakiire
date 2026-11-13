# 別の Mac にインストールする

Kakiire は Apple Development 署名(Developer ID なし・公証なし)。Apple Silicon の macOS 15 以降で動く。

## 1. 配布用 zip を作る(ビルドする Mac で)

```bash
./scripts/package.sh
```

`dist/Kakiire-<version>.zip` ができる。

## 2. 別の Mac にコピーしてインストールする

AirDrop・iCloud Drive・Google ドライブなど、好きな方法で zip を送る。受け取った Mac で:

```bash
ditto -x -k ~/Downloads/Kakiire-0.8.0.zip /Applications
xattr -dr com.apple.quarantine /Applications/Kakiire.app
open /Applications/Kakiire.app
```

`ditto` が `ditto: /Applications: Operation not permitted` で止まることがある(2026-11-12、MBP で発生)。`Permission denied` ではないので、ファイルの権限ではなく macOS の保護(「App 管理」)か、管理者でないユーザーが疑わしい。原因は確かめていない。次のどちらかで入れる:

- 自分用の `~/Applications` に入れる。Launchpad・Spotlight・Quick Look 拡張はそのまま使える

  ```bash
  mkdir -p ~/Applications && ditto -x -k ~/Downloads/Kakiire-0.8.0.zip ~/Applications
  xattr -dr com.apple.quarantine ~/Applications/Kakiire.app
  open ~/Applications/Kakiire.app
  ```

- `~/Downloads` に展開し、Finder で `Kakiire.app` を「アプリケーション」へドラッグする(パスワードを求められる)。そのあと上と同じく `xattr` と `open` を `/Applications/Kakiire.app` に対して行う

  ```bash
  ditto -x -k ~/Downloads/Kakiire-0.8.0.zip ~/Downloads/Kakiire-0.8.0 && open ~/Downloads/Kakiire-0.8.0
  ```

ターミナルのまま `/Applications` に入れたいときは、「システム設定 › プライバシーとセキュリティ › App 管理」で使っているターミナルをオンにする(既存の `Kakiire.app` を上書きする場合に効くはず。未確認)。

`xattr` を付けずに開くと「Apple は検証できませんでした」と出て開けない。その場合は「システム設定 › プライバシーとセキュリティ」の下にある「このまま開く」でも通せる(macOS 15 から、Control + クリックで開く方法は使えない)。

## 3. スクリーンショットの許可

撮影(⌃⇧⌘5・メニューバー・カメラのボタン)には画面収録の許可が要る。「システム設定 › プライバシーとセキュリティ › 画面とシステムオーディオの録音」で Kakiire をオンにして、Kakiire を起動し直す。

0.2.0 以前(ad-hoc 署名)で許可を入れていた場合、その登録は 0.3.0 には当てはまらない。一度消してから入れ直す:

```bash
tccutil reset ScreenCapture com.tep-lab.kakiire
```

0.3.0 からは Apple Development 署名なので、更新しても許可は残る。

## 別案:その Mac でビルドする

Xcode と XcodeGen(`brew install xcodegen`)があれば、リポジトリを clone して `./scripts/package.sh` を実行し、`dist/` の zip を展開するだけ。自分でビルドしたアプリには隔離属性が付かないので、`xattr` は要らない。

署名には「Apple Development: Sumihiro Kagawa」の証明書(チーム EBBVRDHK5Z)が要る。その Mac のキーチェーンになければ、Xcode の設定で同じ Apple ID にサインインして証明書を作るか、ad-hoc 署名でビルドする(画面収録の許可はビルドのたびに外れる):

```bash
xcodebuild -project Kakiire.xcodeproj -scheme Kakiire -configuration Release -derivedDataPath build/DerivedData build CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

## 更新するとき

同じ手順で `/Applications/Kakiire.app` を置き換える。
