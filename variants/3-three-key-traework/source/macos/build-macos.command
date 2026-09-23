#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
build_dir="$source_dir/build"
fn_app="$build_dir/Fn Bridge.app"
trae_app="$build_dir/TraeWork Bridge.app"

mkdir -p "$fn_app/Contents/MacOS" "$trae_app/Contents/MacOS"

xcrun clang -fobjc-arc -arch arm64 -arch x86_64 \
  -framework AppKit -framework CoreAudio \
  "$source_dir/fn_bridge.m" -o "$fn_app/Contents/MacOS/fn-bridge"
cp "$source_dir/Fn-Bridge-Info.plist" "$fn_app/Contents/Info.plist"
chmod 755 "$fn_app/Contents/MacOS/fn-bridge"

xcrun clang -fobjc-arc -arch arm64 -arch x86_64 \
  -framework AppKit -framework ApplicationServices \
  "$source_dir/traework_bridge.m" \
  -o "$trae_app/Contents/MacOS/traework-bridge"
cp "$source_dir/TraeWork-Bridge-Info.plist" "$trae_app/Contents/Info.plist"
chmod 755 "$trae_app/Contents/MacOS/traework-bridge"

codesign --force --deep --sign - "$fn_app"
codesign --force --deep --sign - "$trae_app"
codesign --verify --deep --strict "$fn_app"
codesign --verify --deep --strict "$trae_app"
file "$fn_app/Contents/MacOS/fn-bridge"
file "$trae_app/Contents/MacOS/traework-bridge"
echo "构建完成：$build_dir"

