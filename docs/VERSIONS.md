# 版本顺序与功能

课程主线按照功能复杂度固定为 V1、V2、V3，并与 Windows 仓库保持一致。旧单键方案作为 Legacy 历史归档，不参与课程编号。

## V1：三个按键，K1 语音输入

- 麦克风新接线：SCK → D9、WS → D10、SD → D8。
- K1 → D2；K2 → D1；K3 → D0。
- 只启用 K1，按住开始语音输入，松开结束。
- K2、K3 在这个版本中不执行功能。
- USB 产品名：`XIAO Voice Keyboard V1`。
- 提供固件、Mac 程序、源码和完整构建说明。

## V2：三个按键，语音输入、发送、取消

- 硬件接线与 V1 相同。
- 三个按键按下时向 GPIO 输出 3.3 V 高电平，固件使用内部下拉。
- K1：按住语音输入。
- K2：发送 Return，并带防重复触发逻辑。
- K3：长按约 1.5 秒执行 Command+A、Backspace，以清空文本框的方式取消当前输入。
- USB 产品名：`XIAO Voice Keyboard V2`。
- 提供固件、Mac 程序、源码和完整构建说明。

## V3：三个按键，TraeWork CN 工作流

- 硬件接线与 V2 相同。
- K1：发送 F16，由 TraeWork Bridge 打开或置前 TRAE SOLO CN，并尝试聚焦对话输入框。
- K2：发送 F13，由 Fn Bridge 映射为 Apple Fn；短按切换输入法，长按调用微信输入法语音。
- K3：标准 Return，用于发送、确认或换行。
- USB 产品名：`XIAO Voice Keyboard V3 TraeWork`。
- 提供固件、两个 Mac 程序、源码和完整构建说明。

## 共用组件

V1、V2 和 V3 共用部分 USB 音频底层实现、分区表、引导程序和 Fn Bridge。各版本仍分别保留所需文件，以便每个目录都能独立构建、烧录和安装。

## Legacy：旧版单键语音输入

- 一个语音按键，连接 D0 与 GND。
- 麦克风旧接线：SCK → D7、WS → D8、SD → D10。
- 历史固件内部名称为 `XIAO Voice Keyboard V8`。
- 原始资料没有固件源码；公开版不提供旧设备完整 Flash。
- 只保留方案说明和历史 Mac 安装包，不属于课程 V1–V3 或源码级复现版本。

## 旧编号迁移

| 旧 macOS 编号 | 新课程编号 |
|---|---|
| 单键 V1 | Legacy |
| 三键 V2 | V1 |
| 三键 V3 | V2 |
| 三键 V4 | V3 |
