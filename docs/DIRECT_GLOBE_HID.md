# XIAO ESP32S3 直连 macOS Globe HID 技术报告

## 结论

在 XIAO ESP32S3、macOS 27.0（Build 26A428）和微信输入法的实机组合上，Consumer Page `0x0C` / `AC Next Keyboard Layout Select` `0x029D` 可以完成以下链路：

```text
K1 按下并保持
  → XIAO ESP32S3 发送 Consumer HID 0x029D
  → macOS Event System 接收 Consumer 事件
  → 微信输入法开始语音输入

K1 松开
  → XIAO ESP32S3 发送 0x0000
  → 微信输入法结束语音输入
```

正式实现归属于 `V1 Direct HID Edition / V1 免安装版`，不需要 Fn Bridge、不需要辅助功能权限，也不需要 `hidutil` remapping。原 F13 方案归属于同层级的 `V1 Fn Bridge Edition / V1 桥接兼容版`。

Generic Desktop `System Function Shift 0x97` 虽然符合 USB HID Usage Tables 中的 Fn 状态定义，但在同一实机环境中没有被 macOS 转换为 Apple Fn/Globe，因此不能完成本项目目标。

## 原项目基线

原 V1 源码位于 `variants/1-three-key-k1-voice/source/firmware`，关键结构如下：

- PlatformIO：`espressif32 @ 6.13.0`
- Framework：Arduino
- Arduino ESP32 Core：`3.20017.241212`
- 底层 USB：TinyUSB
- 开发板：Seeed Studio XIAO ESP32S3
- K1：D2，对应 GPIO 3
- 原 HID：`USBHIDKeyboard`
- 原 K1 行为：`keyboard.press(KEY_F13)` / `keyboard.release(KEY_F13)`
- 麦克风：INMP441，16 kHz、16-bit、单声道
- USB 结构：一个 HID interface 加 USB Audio Control / Streaming interfaces

原 USB Audio 使用 `tinyusb_enable_interface(USB_INTERFACE_CUSTOM, ...)` 注入描述符，并通过自定义 TinyUSB Audio driver 发送 I2S 数据。Test A 和 Test B 均没有修改这条音频路径。

## 正式版本与实验记录

正式版本源码位于：

```text
variants/1-three-key-k1-voice-direct-hid/source/firmware/src/main.cpp
```

Test A 和 Test B 原始工程仍保存在 `experiments/`，用于复核两个 Usage 的对照过程。正式版本以 Test B 的成功实现为基础，只调整了产品名和固件版本，不改变 HID、按键或 USB Audio 逻辑。

## 成功方案的 HID 描述符

报告描述符：

```c
constexpr uint8_t kNextKeyboardLayoutReportDescriptor[] = {
    0x05, 0x0C,        // Usage Page (Consumer)
    0x09, 0x01,        // Usage (Consumer Control)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x01,        // Report ID (1)
    0x15, 0x00,        // Logical Minimum (0)
    0x26, 0xFF, 0x03,  // Logical Maximum (0x03FF)
    0x19, 0x00,        // Usage Minimum (0)
    0x2A, 0xFF, 0x03,  // Usage Maximum (0x03FF)
    0x75, 0x10,        // Report Size (16)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x00,        // Input (Data, Array, Absolute)
    0xC0,              // End Collection
};
```

`0x029D` 是一个 Consumer selection usage，因此报告采用标准的 16-bit array，而不是 Keyboard Page 键码或 1-bit modifier。

### 线上的报告内容

HID interrupt IN report 包含 Report ID 和 little-endian 16-bit usage：

| 状态 | 报告字节 | 含义 |
|---|---|---|
| K1 按下/保持 | `01 9D 02` | Report ID 1，选中 Usage `0x029D` |
| K1 松开 | `01 00 00` | Report ID 1，无 Consumer selection |

固件只在防抖后的状态变化时发送。成功的 Press 报告会一直表示按下状态，直到 Release 报告到达；不存在定时自动释放或“点按脉冲”。如果 USB 枚举尚未完成或端点暂时忙，待发送状态会保留并重试。

## 按键状态机

Test B 完全沿用 V1 的 K1 处理：

1. 上电采样 25 次，学习 K1 的松开电平。
2. 每次读取时分别启用弱上拉和弱下拉，区分开路、强低、强高和不稳定状态。
3. 原始状态持续 25 ms 后才改变稳定状态。
4. 稳定按下调用 `setPressed(true)`，发送 `0x029D`。
5. 稳定松开调用 `setPressed(false)`，发送 `0x0000`。

插电或复位时不要按住 K1，否则固件可能把按下状态学习成松开状态。

## USB Composite 与音频影响

Test B 用自定义 `USBHIDDevice` 替换 `USBHIDKeyboard`，仍由 Arduino ESP32 USB library 建立同一个 HID interface。改变的是 HID report descriptor 和 input report payload，不是 USB Audio descriptor。

实机枚举结果：

- HID：Consumer Page `0x0C` / Consumer Control `0x01`
- HID 最大 input report：3 bytes（1 byte Report ID + 2 bytes payload）
- Audio Control interface：正常枚举并由 `usbaudiod` 占用
- Audio Streaming interface：`AppleUSBAudioStreamPropertiesReady = Yes`
- 微信输入法语音输入实测成功

因此本次 HID 修改没有破坏原有 Composite USB Audio 接口。源码中的 `audio_device.c`、`dcd_esp32sx_fixed.c`、I2S 配置、采样率和音频包大小均与 V1 保持一致。

## 实机验证记录

测试日期：2026-09-24。

环境：

- Seeed Studio XIAO ESP32S3
- INMP441
- macOS 27.0，Build 26A428
- 微信输入法
- Fn Bridge 退出
- 未设置 `hidutil` remapping

### Test A：0x97

- macOS 正确解析出 Generic Desktop Page `0x01`、System Control `0x80`、System Function Shift `0x97`。
- Press/Release 输入报告到达系统。
- `IOHIDEventDriver` 显示 `SupportedHIDEventMask = 0`。
- K1 按住期间 `kCGEventFlagMaskSecondaryFn` 始终为 0。
- 微信输入法没有开始语音输入。

结论：失败。

### Test B：0x029D

- macOS 正确解析 Consumer Page `0x0C` 和 16-bit Consumer array。
- 设备匹配 `AppleUserHIDEventService`，`SupportedHIDEventMask = 72`。
- 一次短按和一次长按产生完整的四个 Press/Release HID 事件。
- Event System 的队列收到四个事件，最后事件类型为 keyboard/consumer 路径。
- K1 长按开始微信输入法语音输入，松开结束。

结论：成功。

## 构建正式版本

```bash
cd variants/1-three-key-k1-voice-direct-hid/source/firmware
pio run
```

应用镜像生成在：

```text
.pio/build/seeed_xiao_esp32s3/firmware.bin
```

从源码上传：

```bash
pio run --target upload
```

进入下载模式：按住 BOOT/B，点按 RESET/R，松开 RESET，再松开 BOOT。烧录完成后如果设备仍显示为 `USB JTAG/serial debug unit`，只短按一次 RESET。

## 预编译固件

`variants/1-three-key-k1-voice-direct-hid/firmware` 包含：

| 地址 | 文件 |
|---:|---|
| `0x0000` | `bootloader.bin` |
| `0x8000` | `partitions.bin` |
| `0xE000` | `boot_app0.bin` |
| `0x10000` | `firmware-app-V1-Direct.bin` |

也可以直接把 `XIAO-ESP32S3-Voice-Keyboard-V1-Direct-complete.bin` 写入 `0x0`。

## macOS 调试命令

这些命令只读取状态，不设置映射：

```bash
hidutil list --matching '{"ProductID":0x005f}'
ioreg -r -c AppleUserUSBHostHIDDevice -l -w0
ioreg -r -c AppleUserHIDEventService -l -w0
```

期望看到：

- Product：`XIAO Voice Keyboard V1 Direct`
- Vendor ID：`0x2886`
- Product ID：`0x005F`
- Primary Usage Page：`12`
- Primary Usage：`1`

## 适用边界

- 本方案验证的是“触发当前微信输入法语音输入”，不是完整仿真 Apple 内建键盘 Fn 键。
- Test B 不会设置 Quartz `kCGEventFlagMaskSecondaryFn`；其他只监听 Quartz Fn modifier 的应用可能不响应。
- `0x029D` 的 USB 标准语义是“选择下一个键盘布局”。不同 macOS 版本、输入法或应用可能采用不同处理路径。
- 正式版继续使用独立 PID `0x005F`，避免 macOS 复用 V1 Fn Bridge Edition / V1 桥接兼容版或 Test A 的 HID descriptor 缓存。
- V1–V3 Known-Good 版本没有被修改，可随时烧回原完整固件。

## 正式版本采用的变更

V1 Direct HID Edition / V1 免安装版相对 V1 Fn Bridge Edition / V1 桥接兼容版的最小变更集合是：

1. `#include <USBHIDKeyboard.h>` 改为 `#include <USBHID.h>`。
2. 用 Test B 的 `NextKeyboardLayoutHID` 替换 `USBHIDKeyboard`。
3. `keyboard.press(KEY_F13)` 改为 `nextKeyboardLayout.setPressed(true)`。
4. `keyboard.release(KEY_F13)` 改为 `nextKeyboardLayout.setPressed(false)`。
5. 保留 K1 防抖、电平学习、TinyUSB Audio 和 I2S 代码。
6. 正式发行包不包含 Fn Bridge、LaunchAgent 或辅助功能权限步骤。
7. 在目标 macOS 版本上重新执行 USB Audio 与微信输入法回归测试。

为保留兼容性和既有链接，两个 V1 以同一层级的独立正式版本发布。免安装版不覆盖桥接兼容版；若目标环境不响应 `0x029D`，可以直接烧回 V1 桥接兼容版。

## 规范参考

- USB-IF：[HID Usage Tables](https://www.usb.org/sites/default/files/hut1_3_0.pdf)
- Seeed Studio：[XIAO ESP32S3 Getting Started](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/)
