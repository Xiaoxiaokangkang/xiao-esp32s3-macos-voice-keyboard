# Test B：AC Next Keyboard Layout Select（0x029D）

这个实验在 Test A 未被 macOS 转换为 Apple Fn 后，单独验证 Consumer Page `0x0C` / `AC Next Keyboard Layout Select` `0x029D` 是否产生 Globe 或输入源切换行为。

这是当前已经实机验证成功的无 Fn Bridge 方案。完整的描述符分析、USB Composite 说明和测试证据见 [`../../docs/DIRECT_GLOBE_HID.md`](../../docs/DIRECT_GLOBE_HID.md)。

日常使用请转到已经正式整理的 [V1 Direct HID Edition / V1 免安装版](../../variants/1-three-key-k1-voice-direct-hid/README.md)；本目录保留实验设备名、实验固件版本和原始验证材料。

## 实验边界

- K1 仍接 D2，继续使用 V1 的启动状态学习和 25 ms 防抖。
- K2、K3 不启用。
- USB Audio 麦克风的描述符、I2S 采集和数据发送代码保持不变。
- 不包含 Fn Bridge，不发送 F13，也不包含 Test A 的 `0x97`。
- HID 只包含 Consumer Control Application Collection 和一个 16-bit Consumer Usage array。

K1 稳定按下时报告值为 `0x029D`；K1 稳定松开时报告值为 `0x0000`。报告成功送达后保持该 HID 状态，不发送自动释放脉冲。

测试固件使用独立的 USB Product ID `0x005F`、固件版本 `0x0B01` 和产品名 `XIAO Next Keyboard Layout Test B`，避免 macOS 复用 Test A 或 V1 的描述符缓存。

## 构建和上传

```bash
cd experiments/test-b-next-keyboard-layout/source/firmware
pio run
pio run --target upload
```

也可以运行 [`firmware/烧录TestB.command`](firmware/烧录TestB.command)，或把完整镜像 `firmware/XIAO-ESP32S3-Direct-Globe-Test-B-complete.bin` 写入地址 `0x0`。

## macOS 验证顺序

1. 保持 Fn Bridge 退出，不设置 `hidutil` 映射。
2. 确认 `hidutil list --matching '{"ProductID":0x005f}'` 返回 Consumer Control 设备。
3. 按住和松开 K1，观察输入源、Globe 或系统修饰键状态。
4. 如果 macOS 层出现所需行为，再测试微信输入法的长按开始和松开结束。

`0x029D` 的标准语义是选择下一个键盘布局；实验结果不能预先假定它与所有 Apple Fn 行为完全等价。

## 实机结果

2026-09-24 在 macOS 27.0（Build 26A428）、微信输入法和 XIAO ESP32S3 实机上测试：

- macOS 正确枚举 Consumer Page `0x0C` / Consumer Control，报告描述符和 16-bit 输入均正常。
- 一次短按和一次长按产生了完整的四个 Press/Release HID 事件，证明 Hold 与 Release 路径正常。
- 该 Usage 不会设置 Quartz `kCGEventFlagMaskSecondaryFn`，测试期间输入源也没有发生切换。
- 在微信输入法文本输入场景中，K1 长按可以开始语音输入，松开可以结束，目标功能成功。

结论：对本项目当前目标，Test B 的 `0x029D` 可直接替代 F13 + Fn Bridge；Test A 的 `0x97` 在同一环境下不可用。这个结论只覆盖上述实测软硬件组合，不表示所有 macOS 版本或应用都会把 `0x029D` 等同于完整的 Apple Fn 键。
