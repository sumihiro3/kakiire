# LP 用のスクリーンショットを撮り直す

`site/assets/tool-*.png` と `shot-*.png` は、ここで作ったサンプル文書を実際のアプリで開いて撮ったもの。画面の見た目が変わったら、同じ手順で撮り直す。

## 1. 元にする画像を作る

`mock.html` は架空のサービスの設定画面(1280×800)。Chrome で PNG にする。

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1280,800 --user-data-dir=/tmp/lp-shots-chrome --screenshot=/tmp/lp-shots/base.png "file://$PWD/mock.html"
```

## 2. サンプル文書を作る

```bash
swift run gen /tmp/lp-shots/base.png /tmp/lp-shots/docs
```

`.kakiire` が4つと、それぞれを書き出した PNG ができる。

| 文書 | 使う場所 |
| --- | --- |
| `道具の見本.kakiire` | 01 できること(切り抜きと画像以外の10個) |
| `切り抜きの例.kakiire` | 01 できること(切り抜き) |
| `ボタンの拡大.kakiire` | 01 できること(画像)、02 画像を重ねる |
| `手順の説明.kakiire` | 03 レイヤー、04 保存と書き出しの2枚 |

## 3. アプリで開いて撮る

```bash
open -a "$PWD/../../build/DerivedData/Build/Products/Debug/Kakiire.app" /tmp/lp-shots/docs/道具の見本.kakiire
```

- ウインドウは画像が等倍で収まる大きさで開く(1280×800 の画像なら 1540×832、672×592 なら 932×629)
- ウインドウの番号は `CGWindowListCopyWindowInfo` でアプリ名「Kakiire」から引き、`screencapture -x -l<番号> out.png` で撮る。撮る前にウインドウを前面に出し、カーソルをウインドウの外へ動かす(動かすだけで、クリックはしない)
- `切り抜きの例` は切り抜きツール(C)にして、画像の (972, 186) から (1180, 310) までドラッグした状態で撮る。撮ったら Esc で取り消す
- `ボタンの拡大` は2回撮る。何も選ばない状態(道具の見本用)と、選択ツール(V)で重ねた画像をクリックして選んだ状態(02 の段用)
- `手順の説明` は矢印をクリックして選んだ状態で撮る
- 道具の選択は全ウインドウで共通なので、別のウインドウで道具を替えたあとは、選択ツールに戻してから撮る

`helpers/` に、このとき使った小さなスクリプトがある(`swift helpers/winlist.swift` のように動かす)。

| スクリプト | すること |
| --- | --- |
| `winlist.swift` | Kakiire のウインドウの番号・名前・位置を並べる |
| `move.swift x y` | カーソルを動かす(クリックしない) |
| `click.swift x y` | 画面の座標をクリックする。対象のウインドウの中だけで使う |
| `drag.swift x0 y0 x1 y1` | ドラッグする |
| `img.swift` | `bbox <画像>` で不透明な範囲を測る。`crop <入力> <出力> x y w h` で切り出す |

画面の座標は、System Events で取ったキャンバスの位置(`position of scroll area 1 of window 1`)に、画像の中の位置を足す。

## 4. 切り出して site/assets に置く

撮った PNG には影の分の透明な余白が付く(左右 56、上 38、下 74)。画像の左上は、PNG の (96, 70) に来る(672×592 の画像では上が 72 前後)。下の表の座標は画像の中の位置なので、切り出すときは (96, 70) を足す。

| ファイル | 元 | 画像の中の位置 | 大きさ |
| --- | --- | --- | --- |
| `tool-arrow.png` | 道具の見本 | (20, 184) | 256×161 |
| `tool-line.png` | 道具の見本 | (262, 44) | 256×161 |
| `tool-rect.png` | 道具の見本 | (936, 256) | 320×201 |
| `tool-ellipse.png` | 道具の見本 | (920, 426) | 256×161 |
| `tool-text.png` | 道具の見本 | (302, 560) | 256×161 |
| `tool-highlighter.png` | 道具の見本 | (300, 439) | 320×201 |
| `tool-pen.png` | 道具の見本 | (972, 560) | 256×161 |
| `tool-stamp.png` | 道具の見本 | (572, 215) | 256×161 |
| `tool-mosaic.png` | 道具の見本 | (312, 263) | 256×161 |
| `tool-blur.png` | 道具の見本 | (1024, 0) | 256×161 |
| `tool-crop.png` | 切り抜きの例 | (916, 148) | 320×201 |
| `tool-image.png` | ボタンの拡大(選択なし) | (216, 312) | 448×281 |

| ファイル | 作り方 |
| --- | --- |
| `shot-overlay.png` | `ボタンの拡大`(画像を選択中)のウインドウをそのまま(1044×741) |
| `shot-layers.png` | `手順の説明` のウインドウをそのまま(1044×741) |
| `shot-layer-panel.png` | `shot-layers.png` の (769, 70) から 219×346 を切り出す |
| `shot-export.png` | `手順の説明-export.png` をそのまま |

`site/style.css` の `.appshot--small` は、1044×741 の PNG の中に 932×629 のウインドウがある前提で、ウインドウの縁が段の幅に合うようにしている。ウインドウの大きさが変わったら、そこの比率も直す。

道具の見本は、切り出す範囲に他の注釈が入らないように注釈を置いている。注釈の位置を変えたら、切り出す位置も見直す。
