# V2 免安装版：三键语音输入、发送、取消

V2 在 V1 USB 语音输入的基础上启用了全部三个按键。K1 由 XIAO ESP32S3 直接发送 macOS 可识别的 Globe/Fn Consumer HID 报告，不安装 Fn Bridge，不创建 LaunchAgent，也不需要辅助功能权限。

## 接线

- INMP441 SCK → D9
- INMP441 WS → D10
- INMP441 SD → D8
- INMP441 VDD → 3V3
- INMP441 GND → GND
- INMP441 L/R → GND
- K1 信号 → D2
- K2 信号 → D1
- K3 信号 → D0

三个按键按下时必须向 GPIO 输出 3.3 V 高电平；固件使用内部下拉。

## 按键功能

- K1：按住时直接发送 Consumer HID `0x029D`，调用微信输入法语音输入；松开时发送 `0x0000` 结束语音输入。
- K2：短按发送 Return；释放稳定约 250 ms 后才允许再次发送。
- K3：长按约 1.5 秒执行 Command+A、Backspace，以清空当前文本框的方式实现“取消”；每次按住只执行一次。

## 使用方法

1. 运行 `firmware/烧录V2.command`。
2. 按提示进入下载模式并完成烧录；若仍显示 `USB JTAG/serial debug unit`，只短按一次 RESET。
3. 首次使用时在“系统设置 → 声音 → 输入”中选择 `XIAO Voice Keyboard Microphone`。
4. 在微信输入法中启用 Fn/地球键长按语音功能，并允许微信输入法使用麦克风。
5. 将光标放入文本框，即可使用 K1、K2、K3。

不需要运行任何 Mac 安装程序，不需要安装 Fn Bridge，也不要设置 `hidutil` 映射。完整固件也可以由其他 ESP32-S3 工具写入 `0x0`；分立镜像地址见 `firmware/烧录说明.md`。

## 技术实现

固件把两类报告合并在同一个 HID interface 中，同时保留 USB Audio：

- Report ID 4：Consumer Page `0x0C` / `AC Next Keyboard Layout Select 0x029D`，用于 K1。
- Report ID 1：标准 Keyboard Page 报告，用于 K2 和 K3。
- USB Audio Control + Streaming：INMP441，16 kHz、16-bit、单声道。

USB 产品名为 `XIAO Voice Keyboard V2 Direct`，Product ID 为 `0x0060`，避免 macOS 复用旧版 F13 描述符缓存。完整技术框架、报告字节、接口结构和验证方法见 [`../../docs/V2_DIRECT_HID.md`](../../docs/V2_DIRECT_HID.md)。

## 已验证行为

- macOS 识别产品名 `XIAO Voice Keyboard V2 Direct`、VID `0x2886`、PID `0x0060`。
- HID 同时包含 Consumer Control 与普通 Keyboard collection。
- `AppleUserHIDEventService` 报告 `SupportsGlobeKey = Yes`。
- USB 麦克风被识别为 `XIAO Voice Keyboard Microphone`，16 kHz、单声道。
- 10 秒实录得到 475,200 帧非零音频，峰值约 1.03、RMS 约 0.142。
- K2 保留一次一组 Return 按下/松开事件；K3 每次长按只执行一次清空序列。

## 从源码构建

```bash
cd variants/2-three-key-voice-send-cancel/source/firmware
pio run
```

应用镜像生成在 `.pio/build/seeed_xiao_esp32s3/firmware.bin`。必须保持 `ARDUINO_USB_CDC_ON_BOOT=0`；开启 USB CDC 会占用端点并破坏 USB Audio 枚举。

`diagnostics/record_xiao` 是可选的 arm64 麦克风采样工具，仅用于开发验证，不是正常使用所需组件。通用构建要求和可重复构建边界见仓库根目录的 [`docs/BUILDING.md`](../../docs/BUILDING.md)。

## 兼容性边界

`0x029D` 的 USB 标准语义是“选择下一个键盘布局”，本项目验证的是它在目标 macOS 与微信输入法组合中能够进入 Globe/Fn 语音路径；它不等同于完整仿真 Apple 内建键盘的所有 Fn 行为。若某个系统或输入法版本不响应，可改用 V1 Fn Bridge Edition 作为兼容方案。

免安装版没有后台程序替你切换和恢复默认麦克风；首次连接或 Mac 改变输入设备后，需要手动重新选择 XIAO 麦克风。
