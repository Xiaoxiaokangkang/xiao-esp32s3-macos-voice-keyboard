# V3：调用 TraeWork CN、语音/切换输入法、发送

V3 面向 TRAE SOLO CN 工作流。它沿用 V2 的 USB 音频底层和硬件接线，但重新定义了三个按键，并增加 TraeWork Bridge。

设备连接后显示为 `XIAO Voice Keyboard V3 TraeWork`，可与 V1、V2 明确区分。

## 环境

- macOS 12 或更高版本，Apple Silicon 或 Intel
- 微信输入法，语音输入触发键设置为 `Fn`
- `/Applications/TRAE SOLO CN.app`
- TRAE SOLO CN Bundle ID：`cn.trae.solo.app`

## 接线

- INMP441 SCK → D9
- INMP441 WS → D10
- INMP441 SD → D8
- INMP441 VDD → 3V3
- INMP441 GND → GND
- INMP441 L/R → GND
- K1 → D2
- K2 → D1
- K3 → D0

三个按键按下时向 GPIO 输出 3.3 V 高电平。

## 按键功能

| 按键 | 固件按键 | 最终效果 |
|---|---|---|
| K1 | F16 | 打开或置前 TRAE SOLO CN，并尝试聚焦对话输入框 |
| K2 | F13 | 映射为 Apple Fn；短按可切换输入法，长按可调用微信输入法语音 |
| K3 | Return | 在当前应用执行回车、确认、换行或发送 |

## 安装

1. 如果开发板尚未刷入这个版本，运行 `firmware/烧录V3.command`。
2. 运行 `macos/安装Mac端.command`，按提示输入管理员密码。
3. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许 `/Applications/TraeWork Bridge.app`。
4. 运行 `macos/检查状态.command` 检查 App、LaunchAgent、USB、Fn 映射和音频设备。

Fn Bridge 只针对 VendorID `0x2886`、ProductID `0x005D` 的设备设置键位映射并处理默认输入设备。TraeWork Bridge 只监听 F16，不记录其他普通按键，但它需要辅助功能权限来操作目标应用界面。

## 固件地址

- 完整镜像：`firmware/XIAO-ESP32S3-Voice-Keyboard-V3-complete.bin` → `0x0`
- `bootloader.bin` → `0x0000`
- `partitions.bin` → `0x8000`
- `boot_app0.bin` → `0xE000`
- `firmware-app-V3.bin` → `0x10000`

## 从源码构建

- 固件工程：`source/firmware`，运行 `pio run`。
- Fn Bridge：`source/macos/fn_bridge.m`。
- TraeWork Bridge：`source/macos/traework_bridge.m`。
- 两个 App：进入 `source/macos` 后运行 `./build-macos.command`。

构建脚本会生成两个 arm64 + x86_64 Universal App，并进行 ad-hoc 签名。通用构建要求和签名说明见仓库根目录的 `docs/BUILDING.md`。
