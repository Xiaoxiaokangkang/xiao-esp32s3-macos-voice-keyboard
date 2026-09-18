#!/bin/zsh
set -e

script_dir="${0:A:h}"
image="$script_dir/XIAO-ESP32S3-Voice-Keyboard-V3-complete.bin"
pio_python="$HOME/.platformio/penv/bin/python3"
esptool="$HOME/.platformio/packages/tool-esptoolpy/esptool.py"

if [[ ! -f "$image" ]]; then
  echo "找不到完整固件：$image"
  read -k 1 "?按任意键关闭……"
  exit 1
fi
if [[ ! -x "$pio_python" || ! -f "$esptool" ]]; then
  echo "没有找到本机已有的 PlatformIO/esptool。"
  echo "也可用任意 ESP32-S3 烧录工具，将完整镜像写入地址 0x0。"
  read -k 1 "?按任意键关闭……"
  exit 2
fi

echo "按住 BOOT/B，短按 RESET/R，先松开 RESET，再松开 BOOT。"
read -k 1 "?进入下载模式后按任意键继续……"
echo

ports=(/dev/cu.usbmodem*(N))
if (( ${#ports} != 1 )); then
  echo "需要且只能检测到一个 /dev/cu.usbmodem*，当前数量：${#ports}"
  printf '%s\n' "${ports[@]}"
  read -k 1 "?按任意键关闭……"
  exit 3
fi

"$pio_python" "$esptool" --chip esp32s3 --port "$ports[1]" --baud 460800 \
  write_flash 0x0 "$image"

echo "烧录完成。若仍处于下载模式，只短按一次 RESET/R。"
read -k 1 "?按任意键关闭……"
