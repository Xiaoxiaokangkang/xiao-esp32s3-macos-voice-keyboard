# V2 免安装直连技术框架

## 目标与结果

V2 将原来的 `K1 → F13 → Fn Bridge → Apple Fn` 链路替换为纯 USB HID：

```text
K1 按下并保持
  → ESP32S3 发送 Consumer Usage 0x029D
  → macOS 将设备识别为支持 Globe Key
  → 微信输入法开始语音输入

K1 松开
  → ESP32S3 发送 0x0000
  → 微信输入法结束语音输入
```

K2 和 K3 继续使用标准 Keyboard HID，INMP441 继续通过 USB Audio 向 Mac 提供 16 kHz 单声道音频。整个运行链路只包含开发板固件、macOS 原生 USB/HID/Audio 驱动和微信输入法，不包含 Mac 后台 App、LaunchAgent、辅助功能权限或 `hidutil` 映射。

由于没有后台 App，固件不能替用户修改 macOS 默认输入设备。首次使用时需要在“系统设置 → 声音 → 输入”中选择 `XIAO Voice Keyboard Microphone`；之后若系统切换到其他麦克风，也需要手动选回。

## USB Composite 结构

设备身份：

- Vendor ID：`0x2886`（Seeed Studio）
- Product ID：`0x0060`
- 固件版本：`0x0201`
- 产品名：`XIAO Voice Keyboard V2 Direct`

Product ID 与旧 V2 的 `0x005D` 分开，防止 macOS 复用旧 F13-only HID 描述符缓存。

一个 USB 配置包含：

1. HID interface
   - Consumer Control collection，Report ID 4，K1 使用。
   - Keyboard collection，Report ID 1，K2/K3 使用。
2. Audio Control interface
   - 名称 `XIAO Voice Keyboard Microphone`。
3. Audio Streaming interface
   - 16 kHz、16-bit、单声道、每个 USB 包 32 字节。

Consumer 与 Keyboard 共用 HID interrupt endpoints，不额外增加 USB interface。音频继续通过 `USB_INTERFACE_CUSTOM` 注册 TinyUSB Audio 描述符和 class driver。

## K1：直连 Globe/Fn

K1 使用 Consumer Page `0x0C` / `AC Next Keyboard Layout Select 0x029D`。描述符是 16-bit array：

```c
constexpr uint8_t kNextKeyboardLayoutReportDescriptor[] = {
    0x05, 0x0C,        // Usage Page (Consumer)
    0x09, 0x01,        // Usage (Consumer Control)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x04,        // Report ID (4)
    0x15, 0x00,        // Logical Minimum (0)
    0x26, 0xFF, 0x03,  // Logical Maximum (0x03FF)
    0x19, 0x00,        // Usage Minimum (0)
    0x2A, 0xFF, 0x03,  // Usage Maximum (0x03FF)
    0x75, 0x10,        // Report Size (16)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x00,        // Input (Data, Array, Absolute)
    0xC0,
};
```

线上的 input report：

| K1 状态 | 报告字节 | 含义 |
|---|---|---|
| 按下/保持 | `04 9D 02` | Report ID 4，Usage `0x029D` |
| 松开 | `04 00 00` | Report ID 4，无 Consumer selection |

固件在防抖后的状态变化时发送报告。如果枚举尚未完成或 endpoint 暂时忙，状态会保留并重试；按下报告成功后保持逻辑按下状态，直到松开报告成功。

Generic Desktop Page 的 `System Function Shift 0x97` 在同一 Mac 上不会进入 Apple Globe/Fn 事件路径，因此没有采用。对照实验保存在 `experiments/`，详细背景见 [`DIRECT_GLOBE_HID.md`](DIRECT_GLOBE_HID.md)。

## K2：发送

- 引脚：D1。
- 稳定按下时通过 `USBHIDKeyboard` 发送一组 Return press/release。
- 松开状态必须持续约 250 ms 才重新允许发送。
- K3 活动时锁住 K2，降低相邻按键或线缆串扰造成误发送的风险。

## K3：取消/清空

- 引脚：D0。
- 持续按住约 1.5 秒后执行一次 Command+A、Backspace。
- `longActionDone` 保证同一次长按只执行一次。
- K1 正在按下时不执行，避免语音输入和清空序列相互干扰。

## USB 麦克风

- INMP441：SCK → D9、WS → D10、SD → D8、L/R → GND。
- I²S：16 kHz、32-bit slot，固件取有效 24-bit 数据并转为带增益的 signed 16-bit PCM。
- 固件比较左右 slot 能量，自动选取实际承载 INMP441 数据的 slot。
- 2048 个采样点的环形缓冲区保留最近约 128 ms 音频。
- TinyUSB 在每次 isochronous IN 请求时同步写入完整 32 字节数据包。

`platformio.ini` 必须同时满足：

```ini
build_unflags =
    -DARDUINO_USB_CDC_ON_BOOT=1
build_flags =
    -DARDUINO_USB_MODE=1
    -DARDUINO_USB_CDC_ON_BOOT=0
```

不能为课程固件打开 USB CDC。旧版 ESP32-S3 USB driver 假设 IN endpoint 编号与 TX FIFO 编号一致，CDC 会预留端点并破坏 isochronous audio。

## 构建与发布镜像

```bash
cd variants/2-three-key-voice-send-cancel/source/firmware
pio run
```

应用镜像位于 `.pio/build/seeed_xiao_esp32s3/firmware.bin`，单独烧录地址为 `0x10000`。发布目录还包含可直接写入 `0x0` 的完整镜像，以及 bootloader、分区表和 boot_app0。

## 验证清单

固件发布前至少检查：

1. `pio run` 编译成功，且实际编译参数只有 `ARDUINO_USB_CDC_ON_BOOT=0`。
2. `ioreg` 显示产品名 `XIAO Voice Keyboard V2 Direct`、PID `0x0060`。
3. HID ReportDescriptor 同时含 Report ID 4 Consumer collection 与 Report ID 1 Keyboard collection。
4. `AppleUserHIDEventService` 显示 `SupportsGlobeKey = Yes`。
5. USB Audio Control 与 Streaming interfaces 均枚举，`AppleUSBAudioStreamPropertiesReady = Yes`。
6. CoreAudio 列出 `XIAO Voice Keyboard Microphone`、16 kHz、1 input channel。
7. 麦克风录音具有非零 frames、peak 和 RMS。
8. K1 长按开始、松开结束语音；K2 每次只发送一次；K3 短按无动作、长按只清空一次。

2026-10-04 实机回归中，10 秒麦克风录音得到 475,200 帧，peak 约 1.03、RMS 约 0.142；macOS 同时识别 Consumer、Keyboard 和 USB Audio 接口。

## 兼容性边界

- `0x029D` 的标准名称是 AC Next Keyboard Layout Select，不是通用的 Apple Fn modifier。
- 已验证目标是微信输入法的 Fn/地球键语音路径；只监听 Quartz Fn modifier 的其他应用可能不响应。
- 不同 macOS 或输入法版本可能改变处理方式。课程应保留 V1 Fn Bridge Edition 作为兼容回退，但 V2 默认发行包不再包含或安装 Fn Bridge。
