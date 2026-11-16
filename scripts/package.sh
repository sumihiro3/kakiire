#!/bin/zsh
# Release ビルドを Developer ID で署名し、dist/Kakiire.dmg を作って公証・staple する(ADR 0013、手順は docs/release.md)。
#   ./scripts/package.sh                 公証まで行う
#   ./scripts/package.sh --no-notarize   公証せずに DMG まで作る(手元で中身を確かめるとき)
# 公証の認証は notarytool のキーチェーンのプロファイル(既定 kakiire-notary、KAKIIRE_NOTARY_PROFILE で変えられる)。
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

xcodegen generate >/dev/null
xcodebuild -project Kakiire.xcodeproj -scheme Kakiire -configuration Release \
  -derivedDataPath build/DerivedData build -quiet
app=build/DerivedData/Build/Products/Release/Kakiire.app
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")

# 公証で落ちる条件(Developer ID 以外の署名・Hardened Runtime なし・タイムスタンプなし・get-task-allow あり)を、提出する前に確かめる
codesign --verify --deep --strict "$app"
for bundle in "$app" "$app"/Contents/PlugIns/*.appex; do
  info=$(codesign -dvv "$bundle" 2>&1)
  for want in "Authority=$identity" "flags=0x10000(runtime)" "Timestamp="; do
    if ! print -r -- "$info" | grep -qF "$want"; then
      echo "$bundle の署名に「$want」がない" >&2
      exit 1
    fi
  done
  if codesign -d --entitlements - --xml "$bundle" 2>/dev/null | grep -q get-task-allow; then
    echo "$bundle に get-task-allow が付いている(公証で落ちる)" >&2
    exit 1
  fi
done

mkdir -p dist
# 名前に版を入れない。LP が releases/latest/download/Kakiire.dmg で最新版を直接指すため(ADR 0013)
dmg="dist/Kakiire.dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Kakiire.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname Kakiire -srcfolder "$staging" -fs HFS+ -format UDZO -quiet "$dmg"
codesign --sign "$identity" --timestamp "$dmg"

if ! $notarize; then
  echo "$dmg(v$version、未公証)"
  exit 0
fi

# --wait は審査が Invalid でも 0 で終わることがあるので、status を読んで判定する
result=$(xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format json)
notary_status=$(print -r -- "$result" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
if [[ "$notary_status" != Accepted ]]; then
  id=$(print -r -- "$result" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  echo "公証が通らなかった(status: $notary_status)。理由: xcrun notarytool log $id --keychain-profile $profile" >&2
  exit 1
fi
xcrun stapler staple -q "$dmg"
xcrun stapler validate -q "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"
echo "$dmg(v$version)"
