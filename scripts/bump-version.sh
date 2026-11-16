#!/bin/bash
# 版を上げる。前の版のタグ以降にマージした PR から CHANGELOG.md の節を作り、版の表記をすべて書き換える。
# 使い方:
#   scripts/bump-version.sh 0.8.0             # CHANGELOG.md と版の表記を書き換える
#   scripts/bump-version.sh 0.8.0 --dry-run   # 作る節を表示するだけ(何も書き換えない)
#   scripts/bump-version.sh 0.8.0 --since <ref>  # 前の版のタグがないときに起点を指定する
# PR 本文の「## 変更履歴」の欄を項目にする。欄が空なら PR の件名を使い、「なし」なら載せない。
# 書き換えたあと、節を読んで直してからコミットする(手順は docs/release.md)。
set -euo pipefail
cd "$(dirname "$0")/.."

new=""
since=""
dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --since) since=${2:?--since には git の ref を指定してください}; shift ;;
    -*) echo "知らないオプションです: $1" >&2; exit 2 ;;
    *) new=$1 ;;
  esac
  shift
done

if [[ ! "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "使い方: scripts/bump-version.sh <x.y.z> [--dry-run] [--since <ref>]" >&2
  exit 2
fi

current=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
if [[ "$current" == "$new" ]]; then
  echo "すでに $new です" >&2
  exit 1
fi
if [[ "$(printf '%s\n%s\n' "$current" "$new" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" != "$new" ]]; then
  echo "$new は今の版 $current より新しくありません" >&2
  exit 1
fi
if grep -q "^## $new " CHANGELOG.md; then
  echo "CHANGELOG.md にはもう ## $new の節があります" >&2
  exit 1
fi

if [[ -z "$since" ]]; then
  since="v$current"
  if ! git rev-parse -q --verify "refs/tags/$since" >/dev/null; then
    git fetch -q --tags origin || true
  fi
  if ! git rev-parse -q --verify "refs/tags/$since" >/dev/null; then
    echo "前の版のタグ $since がありません。--since で起点を指定してください" >&2
    exit 1
  fi
fi

# main にマージした PR(マージコミットと squash の両方)と、今のブランチの開いている PR
prs=$(git log --first-parent --format=%s "$since..HEAD" \
  | sed -n -e 's/^Merge pull request #\([0-9][0-9]*\) .*/\1/p' -e 's/.*(#\([0-9][0-9]*\))$/\1/p')
branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$branch" != "main" && "$branch" != "HEAD" ]]; then
  open_pr=$(gh pr view "$branch" --json number,state --jq 'select(.state == "OPEN") | .number' 2>/dev/null || true)
  prs="$prs $open_pr"
fi
prs=$(printf '%s\n' $prs | sed '/^$/d' | sort -n -u)

# PR 本文の「## 変更履歴」の欄を取り出し、1行ずつ「- … (#N)」にする
entries=""
for n in $prs; do
  title=$(gh pr view "$n" --json title --jq .title)
  # 欄が本文の最後にあると、後ろの署名(🤖 Generated with …)まで欄の中身になる。項目は「- 」の行だけ読む。
  section=$(gh pr view "$n" --json body --jq .body \
    | tr -d '\r' \
    | perl -0pe 's/<!--.*?-->//gs' \
    | awk '/^## / { if (in_section) exit; if ($0 ~ /^## 変更履歴[[:space:]]*$/) { in_section = 1; next } } in_section { print }' \
    | sed -e 's/[[:space:]]*$//' -e '/^$/d' \
    | grep -E '^(- |なし)' || true)
  if [[ -z "$section" ]]; then
    entries+="- $title (#$n)"$'\n'
    continue
  fi
  if [[ "$(printf '%s' "$section" | head -1 | sed 's/^- *//')" == なし* ]]; then
    echo "#$n は「なし」なので載せません: $title" >&2
    continue
  fi
  while IFS= read -r line; do
    entries+="- ${line#- } (#$n)"$'\n'
  done <<< "$section"
done

if [[ -z "$entries" ]]; then
  echo "載せる PR がありません($since 以降)。節は「- 」の行を手で書いてください" >&2
  entries="- (ここに変化を書く)"$'\n'
fi

heading="## $new — $(date +%F)"
if [[ $dry_run -eq 1 ]]; then
  printf '%s\n\n%s' "$heading" "$entries"
  exit 0
fi

# 最初の「## 」の前に新しい節を入れる
tmp=$(mktemp)
HEADING=$heading ENTRIES=$entries awk '
  BEGIN { heading = ENVIRON["HEADING"]; entries = ENVIRON["ENTRIES"] }
  !done && /^## / { print heading; print ""; printf "%s", entries; print ""; done = 1 }
  { print }
  END { if (!done) { print ""; print heading; print ""; printf "%s", entries } }
' CHANGELOG.md > "$tmp"
mv "$tmp" CHANGELOG.md

# 版の表記。どれかが見つからなければ止める(表記の場所が増えたらここに足す)
replace() {
  local file=$1 from=$2 to=$3
  if ! grep -qF -- "$from" "$file"; then
    echo "$file に「$from」が見つかりません" >&2
    exit 1
  fi
  FROM=$from TO=$to perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$file"
}
replace project.yml "MARKETING_VERSION: \"$current\"" "MARKETING_VERSION: \"$new\""
replace Sources/KakiireTooling/KakiireTool.swift "appVersion = \"$current\"" "appVersion = \"$new\""
replace site/index.html "<span data-version>$current</span>" "<span data-version>$new</span>"
replace site/en/index.html "<span data-version>$current</span>" "<span data-version>$new</span>"
replace docs/cli.md "kakiire-$current" "kakiire-$new"

echo "$current → $new にしました。CHANGELOG.md の ## $new の節を読んで直してからコミットしてください" >&2
git --no-pager diff --stat
