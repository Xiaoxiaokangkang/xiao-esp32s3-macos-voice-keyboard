# V1 Fn Bridge Edition / V1 桥接兼容版

V1 使用 XIAO ESP32S3、INMP441 和三键板，但当前只启用 K1。这个兼容版本通过 F13 和 Fn Bridge 实现语音输入，需要安装 Mac 端 App 并授予辅助功能权限。

新安装建议优先使用不需要 Mac App 的 [V1 Direct HID Edition / V1 免安装版](../1-three-key-k1-voice-direct-hid/README.md)。如果免安装版在目标 macOS 或输入法版本上不兼容，再使用本版本。两个 V1 是仓库中同一层级的独立正式版本。

## 已验证配置

- Seeed Studio XIAO ESP32S3
- INMP441，16 kHz、16-bit、单声道 USB 麦克风
- Apple Silicon，macOS 26.6.2
- USB 产品名：`XIAO Voice Keyboard V1`
- Fn Bridge 2.2，Universal（arm64 + x86_64）

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

V1 会在上电时学习 K1 的松开状态，可兼容接 GND、3.3 V 或高低电平按键模块。插电或复位时不要按住 K1。

## 安装

1. 运行 `firmware/烧录V1.command`。
2. 按提示让 XIAO 进入下载模式并完成烧录。
3. 运行 `macos/安装Fn Bridge.command`。
4. 在“系统设置 → 隐私与安全性 → 辅助功能”中添加并允许 `/Applications/Fn Bridge.app`。
5. 将微信输入法语音热键设为 `Fn`。
6. 在文字输入框中按住 K1 说话，松开后等待识别结果。

完整固件也可以由其他 ESP32-S3 工具写入 `0x0`。分立镜像地址见 `firmware/烧录说明.md`。

## 工作原理

K1 按下时开发板发送 F13。Fn Bridge 只针对指定 USB VendorID/ProductID 把它映射为 Apple Fn，并在设备连接时处理默认输入设备。桥接程序不访问微信聊天内容。

## 从源码构建

- 固件工程：`source/firmware`，运行 `pio run`。
- 当前 Fn Bridge 源码：`source/macos/fn_bridge.m`。
- Mac App：进入 `source/macos` 后运行 `./build-macos.command`。
- Swift 诊断与开发期实现也保存在 `source/macos`，用于审计和后续修改。

`diagnostics/` 中另附两个已编译 arm64 工具，用于检查或录制 XIAO 音频。通用构建要求见仓库根目录的 `docs/BUILDING.md`。
