#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
USER_LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
FN_LABEL="com.kangkangzai.xiao-fn-bridge"
TRAE_LABEL="com.kangkangzai.xiao-traework-bridge"

echo "安装 XIAO 语音键盘 Mac 端组件……"
sudo -v

launchctl bootout "gui/$(id -u)/$FN_LABEL" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$TRAE_LABEL" 2>/dev/null || true

sudo /usr/bin/ditto "$SCRIPT_DIR/Fn Bridge.app" "/Applications/Fn Bridge.app"
sudo /usr/bin/ditto "$SCRIPT_DIR/TraeWork Bridge.app" "/Applications/TraeWork Bridge.app"
sudo /usr/bin/xattr -dr com.apple.quarantine "/Applications/Fn Bridge.app" 2>/dev/null || true
sudo /usr/bin/xattr -dr com.apple.quarantine "/Applications/TraeWork Bridge.app" 2>/dev/null || true

mkdir -p "$USER_LAUNCH_AGENTS"
/usr/bin/ditto "$SCRIPT_DIR/com.kangkangzai.xiao-fn-bridge.plist" \
  "$USER_LAUNCH_AGENTS/com.kangkangzai.xiao-fn-bridge.plist"
/usr/bin/ditto "$SCRIPT_DIR/com.kangkangzai.xiao-traework-bridge.plist" \
  "$USER_LAUNCH_AGENTS/com.kangkangzai.xiao-traework-bridge.plist"

launchctl bootstrap "gui/$(id -u)" \
  "$USER_LAUNCH_AGENTS/com.kangkangzai.xiao-fn-bridge.plist"
launchctl bootstrap "gui/$(id -u)" \
  "$USER_LAUNCH_AGENTS/com.kangkangzai.xiao-traework-bridge.plist"

echo
echo "Mac 端组件安装完成。"
echo "接下来请在系统设置 → 隐私与安全性 → 辅助功能中允许："
echo "  /Applications/TraeWork Bridge.app"
echo "授权后关闭再打开一次该开关。Fn Bridge 不需要辅助功能权限。"
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' || true
echo
read -k 1 "?按任意键关闭……"
echo
