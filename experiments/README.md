# USB HID 直连 Fn / Globe 实验

本目录保存从 F13 + Fn Bridge 迁移到纯 USB HID 的两个隔离实验。两个实验都复制自 V1 固件，保留相同的 K1、电平学习、防抖和 USB Audio 实现，只替换 HID 描述符与报告内容。

| 实验 | HID Usage | macOS 结果 | 微信输入法 |
|---|---|---|---|
| [Test A](test-a-system-function-shift/README.md) | Generic Desktop `0x01` / System Function Shift `0x97` | 描述符和报告可解析，但不生成 Apple Fn/Globe | 失败 |
| [Test B](test-b-next-keyboard-layout/README.md) | Consumer `0x0C` / AC Next Keyboard Layout Select `0x029D` | Consumer 事件进入 Event System | 成功 |

详细的实现、描述符字节、测试证据和适用边界见 [`docs/DIRECT_GLOBE_HID.md`](../docs/DIRECT_GLOBE_HID.md)。
