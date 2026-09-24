# V1 Direct HID Edition：K1 免安装语音输入

这是 V1 的免安装实现。XIAO ESP32S3 通过 USB HID 直接向 macOS 发送 Globe 相关的 Consumer Usage，不需要安装 Fn Bridge，不需要辅助功能权限，也不需要 `hidutil` remapping。

```text
长按 K1 → 开始微信输入法语音输入
松开 K1 → 结束录音并输出文字
```

## 选择哪个 V1

| 版本 | Mac 端安装 | HID 实现 | 建议 |
|---|---|---|---|
| V1 Direct HID Edition（本目录） | 不需要 | Consumer `0x029D` | 优先尝试 |
| [V1 Fn Bridge Edition](../1-three-key-k1-voice/README.md) | Fn Bridge + 辅助功能权限 | F13 → Fn | Direct 不兼容时使用 |

两个版本使用相同硬件、接线、K1 电平学习和 USB 麦克风；区别只在 K1 的 HID 实现与是否需要 Mac 端桥接。

## 已验证环境

- Seeed Studio XIAO ESP32S3
- INMP441，16 kHz、16-bit、单声道 USB 麦克风
- macOS 27.0（Build 26A428）
- 微信输入法
- USB 产品名：`XIAO Voice Keyboard V1 Direct`
- USB Product ID：`0x005F`

不同 macOS 或输入法版本可能有不同处理方式。如果 K1 没有触发语音输入，请使用 Fn Bridge Edition。

## 接线

- INMP441 SCK → D9
- INMP441 WS → D10
- INMP441 SD → D8
- INMP441 VDD → 3V3
- INMP441 GND → GND
- INMP441 L/R → GND
- K1 → D2
- K2 → D1（未分配功能）
- K3 → D0（未分配功能）

固件会在上电时学习 K1 的松开状态，可兼容接 GND、3.3 V 或高低电平按键模块。插电或复位时不要按住 K1。

## 安装

1. 运行 [`firmware/烧录V1-Direct.command`](firmware/烧录V1-Direct.command)。
2. 按提示让 XIAO 进入下载模式并完成烧录。
3. 如果烧录后仍显示为下载设备，只短按一次 RESET/R。
4. 在微信输入法中启用 Fn/Globe 长按语音功能。
5. 在文字输入框中长按 K1 说话，松开后等待识别结果。

本版本没有 `macos/` 目录，因为正式使用不需要任何 Mac 端辅助 App。

## 工作原理

K1 稳定按下时，固件发送 Consumer Page `0x0C` / `AC Next Keyboard Layout Select 0x029D` 并保持该状态；松开后发送 `0x0000`。它不是 Keyboard Page 的 `KEY_FN`，也不发送 F13。

USB 设备仍是 HID + Audio Composite Device。USB Audio 描述符、I2S 采集和音频传输与 V1 Bridge Edition 保持一致。

完整的描述符、报告字节、Test A/Test B 对照、macOS 枚举证据与兼容性边界见 [Direct Globe HID 技术报告](../../docs/DIRECT_GLOBE_HID.md)。

## 从源码构建

```bash
cd variants/1-three-key-k1-voice-direct-hid/source/firmware
pio run
```

源码构建的应用镜像位于 `.pio/build/seeed_xiao_esp32s3/firmware.bin`。连接下载模式下的 XIAO 后可运行：

```bash
pio run --target upload
```

预编译完整镜像和分立镜像位于 `firmware/`。完整镜像从地址 `0x0` 写入，单独的应用镜像从 `0x10000` 写入。

## 恢复 Bridge 版

重新烧录 [`../1-three-key-k1-voice/firmware`](../1-three-key-k1-voice/firmware/) 中的 V1 完整固件即可。恢复 Bridge 版后仍需安装 Fn Bridge。
