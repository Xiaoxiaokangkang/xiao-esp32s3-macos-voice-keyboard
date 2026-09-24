# 正式版本顺序与功能

仓库中的正式版本严格按照以下顺序排列。两个 V1 是功能目标相同、实现方式不同的并列正式版本，目录层级完全相同；免安装版排在桥接兼容版之前。旧单键方案作为 Legacy 历史归档，不参与正式版本顺序。

| 顺序 | 正式版本 | Mac 端依赖 | K1 实现 |
|---:|---|---|---|
| 1 | [V1 Direct HID Edition / V1 免安装版](../variants/1-three-key-k1-voice-direct-hid/README.md) | 无 | Consumer HID `0x029D` |
| 2 | [V1 Fn Bridge Edition / V1 桥接兼容版](../variants/1-three-key-k1-voice/README.md) | Fn Bridge + 辅助功能权限 | F13 → Fn |
| 3 | [V2：语音、发送、取消](../variants/2-three-key-voice-send-cancel/README.md) | Fn Bridge + 辅助功能权限 | F13 → Fn |
| 4 | [V3：TraeWork CN](../variants/3-three-key-traework/README.md) | Fn Bridge + TraeWork Bridge | F13/F16 + Bridge |

## 1. V1 Direct HID Edition / V1 免安装版

- INMP441：SCK → D9、WS → D10、SD → D8。
- K1 → D2；K2 → D1；K3 → D0。
- 只启用 K1，按住开始语音输入，松开结束。
- K1 直接发送 Consumer Page `0x0C` / `AC Next Keyboard Layout Select 0x029D`。
- 不发送 F13，不安装 Fn Bridge，不需要辅助功能权限或 `hidutil` remapping。
- USB 产品名：`XIAO Voice Keyboard V1 Direct`；Product ID：`0x005F`。
- 已在 macOS 27.0（Build 26A428）与微信输入法上完成实机验证。
- 正式目录：[`variants/1-three-key-k1-voice-direct-hid`](../variants/1-three-key-k1-voice-direct-hid/README.md)。

## 2. V1 Fn Bridge Edition / V1 桥接兼容版

- 硬件、接线和按键功能与 V1 免安装版相同。
- K1 发送 F13，由 Fn Bridge 转换成 Apple Fn。
- 需要安装 Fn Bridge 并授予辅助功能权限。
- USB 产品名：`XIAO Voice Keyboard V1`；Product ID：`0x005D`。
- 正式目录：[`variants/1-three-key-k1-voice`](../variants/1-three-key-k1-voice/README.md)。

## 3. V2：三个按键，语音输入、发送、取消

- 硬件接线与两个 V1 相同。
- 三个按键按下时向 GPIO 输出 3.3 V 高电平，固件使用内部下拉。
- K1：按住语音输入。
- K2：发送 Return，并带防重复触发逻辑。
- K3：长按约 1.5 秒执行 Command+A、Backspace，以清空文本框的方式取消当前输入。
- USB 产品名：`XIAO Voice Keyboard V2`。
- 提供固件、Mac 程序、源码和完整构建说明。

## 4. V3：三个按键，TraeWork CN 工作流

- 硬件接线与 V2 相同。
- K1：发送 F16，由 TraeWork Bridge 打开或置前 TRAE SOLO CN，并尝试聚焦对话输入框。
- K2：发送 F13，由 Fn Bridge 映射为 Apple Fn；短按切换输入法，长按调用微信输入法语音。
- K3：标准 Return，用于发送、确认或换行。
- USB 产品名：`XIAO Voice Keyboard V3 TraeWork`。
- 提供固件、两个 Mac 程序、源码和完整构建说明。

## 实验、文档与共用组件

正式版本共用部分 USB 音频底层实现、分区表和引导程序。桥接版本还共用 Fn Bridge。各版本分别保留所需文件，可以独立构建、烧录和安装，不需要从另一个版本目录复制文件。

Direct HID 的 Test A/Test B 原始工程保存在 [`experiments`](../experiments/README.md)，用于记录 `0x97` 失败和 `0x029D` 成功的验证过程；它们是技术证据，不占用正式版本顺序。构建方法见 [`BUILDING.md`](BUILDING.md)，Direct HID 技术细节见 [`DIRECT_GLOBE_HID.md`](DIRECT_GLOBE_HID.md)。

## Legacy：旧版单键语音输入

- 一个语音按键，连接 D0 与 GND。
- 麦克风旧接线：SCK → D7、WS → D8、SD → D10。
- 历史固件内部名称为 `XIAO Voice Keyboard V8`。
- 原始资料没有固件源码；公开版不提供旧设备完整 Flash。
- 只保留方案说明和历史 Mac 安装包，不属于正式版本顺序或源码级复现版本。

## 旧编号迁移

| 旧 macOS 编号 | 新课程编号 |
|---|---|
| 单键 V1 | Legacy |
| 三键 V2 | V1 |
| 三键 V3 | V2 |
| 三键 V4 | V3 |
