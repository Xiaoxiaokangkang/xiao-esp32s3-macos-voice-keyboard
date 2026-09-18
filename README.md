# XIAO ESP32S3 macOS 语音键盘

这是一个基于 Seeed Studio XIAO ESP32S3、INMP441 麦克风和实体按键的 macOS USB 语音键盘项目。设备可作为 USB 键盘和 USB 麦克风使用，并通过本仓库提供的 Mac 端桥接程序调用微信输入法的 `Fn` 语音输入功能。

仓库按功能复杂度依次收录四套方案。版本号 `V1` 至 `V4` 同时代表推荐阅读和使用顺序，请根据硬件接线与目标功能选择，不要混刷。

## 版本选择

| 顺序 | 版本 | 硬件 | 按键功能 |
|---:|---|---|---|
| 1 | [V1 单键语音输入](variants/1-one-key-voice/README.md) | 1 个按键、旧接线 | 语音输入；仅保留历史介绍，不公开完整 Flash |
| 2 | [V2 三键硬件·K1 语音输入](variants/2-three-key-k1-voice/README.md) | 3 个按键、新接线 | K1 语音输入，K2/K3 暂未启用 |
| 3 | [V3 三键语音、发送、取消](variants/3-three-key-voice-send-cancel/README.md) | 3 个按键、新接线 | K1 语音、K2 发送、K3 长按取消/清空 |
| 4 | [V4 三键 TraeWork CN](variants/4-three-key-traework/README.md) | 3 个按键、新接线 | K1 调用 TraeWork、K2 语音/切换输入法、K3 发送 |

更详细的横向比较见 [版本说明](docs/VERSIONS.md)。

## 硬件

- Seeed Studio XIAO ESP32S3（8 MB Flash）
- INMP441 I²S 麦克风
- 一个或三个按键，取决于所选版本
- macOS 12 或更高版本
- 微信输入法；V4 还需要 TRAE SOLO CN

## 使用前必读

1. 不同版本的接线和按键电平并不完全相同，刷写前必须阅读对应版本的 README。
2. 烧录操作会覆盖开发板现有固件，请先确认设备和串口。
3. Mac 端 App 是 Universal Binary，可运行于 Apple Silicon 和 Intel Mac，但当前仅为 ad-hoc 签名，并非 Apple Developer ID 公证版本。
4. 安装脚本会把 App 写入 `/Applications`、创建用户级 LaunchAgent，并可能请求管理员密码与辅助功能权限。
5. 本项目不读取微信聊天内容。桥接程序只处理指定设备的功能键、输入设备切换，以及特定版本的前台应用聚焦操作。

相关权限和风险说明见 [安全说明](SECURITY.md)。

## 源码与复现

V2、V3 和 V4 均提供固件源码、固定版本的 PlatformIO 配置、Mac 端源码、App Info.plist 和构建脚本。用户既可以直接使用预编译文件，也可以从源码重新构建。完整步骤见 [构建说明](docs/BUILDING.md)。

发布前已经检查源码，未发现密码、API Token、私钥、Wi-Fi 凭据、个人绝对路径、原设备编号或网络上传逻辑。源码公开本身不会赋予他人访问作者电脑的权限。

V1 源自旧设备的历史方案，原始资料没有对应固件源码，因此不能进行源码级复现。出于隐私考虑，公开版只保留方案介绍和旧 Mac 安装包，不发布完整 Flash。

## 完整性校验

仓库根目录的 `SHA256SUMS.txt` 记录全部发布文件的 SHA-256。下载后可在仓库目录运行：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## 项目状态

- V1 是旧设备介绍，不提供固件镜像或可重新编译的固件源码。
- V2、V3 和 V4 使用相同的新麦克风接线，但按键逻辑和 USB 产品名不同。
- 新编号分别显示为 `XIAO Voice Keyboard V2`、`XIAO Voice Keyboard V3` 和 `XIAO Voice Keyboard V4 TraeWork`。
- 当前仓库没有电路板 Gerber、原理图、实物照片或演示视频；这些内容以后可以继续补充。

## 许可

本仓库采用面向个人非商业用途的 source-available 许可：允许查看、编译和为个人使用而修改源码，但不自动授予商业使用或再发布权。详情见 [LICENSE](LICENSE)。第三方组件声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
