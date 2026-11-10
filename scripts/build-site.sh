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

# <span data-version>…</span> の中身だけを差し替える。site/index.html に書いてある値は手元で見るときの仮の値
sed -i.bak -E "s#(<span data-version>)[^<]*(</span>)#\\1${version}\\2#g" "$out/index.html"
rm "$out/index.html.bak"

if ! grep -q "<span data-version>${version}</span>" "$out/index.html"; then
  echo "index.html に <span data-version> が見つからない" >&2
  exit 1
fi
echo "Kakiire ${version} → ${out}"
