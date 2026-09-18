#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
build_dir="$source_dir/build"
app="$build_dir/Fn Bridge.app"

mkdir -p "$app/Contents/MacOS"
xcrun clang -fobjc-arc -arch arm64 -arch x86_64 \
  -framework AppKit -framework ApplicationServices -framework CoreAudio \
  "$source_dir/fn_bridge.m" -o "$app/Contents/MacOS/fn-bridge"
cp "$source_dir/Fn-Bridge-Info.plist" "$app/Contents/Info.plist"
chmod 755 "$app/Contents/MacOS/fn-bridge"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
file "$app/Contents/MacOS/fn-bridge"
echo "构建完成：$app"

