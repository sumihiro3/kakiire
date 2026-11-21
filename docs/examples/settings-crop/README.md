# 必要な所だけ切り抜いて、新機能を知らせる

画面全体から、サイドバーだけを切り抜いて「新機能」のバッジを強調した例。お知らせや SNS に貼る画像を想定している。元の画像は[操作手順書の例](../settings-steps/README.md)と同じ。

| 元の画像 | 切り抜いて書き入れた後 |
|---|---|
| ![元の画像](../settings-steps/before.png) | ![切り抜いて書き入れた後](after.png) |

## 頼んだこと

```text
~/Desktop/settings.png のサイドバーだけ切り抜いて、
「新機能」のバッジを丸で囲んで、吹き出しで「同期が新しくなりました」と書いて
```

## AI がしたこと

1. `get_image_info` で画像を見て、サイドバーの範囲を決める
2. `crop` に `[160, 190, 480, 1000]` を渡し、「新機能」のバッジを `ellipse` で囲み、下の空いた所に吹き出しを置く
3. プレビューを見ると、吹き出しのしっぽが「ショートカット」の文字にかかっていた。吹き出しを右に寄せて、3行に折り返して描き直す
4. 下の余白が広かったので、切り抜きの高さを 920 に詰めて書き出す

切り抜いても、座標は元画像のピクセルのまま書ける。付けた注釈は [annotations.json](annotations.json) にある。

## 手で直す

[after.kakiire](after.kakiire) は切り抜きを非破壊で持っている。アプリで開けば、切り抜きの範囲を広げ直せる。

## CLI で同じものを作る

```bash
kakiire annotate ../settings-steps/before.png -o after.png -o after.kakiire -a annotations.json --crop 160,190,480,920
```
