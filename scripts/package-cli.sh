#!/bin/zsh
# CLI(kakiire。MCP サーバーも兼ねる)を Developer ID で署名し、dist/kakiire-<version>-macos-arm64.zip を作って公証する(ADR 0008・0013、手順は docs/release.md)。
#   ./scripts/package-cli.sh                 公証まで行う
#   ./scripts/package-cli.sh --no-notarize   公証せずに zip まで作る
# 単体の実行ファイルには staple できないので、Gatekeeper は初回にネットから公証のチケットを取る。
set -euo pipefail
cd "$(dirname "$0")/.."

notarize=true
case "${1:-}" in
  "") ;;
  --no-notarize) notarize=false ;;
  *) echo "usage: $0 [--no-notarize]" >&2; exit 2 ;;
esac
profile=${KAKIIRE_NOTARY_PROFILE:-kakiire-notary}
identity="Developer ID Application"

if ! security find-identity -v -p codesigning | grep -q "\"$identity: "; then
  echo "キーチェーンに $identity の証明書がない(docs/release.md の「署名の準備」)" >&2
  exit 1
fi

swift build -c release --product kakiire --arch arm64
bin=$(swift build -c release --product kakiire --arch arm64 --show-bin-path)/kakiire
version=$("$bin" --version)

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/kakiire-$version"
cp "$bin" "$staging/kakiire-$version/kakiire"
cp LICENSE THIRD_PARTY_NOTICES.md "$staging/kakiire-$version/"
# サンドボックスは付けない(引数で受け取ったパスを読むため。ADR 0008)
codesign --force --sign "$identity" --options runtime --timestamp \
  --identifier com.tep-lab.kakiire.cli "$staging/kakiire-$version/kakiire"

info=$(codesign -dvv "$staging/kakiire-$version/kakiire" 2>&1)
for want in "Authority=$identity" "flags=0x10000(runtime)" "Timestamp="; do
  if ! print -r -- "$info" | grep -qF "$want"; then
    echo "kakiire の署名に「$want」がない" >&2
    exit 1
  fi
done
"$staging/kakiire-$version/kakiire" --version >/dev/null

mkdir -p dist
zip="dist/kakiire-$version-macos-arm64.zip"
rm -f "$zip"
ditto -c -k --keepParent "$staging/kakiire-$version" "$zip"

if ! $notarize; then
  echo "$zip(未公証)"
  exit 0
fi

# --wait は審査が Invalid でも 0 で終わることがあるので、status を読んで判定する(zsh では status は予約済み)
result=$(xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait --output-format json)
notary_status=$(print -r -- "$result" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
if [[ "$notary_status" != Accepted ]]; then
  id=$(print -r -- "$result" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  echo "公証が通らなかった(status: $notary_status)。理由: xcrun notarytool log $id --keychain-profile $profile" >&2
  exit 1
fi
echo "$zip"
shasum -a 256 "$zip"
