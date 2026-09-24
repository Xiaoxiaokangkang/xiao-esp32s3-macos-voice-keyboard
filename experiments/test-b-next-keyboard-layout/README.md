# Test B：AC Next Keyboard Layout Select（0x029D）

这个实验在 Test A 未被 macOS 转换为 Apple Fn 后，单独验证 Consumer Page `0x0C` / `AC Next Keyboard Layout Select` `0x029D` 是否产生 Globe 或输入源切换行为。

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

## macOS 验证顺序

1. 保持 Fn Bridge 退出，不设置 `hidutil` 映射。
2. 确认 `hidutil list --matching '{"ProductID":0x005f}'` 返回 Consumer Control 设备。
3. 按住和松开 K1，观察输入源、Globe 或系统修饰键状态。
4. 如果 macOS 层出现所需行为，再测试微信输入法的长按开始和松开结束。

`0x029D` 的标准语义是选择下一个键盘布局；实验结果不能预先假定它与所有 Apple Fn 行为完全等价。
