# XIAO ESP32S3 macOS 语音键盘

这是一个基于 Seeed Studio XIAO ESP32S3、INMP441 麦克风和实体按键的 macOS USB 语音键盘项目。V1 同时提供免安装的 Direct HID Edition 和兼容性的 Fn Bridge Edition；V2、V3 继续使用仓库中的 Mac 端桥接程序。

仓库的课程主线按功能复杂度分为 `V1` 至 `V3`，与 Windows 仓库使用相同编号。旧版单键方案移入 Legacy 历史归档，不再占用课程版本号。请根据目标功能选择版本，不要混刷。

## 版本选择

| 顺序 | 课程版本 | 实现方式 | Mac 端安装 | 按键功能 |
|---:|---|---|---|---|
| 1A | [V1 Direct HID Edition（推荐）](variants/1-three-key-k1-voice-direct-hid/README.md) | USB Consumer HID `0x029D` | 不需要 | K1 语音输入，K2/K3 暂未启用 |
| 1B | [V1 Fn Bridge Edition（兼容）](variants/1-three-key-k1-voice/README.md) | F13 → Fn Bridge → Fn | 需要 | K1 语音输入，K2/K3 暂未启用 |
| 2 | [V2：语音、发送、取消](variants/2-three-key-voice-send-cancel/README.md) | F13 + Fn Bridge | 需要 | K1 语音、K2 发送、K3 长按取消/清空 |
| 3 | [V3：TraeWork CN](variants/3-three-key-traework/README.md) | F13/F16 + Bridge | 需要 | K1 调用 TraeWork、K2 语音/切换输入法、K3 发送 |

旧版一个按键、旧接线的方案保存在 [Legacy：旧版单键语音输入](legacy/one-key-m3/README.md)，仅供历史参考，不属于课程 V1–V3。

更详细的横向比较见 [版本说明](docs/VERSIONS.md)。

## 无 Fn Bridge 的直连版本

[V1 Direct HID Edition](variants/1-three-key-k1-voice-direct-hid/README.md) 已在 XIAO ESP32S3、macOS 27.0（Build 26A428）和微信输入法上完成实机验证：K1 长按开始语音输入，松开结束。

- 成功方案：Consumer Page `0x0C` / `AC Next Keyboard Layout Select` `0x029D`
- 失败对照：Generic Desktop Page `0x01` / `System Function Shift` `0x97`
- 完整技术报告：[USB HID 直连 Globe 技术报告](docs/DIRECT_GLOBE_HID.md)
- A/B 实验记录：[experiments/README.md](experiments/README.md)

正式版本使用独立目录、产品名和 Product ID，没有覆盖 Fn Bridge Edition 或 V2/V3 Known-Good 版本。

## 硬件

- Seeed Studio XIAO ESP32S3（8 MB Flash）
- INMP441 I²S 麦克风
- 三个按键
- macOS 12 或更高版本
- 微信输入法；V3 还需要 TRAE SOLO CN

## 使用前必读

1. 不同版本的接线和按键电平并不完全相同，刷写前必须阅读对应版本的 README。
2. 烧录操作会覆盖开发板现有固件，请先确认设备和串口。
3. Fn Bridge Edition、V2 和 V3 的 Mac 端 App 是 Universal Binary，可运行于 Apple Silicon 和 Intel Mac，但当前仅为 ad-hoc 签名，并非 Apple Developer ID 公证版本。
4. 只有桥接版本的安装脚本会把 App 写入 `/Applications`、创建用户级 LaunchAgent，并可能请求管理员密码与辅助功能权限；V1 Direct HID Edition 不需要这些步骤。
5. 本项目不读取微信聊天内容。桥接程序只处理指定设备的功能键、输入设备切换，以及特定版本的前台应用聚焦操作。

相关权限和风险说明见 [安全说明](SECURITY.md)。

## 源码与复现

所有正式版本均提供固件源码和固定版本的 PlatformIO 配置。使用桥接程序的版本还提供 Mac 端源码、App Info.plist 和构建脚本；V1 Direct HID Edition 没有也不需要 Mac App。完整步骤见 [构建说明](docs/BUILDING.md)。

发布前已经检查源码，未发现密码、API Token、私钥、Wi-Fi 凭据、个人绝对路径、原设备编号或网络上传逻辑。源码公开本身不会赋予他人访问作者电脑的权限。

Legacy 单键方案源自旧设备，原始资料没有对应固件源码，因此不能进行源码级复现。出于隐私考虑，公开版只保留方案介绍和旧 Mac 安装包，不发布完整 Flash。

## 编号迁移说明

自 2026 年 9 月起，macOS 版本号与 Windows 版本和课程内容统一：原 macOS V2、V3、V4 分别调整为 V1、V2、V3；原 macOS 单键 V1 移至 Legacy。USB `ProductID` 作为兼容标识保持不变，用户可见的产品名、固件版本、文件名和文档编号均已按新编号重新生成。

## 完整性校验

仓库根目录的 `SHA256SUMS.txt` 记录全部发布文件的 SHA-256。下载后可在仓库目录运行：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## 项目状态

- V1 Direct、V1 Bridge、V2 和 V3 使用相同的三键硬件与麦克风接线，但按键逻辑和 USB 产品名不同。
- USB 产品名分别显示为 `XIAO Voice Keyboard V1 Direct`、`XIAO Voice Keyboard V1`、`XIAO Voice Keyboard V2` 和 `XIAO Voice Keyboard V3 TraeWork`。
- Legacy 单键方案不提供固件镜像或可重新编译的固件源码。
- 当前仓库没有电路板 Gerber、原理图、实物照片或演示视频；这些内容以后可以继续补充。

## 许可

本仓库采用面向个人非商业用途的 source-available 许可：允许查看、编译和为个人使用而修改源码，但不自动授予商业使用或再发布权。详情见 [LICENSE](LICENSE)。第三方组件声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
