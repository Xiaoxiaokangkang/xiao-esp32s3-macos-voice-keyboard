#!/bin/zsh
set -e

script_dir="${0:A:h}"
image="$script_dir/XIAO-ESP32S3-Voice-Keyboard-V1-Direct-complete.bin"
pio_python="$HOME/.platformio/penv/bin/python3"
esptool="$HOME/.platformio/packages/tool-esptoolpy/esptool.py"

if [[ ! -f "$image" ]]; then
  echo "找不到完整固件：$image"
  read -k 1 "?按任意键关闭……"
  exit 1
fi
if [[ ! -x "$pio_python" || ! -f "$esptool" ]]; then
  echo "这台 Mac 没有找到现有 PlatformIO/esptool 环境。"
  echo "也可以用任意 ESP32-S3 烧录工具，把完整固件写入地址 0x0。"
  read -k 1 "?按任意键关闭……"
  exit 2
fi

echo "V1 Direct HID Edition / V1 免安装版：无需 Fn Bridge。"
echo "请让 XIAO 进入下载模式："
echo "按住 BOOT/B → 短按 RESET/R → 松开 RESET → 松开 BOOT。"
echo
read -k 1 "?完成后按任意键继续……"
echo

ports=(/dev/cu.usbmodem*(N))
if (( ${#ports} != 1 )); then
  echo "需要且只能检测到一个 /dev/cu.usbmodem* 下载端口，当前数量：${#ports}"
  printf '%s\n' "${ports[@]}"
  read -k 1 "?按任意键关闭……"
  exit 3
fi

"$pio_python" "$esptool" --chip esp32s3 --port "$ports[1]" --baud 460800 \
  write_flash 0x0 "$image"

echo
echo "烧录完成。若设备仍处于下载模式，只短按一次 RESET/R。"
echo "设备名称应显示为：XIAO Voice Keyboard V1 Direct"
read -k 1 "?按任意键关闭……"
