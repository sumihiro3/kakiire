#!/bin/bash
# 使用例の元画面を Chrome で 2 倍にして撮る。使い方: shoot.sh <html> <出力.png> [#ハッシュ]
set -euo pipefail
html="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=1280,800 \
  --screenshot="$out" "file://$html${3:-}" 2>/dev/null
