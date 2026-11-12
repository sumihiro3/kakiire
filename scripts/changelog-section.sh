#!/bin/bash
# CHANGELOG.md から「## <版> — 日付」の節の本文(見出しを除く)を出す。GitHub Release の本文に使う。
# 使い方: scripts/changelog-section.sh 0.7.0
# 節がない、または本文が空なら 1 で終わる(Release を空で作らないため)。
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?版を指定してください(例: 0.7.0)}

body=$(awk -v v="$version" '
  /^## / { if (found) exit; split($0, a, " "); if (a[2] == v) { found = 1; next } }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d')

if [[ -z "${body//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md に ## $version の節がないか、中身が空です" >&2
  exit 1
fi
printf '%s\n' "$body"
