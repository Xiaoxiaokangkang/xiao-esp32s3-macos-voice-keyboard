#!/bin/zsh
set -u

echo "=== 应用 ==="
for app in "/Applications/Fn Bridge.app" "/Applications/TraeWork Bridge.app" "/Applications/TRAE SOLO CN.app"; do
  if [[ -d "$app" ]]; then echo "✅ $app"; else echo "❌ $app"; fi
done

echo
echo "=== 后台服务 ==="
for label in com.kangkangzai.xiao-fn-bridge com.kangkangzai.xiao-traework-bridge; do
  if launchctl print "gui/$(id -u)/$label" 2>/dev/null | grep -q 'state = running'; then
    echo "✅ $label 正在运行"
  else
    echo "❌ $label 未运行"
  fi
done

echo
echo "=== USB 设备 ==="
if ioreg -p IOUSB -w0 | grep -q 'XIAO Voice Keyboard V4 TraeWork'; then
  echo "✅ XIAO Voice Keyboard V4 TraeWork 已连接"
else
  echo "❌ 未检测到 XIAO Voice Keyboard V4 TraeWork"
fi

echo
echo "=== F13 → Fn 映射 ==="
hidutil property --matching '{"VendorID":0x2886,"ProductID":0x5d}' \
  --get UserKeyMapping 2>/dev/null || true

echo
echo "=== 音频设备 ==="
system_profiler SPAudioDataType 2>/dev/null | grep -A8 -B2 'XIAO Voice Keyboard Microphone' || \
  echo "❌ 未检测到 XIAO Voice Keyboard Microphone"

echo
read -k 1 "?按任意键关闭……"
echo
