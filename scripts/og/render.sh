#!/bin/bash
# LP の OGP 画像(1200×630)を作る。site/assets/og.png(日本語)と site/assets/en/og.png(英語)
# 層の図は site/assets の hero-*.png を使うので、そちらを撮り直したらこれも動かす
set -euo pipefail
cd "$(dirname "$0")"

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
profile=$(mktemp -d)
trap 'rm -rf "$profile"' EXIT

shot() {
  "$chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 \
    --virtual-time-budget=5000 --user-data-dir="$profile" --screenshot="$2" "file://$PWD/og.html$1" 2>/dev/null
}
shot "" ../../site/assets/og.png
shot "#en" ../../site/assets/en/og.png
echo "site/assets/og.png, site/assets/en/og.png"
