#!/bin/zsh
# Release ビルドして dist/Kakiire-<version>.zip を作る。ad-hoc 署名なので、別の Mac では初回に隔離属性を外す必要がある(docs/install.md)。
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project Kakiire.xcodeproj -scheme Kakiire -configuration Release \
  -derivedDataPath build/DerivedData build -quiet
app=build/DerivedData/Build/Products/Release/Kakiire.app
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
mkdir -p dist
zip="dist/Kakiire-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
codesign --verify --deep --strict "$app"
echo "$zip"
