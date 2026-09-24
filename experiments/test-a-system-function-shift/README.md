# Test A：System Function Shift（0x97）

这个实验从 V1 Known-Good 固件复制而来，专门验证 XIAO ESP32S3 能否不借助 Fn Bridge 或 `hidutil`，通过 USB HID 直接让 macOS 识别 Fn 状态。

## 实验边界

- K1 仍接 D2，继续使用 V1 的启动状态学习和 25 ms 防抖。
- K2、K3 不启用。
- USB Audio 麦克风的描述符、I2S 采集和数据发送代码保持不变。
- 不包含 Fn Bridge，也不发送 F13。
- HID 只包含一个 Generic Desktop `System Control` Application Collection，以及其中的 `System Function Shift`（Usage `0x97`）状态位。

该 Usage 的名称、类型和 `1=on / 0=off` 语义来自 USB-IF [HID Usage Tables](https://www.usb.org/sites/default/files/hut1_3_0.pdf) 的 Generic Desktop / System Controls 表。

K1 稳定按下时发送值 `1`，并保持这个 HID 状态；K1 稳定松开时发送值 `0`。没有自动延时释放，也不重复发送脉冲。

测试固件使用单独的 USB Product ID `0x005E`、固件版本 `0x0A01` 和产品名 `XIAO System Function Shift Test A`，避免 macOS 沿用 V1（PID `0x005D`）的旧 HID 描述符缓存。

## 构建和上传

```bash
cd experiments/test-a-system-function-shift/source/firmware
pio run
pio run --target upload
```

源码构建出的应用镜像在 `.pio/build/seeed_xiao_esp32s3/firmware.bin`。直接写应用镜像时沿用原项目的 `0x10000` 地址；不要把它当作从 `0x0` 开始的完整 Flash 镜像。

## macOS 验证顺序

1. 退出 Fn Bridge；本实验不需要辅助功能权限，也不要设置 `hidutil` 映射。
2. 烧录并重新插拔设备，确认系统中出现 `XIAO System Function Shift Test A` 和原有 USB 麦克风接口。
3. 可先运行 `hidutil list --matching '{"ProductID":0x005e}'` 确认 HID 服务，再使用 IORegistryExplorer、`ioreg` 或其他 HID 观察工具确认报告描述符包含 Generic Desktop Page `0x01` / System Function Shift `0x97`。这里只读取状态，不设置映射。
4. 按住 K1，观察 macOS 是否持续产生 Fn 状态；松开 K1，确认该状态立即消失。
5. 若系统层识别成功，再让文本框获得焦点并测试微信输入法的 Fn 长按语音输入与松开结束。

只有实机观察才能判定 macOS 是否把标准 Usage `0x97` 接入 Apple 的 Fn/Globe 事件路径。编译成功只能证明固件和描述符可被当前工程接受，不能替代这一步。

## Test B（后续）

如果 Test A 在 macOS 系统层没有 Fn 行为，再另建 Test B，使用 Consumer Page `0x0C` / `AC Next Keyboard Layout Select` `0x029D`。不要在本实验里同时声明两个 Usage，否则无法判断到底是哪一个产生了行为。
