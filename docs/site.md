# LP の公開(Cloudflare Pages)

LP は `site/` の静的 HTML。Cloudflare Pages が GitHub のリポジトリを見て、`main` に push されるたびに出し直す。リポジトリは private のままでよい。

GitHub Pages を使わないのは、無料プランでは private リポジトリから出せないため(2026-11-10 時点)。

## 仕組み

1. `main` に push する
2. Cloudflare Pages が `bash scripts/build-site.sh build/site` を動かす
3. スクリプトが `site/` を `build/site` に写し、`<span data-version>` の中身を `project.yml` の `MARKETING_VERSION` に差し替える
4. `build/site` が公開される

ページは日本語版 `site/index.html`(`/`)と英語版 `site/en/index.html`(`/en/`)の2つ。画像と `style.css` は共通で、英語版は `../assets/` から読む。文言を変えたら両方を直す。

`site/` の HTML に書いてあるバージョンは、手元で見るときの仮の値。公開されるページのバージョンは、いつも `project.yml` から入る。アプリのバージョンを上げて push すれば、LP の表記も変わる。

## 手元で見る

```bash
python3 -m http.server 4173 --directory site
```

`file://` で直接開くと、プレビューによっては CSS を読まない。

公開されるものと同じ形を見るとき:

```bash
./scripts/build-site.sh
```

```bash
python3 -m http.server 4173 --directory build/site
```

## Cloudflare 側の設定(最初の1回)

画面の表記は変わることがある。項目名が違っていたら、近い名前のものを探す。

1. `site/` が `main` に入っていることを確かめる(入っていないと最初のビルドが失敗する)
2. Cloudflare のダッシュボードで **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
3. GitHub を選び、Cloudflare の GitHub アプリに `sumihiro3/kakiire` へのアクセスを許可する(「Only select repositories」でこのリポジトリだけにする)
4. ビルドの設定を入れる

| 項目 | 値 |
| --- | --- |
| Project name | `kakiire`(`kakiire.pages.dev` になる。取られていたら別の名前) |
| Production branch | `main` |
| Framework preset | None |
| Build command | `bash scripts/build-site.sh build/site` |
| Build output directory | `build/site` |
| Root directory | 空のまま |

5. **Save and Deploy**。終わると `https://<Project name>.pages.dev` で見られる
6. プロジェクトの **Settings** → **Build** → **Build watch paths** の Include を次の3つにする(LP に関係のない push でビルドしないため)

```
site/*
project.yml
scripts/build-site.sh
```

### ブランチのプレビュー

`main` 以外のブランチを push すると、`<ブランチ名>.<Project name>.pages.dev` にプレビューが出る。URL を知っていれば誰でも見られる。要らなければ **Settings** → **Build** → **Branch control** でプレビューを止める。

### 独自ドメイン(任意)

`tep-lab.com` の DNS は Google Cloud DNS にある。`kakiire.tep-lab.com` で出す場合:

1. Pages のプロジェクトの **Custom domains** で `kakiire.tep-lab.com` を足す
2. Google Cloud DNS に CNAME を1件足す(名前 `kakiire`、値 `<Project name>.pages.dev.`)

## 上限(無料プラン、2026-11 時点)

- ビルドは月 500 回、同時に1つ
- 1ファイル 25 MiB まで

## CI との関係

`.github/workflows/ci.yml`(アプリのテストとビルド)は、`site/**` だけの変更では走らない。
