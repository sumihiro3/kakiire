# フォルダのスクショを、まとめて隠して縮める

メール画面のスクショ3枚から、人の名前・メールアドレス・電話番号・住所を隠し、半分の大きさにして書き出した例。ブログや資料に何枚も貼るときを想定している。

| | 元の画像(2560×1600) | 書き出した画像(1280×800) |
|---|---|---|
| 1 | ![](screenshots/mail-1.png) | ![](out/mail-1.png) |
| 2 | ![](screenshots/mail-2.png) | ![](out/mail-2.png) |
| 3 | ![](screenshots/mail-3.png) | ![](out/mail-3.png) |

## 頼んだこと

```text
screenshots フォルダのスクショ全部で、人の名前とメールアドレスを隠して。
電話番号や住所も隠して。半分の大きさで out フォルダに書き出して
```

## AI がしたこと

1. `get_image_info` で3枚を見て、どの画像でも同じ位置にあるものと、画像ごとに位置が違うものに分ける
   - **同じ位置(16か所)**:右上の自分のアカウント、一覧の6通のアイコンと名前、差出人のアイコン、差出人の名前とアドレス、宛先の名前とアドレス
   - **画像ごとに違う**:本文の宛名・名乗り・署名・電話番号・住所・事務所名(1枚目は4か所、2枚目は5か所、3枚目は3か所)
2. 差出人のアドレスは画像ごとに長さが違う。いちばん長い 2枚目(`daichi@morikawa.example.org`)に合わせて、隠す幅を決める
3. `annotate_image` に `scale: 0.5` を渡して、1枚ずつ書き出す
4. 最初は `out` フォルダがなく、書き出せなかった。フォルダを作ってやり直した(`annotate_image` は書き出し先のフォルダを作らない)
5. `preview_region` で本文を拡大し、隠し漏れがないことを確かめる

モザイクの座標は元画像(2560×1600)のピクセルで書く。`scale` で縮めると、モザイクも一緒に縮む。付けた注釈は [annotations/](annotations/) に、画像ごとの JSON で置いている。

## CLI で同じものを作る

```bash
mkdir -p out
for i in 1 2 3; do
  kakiire annotate screenshots/mail-$i.png -o out/mail-$i.png -a annotations/mail-$i.json --scale 0.5
done
```

## 元の画面について

[screens/mail.html](../screens/mail.html) の `#1`・`#2`・`#3` で、開いているメールを変えて撮っている。撮り直すときは次を実行する:

```bash
for i in 1 2 3; do ../screens/shoot.sh ../screens/mail.html screenshots/mail-$i.png "#$i"; done
```
