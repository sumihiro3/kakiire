# 別の Mac に入れる

Kakiire はまだ ad-hoc 署名(Developer ID なし・公証なし)。Apple Silicon の macOS 15 以降で動く。

## 1. 配布用 zip を作る(ビルドする Mac で)

```bash
./scripts/package.sh
```

`dist/Kakiire-<version>.zip` ができる。

## 2. 別の Mac にコピーして入れる

AirDrop・iCloud Drive・Google ドライブなど、好きな方法で zip を送る。受け取った Mac で:

```bash
ditto -x -k ~/Downloads/Kakiire-0.1.0.zip /Applications
xattr -dr com.apple.quarantine /Applications/Kakiire.app
open /Applications/Kakiire.app
```

`xattr` を付けずに開くと「Apple は検証できませんでした」と出て開けない。その場合は「システム設定 › プライバシーとセキュリティ」の下にある「このまま開く」でも通せる(macOS 15 から、Control + クリックで開く方法は使えない)。

## 別案:その Mac でビルドする

Xcode と XcodeGen(`brew install xcodegen`)があれば、リポジトリを clone して `./scripts/package.sh` を実行し、`dist/` の zip を展開するだけ。自分でビルドしたアプリには隔離属性が付かないので、`xattr` は要らない。

## 更新するとき

同じ手順で `/Applications/Kakiire.app` を置き換える。
