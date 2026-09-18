# V1：单键语音输入

这是四套方案中的第 1 个版本：一个实体按键控制微信输入法语音输入。它源自曾在 Mac M3 上正常工作的旧方案，与 V2 之后的三键新接线完全分开。

## 版本组合

- 历史固件内部名称：`XIAO Voice Keyboard V8`
- Mac 安装包：`macos/M3原用-XIAO语音键盘-Mac安装包-v2.2.zip`
- Fn Bridge App：2.1，Universal（arm64 + x86_64）
- 工作方式：开发板发送 F13，旧版 Fn Bridge 生成软件 Fn

## 接线

INMP441：

- SCK → D7
- WS → D8
- SD → D10
- VDD → 3V3
- GND → GND
- L/R → GND

语音按键：

- 一端 → D0
- 另一端 → GND

这个历史固件不适用于 V2、V3、V4 的 D9、D10、D8 麦克风接线。

## 固件公开状态

V1 的原始资料只有从旧设备读取的完整 8 MB Flash，没有相应固件源码。为避免公开旧编译环境路径和无法全面审计的历史设备状态，GitHub 版本不提供这份 Flash 镜像。

本目录只保留方案介绍和历史 Mac 安装包，不能仅凭公开资源重新烧录 V1。希望实际复刻项目的用户应从 V2 开始。

## Mac 端安装

1. 解压 `macos/M3原用-XIAO语音键盘-Mac安装包-v2.2.zip`。
2. 右键打开 `安装Fn Bridge.command`。
3. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许 `~/Applications/Fn Bridge.app`。
4. 微信输入法的语音热键保持为 `Fn`。

## 限制

这个组合在原 Mac M3 上使用正常，但部分 M4/macOS 26 环境可能不接受旧版软件创建的 Fn 事件。遇到该问题请改用 V2、V3 或 V4 的原地映射版 Fn Bridge。

V1 是历史介绍版，不属于源码级完整复现版本。Mac 安装包仅作为历史兼容资料保留。
