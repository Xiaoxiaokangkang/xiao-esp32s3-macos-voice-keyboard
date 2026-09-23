# V2：三键语音输入、发送、取消

V2 在 V1 的 USB 语音基础上启用了全部三个按键，适合连续进行语音输入、发送和取消当前输入。

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

- K1：按住时调用微信输入法语音输入，松开结束。
- K2：短按发送 Return；释放稳定约 250 ms 后才允许再次发送。
- K3：长按约 1.5 秒执行 Command+A、Backspace，以清空当前文本框的方式实现“取消”；每次按住只执行一次。

## 安装

1. 运行 `firmware/烧录V2.command`。
2. 按提示进入下载模式并完成烧录；若仍显示 USB JTAG/serial debug unit，只短按一次 RESET。
3. 运行 `macos/安装Fn Bridge.command`。
4. 在“系统设置 → 隐私与安全性 → 辅助功能”中添加并允许 `/Applications/Fn Bridge.app`。
5. 允许微信输入法使用麦克风，并将其语音热键设为 `Fn`。

完整固件也可以由其他 ESP32-S3 工具写入 `0x0`。分立镜像地址见 `firmware/烧录说明.md`。

## 已验证行为

- macOS 识别为 `XIAO Voice Keyboard V2`。
- K1 的 F13 由 Fn Bridge 原地转换为 Apple Fn。
- K2 一次操作输出一组 Return 按下/松开事件。
- K3 每次长按只执行一次清空序列。
- 麦克风关闭后再次录音仍能得到非零数据。

## 从源码构建

- 固件工程：`source/firmware`，运行 `pio run`。
- 当前 Fn Bridge 源码：`source/macos/fn_bridge.m`。
- Mac App：进入 `source/macos` 后运行 `./build-macos.command`。
- Swift 诊断与开发期实现也保存在 `source/macos`。

`diagnostics/` 中另附两个已编译 arm64 工具。通用构建要求和可重复构建边界见仓库根目录的 `docs/BUILDING.md`。
