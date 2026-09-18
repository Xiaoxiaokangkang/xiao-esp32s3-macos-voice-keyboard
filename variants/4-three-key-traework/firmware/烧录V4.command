#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

SCRIPT_DIR=${0:A:h}
IMAGE="$SCRIPT_DIR/XIAO-ESP32S3-Voice-Keyboard-V4-complete.bin"

echo "先让 XIAO 进入下载模式："
echo "1. 拔掉 USB；2. 按住 BOOT/B；3. 插入 USB；4. 两秒后松开 BOOT。"
echo
read -k 1 "?准备好后按任意键继续……"
echo

ports=(/dev/cu.usbmodem*)
if (( ${#ports} == 0 )); then
  echo "❌ 未检测到 /dev/cu.usbmodem*，请重新执行上面的下载模式步骤。"
  read -k 1 "?按任意键关闭……"
  exit 2
fi
PORT=${ports[1]}
echo "检测到：$PORT"

if [[ -x "$HOME/.platformio/penv/bin/python3" && \
      -f "$HOME/.platformio/packages/tool-esptoolpy/esptool.py" ]]; then
  "$HOME/.platformio/penv/bin/python3" \
    "$HOME/.platformio/packages/tool-esptoolpy/esptool.py" \
    --chip esp32s3 --port "$PORT" --baud 460800 \
    write_flash 0x0 "$IMAGE"
elif command -v esptool >/dev/null 2>&1; then
  esptool --chip esp32s3 --port "$PORT" --baud 460800 \
    write_flash 0x0 "$IMAGE"
elif python3 -c 'import esptool' >/dev/null 2>&1; then
  python3 -m esptool --chip esp32s3 --port "$PORT" --baud 460800 \
    write_flash 0x0 "$IMAGE"
else
  echo "❌ 未找到 esptool。请先安装 PlatformIO，或运行：python3 -m pip install esptool"
  read -k 1 "?按任意键关闭……"
  exit 3
fi

echo
echo "✅ 刷写完成。请松开 BOOT，拔掉 USB，再在不按任何键的情况下重新插入。"
read -k 1 "?按任意键关闭……"
echo
