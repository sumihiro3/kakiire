#!/bin/bash
# site/ を公開用のフォルダに写し、バージョン表記を project.yml の MARKETING_VERSION に合わせる。
# 使い方: ./scripts/build-site.sh [出力先(既定は build/site)]
# Cloudflare Pages のビルド(Linux)でも動かすので bash で書く。設定は docs/site.md。
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-build/site}"
version=$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' project.yml | head -n 1)
if [ -z "$version" ]; then
  echo "project.yml に MARKETING_VERSION が見つからない" >&2
  exit 1
fi

mkdir -p "$out"
cp -R site/. "$out/"

# <span data-version>…</span> の中身だけを差し替える。site/ の HTML に書いてある値は手元で見るときの仮の値
# 日本語版(index.html)と英語版(en/index.html)の両方に入っているので、HTML をすべて見る
pages=$(find "$out" -name '*.html')
for page in $pages; do
  sed -i.bak -E "s#(<span data-version>)[^<]*(</span>)#\\1${version}\\2#g" "$page"
  rm "$page.bak"
done

for page in "$out/index.html" "$out/en/index.html"; do
  if ! grep -q "<span data-version>${version}</span>" "$page"; then
    echo "$page に <span data-version> が見つからない" >&2
    exit 1
  fi
done
echo "Kakiire ${version} → ${out}"
