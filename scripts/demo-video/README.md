# 操作動画を撮り直す

LP の `site/assets/demo.mp4`(英語は `site/assets/en/demo.mp4`)と、README の `docs/readme/demo.gif`(`demo-en.gif`)は、ここのスクリプトで撮ったもの。実際のアプリ(Release ビルド)を、スクリプトでマウスを動かして操作し、画面を録画している。画面の見た目や道具の並びが変わったら撮り直す。

撮る流れは、矢印 → 文字 → 四角 → モザイク → 番号スタンプ ①② → 文字を少し動かす → 道具の列の取っ手からデスクトップへ持ち出す(25 秒ほど)。

## 前提

- 画面は 2560×1080 の 1 倍の画面で撮った。撮る範囲(`take.sh` の `REGION`)とウインドウの位置(`WX`・`WY`)は、この画面に合わせてある。ほかの画面では、ウインドウの右にデスクトップが 160px ほど見えるように置き直す
- ffmpeg(`brew install ffmpeg`)
- 動かすアプリ(ターミナルなど)に「画面収録」と「アクセシビリティ」の許可が要る。許可がないと、録画が真っ黒になったり、クリックが届かなかったりする
- `swiftc` で `act.swift` をビルドする(`take.sh` が `build/demo-video/act` に作る)

## 1. 元にする画像を作る

LP のスクリーンショットと同じ架空の設定画面(`scripts/lp-shots/mock.html`)を使う。ファイル名がウインドウのタイトルと、持ち出したファイルの名前になる。

```bash
mkdir -p /tmp/demo-video/en
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1280,800 --user-data-dir=/tmp/demo-video/chrome --screenshot=/tmp/demo-video/設定画面.png "file://$PWD/scripts/lp-shots/mock.html"
```

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1280,800 --user-data-dir=/tmp/demo-video/chrome --screenshot=/tmp/demo-video/en/Settings.png "file://$PWD/scripts/lp-shots/mock-en.html"
```

## 2. 画面を片付ける

- Release ビルドを作っておく(`xcodebuild … -configuration Release …`)
- 撮る範囲に写るものを隠す。ほかのアプリは隠す(⌥⌘H)、Finder のウインドウは Dock にしまう。デスクトップのウィジェットが撮る範囲の左上に入らないか確かめる
- 通知を切る(集中モード)
- デスクトップに、前に持ち出した `設定画面.png`・`Settings.png` が残っていたら消す(`take.sh` は自分の言語の分しか消さない)

## 3. 撮る

撮っているあいだ(30 秒ほど)は、マウスにもキーボードにも触らない。

```bash
./scripts/demo-video/take.sh /tmp/demo-video/設定画面.png /tmp/demo-video/take-ja.mp4 "ここを押す"
```

```bash
./scripts/demo-video/take.sh /tmp/demo-video/en/Settings.png /tmp/demo-video/take-en.mp4 "Click here" en
```

## 4. 書き出して置く

```bash
./scripts/demo-video/encode.sh /tmp/demo-video/take-ja.mp4 ja /tmp/demo-video/out
```

```bash
./scripts/demo-video/encode.sh /tmp/demo-video/take-en.mp4 en /tmp/demo-video/out
```

| できるファイル | 置き場所 |
| --- | --- |
| `demo-ja.mp4`・`demo-poster-ja.jpg` | `site/assets/demo.mp4`・`demo-poster.jpg` |
| `demo-en.mp4`・`demo-poster-en.jpg` | `site/assets/en/demo.mp4`・`demo-poster.jpg` |
| `demo-ja.gif`・`demo-en.gif` | `docs/readme/demo.gif`・`demo-en.gif` |
| `kakiire-demo-*-1080p.mp4` | リポジトリには入れない(YouTube や X に載せる元) |

## 気をつけること

- 道具の選択は前回のものが残るので、`take.sh` は撮る前に選択ツールへ戻す
- 文字は `CGEvent` に Unicode の文字を載せて打つので、入力ソースが日本語でもそのまま入る
- 座標を変えたいときは、`act` で同じ操作を録画せずに流し、`screencapture -x -R600,100,1742,980` で撮って確かめてから録画する。間違えたら、`take.sh` がアプリを起動し直すので、そのまま撮り直せる
