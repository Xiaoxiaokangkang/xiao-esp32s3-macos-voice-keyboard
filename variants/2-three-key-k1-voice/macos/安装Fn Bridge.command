#!/bin/zsh
set -e

script_dir="${0:A:h}"
source_app="$script_dir/Fn Bridge.app"
target_app="/Applications/Fn Bridge.app"
agent_dir="$HOME/Library/LaunchAgents"
agent_file="$agent_dir/com.kangkangzai.xiao-fn-bridge.plist"
user_id="$(id -u)"

if [[ ! -d "$source_app" ]]; then
  echo "找不到 Fn Bridge.app，请保留完整文件夹结构。"
  read -k 1 "?按任意键关闭……"
  exit 1
fi

pkill -x fn-bridge 2>/dev/null || true
sudo /usr/bin/ditto "$source_app" "$target_app"
sudo /usr/bin/xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true

mkdir -p "$agent_dir"
plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
<key>Label</key><string>com.kangkangzai.xiao-fn-bridge</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>$target_app</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>"
print -r -- "$plist_content" > "$agent_file"
plutil -lint "$agent_file"

launchctl bootout "gui/$user_id" "$agent_file" 2>/dev/null || true
launchctl bootstrap "gui/$user_id" "$agent_file"
open -a "$target_app"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo
echo "程序已安装到：$target_app"
echo "请在辅助功能列表中删除旧 Fn Bridge，再按 + 重新添加上面的程序并开启。"
echo "若系统要求 Touch ID 或密码，请由当前用户确认。"
read -k 1 "?完成后按任意键关闭……"
