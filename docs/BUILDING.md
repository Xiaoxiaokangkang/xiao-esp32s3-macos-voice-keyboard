# 从源码构建

所有正式版本都包含功能复现所需的固件源码。构建说明严格按照正式版本顺序排列：V1 Direct HID Edition / V1 免安装版、V1 Fn Bridge Edition / V1 桥接兼容版、V2、V3。桥接兼容版、V2 和 V3 还包含 Mac 源码；免安装版不需要 Mac 端程序。Legacy 单键方案没有原始固件源码，公开版也不提供历史完整 Flash，因此只能阅读方案介绍。

## 固件构建

需要安装 PlatformIO。四个正式固件工程都固定使用 `espressif32 @ 6.13.0` 和 `seeed_xiao_esp32s3` 开发板定义。

进入所选版本的 `source/firmware` 后运行：

```bash
pio run
```

生成的应用固件位于：

```text
.pio/build/seeed_xiao_esp32s3/firmware.bin
```

连接处于下载模式的 XIAO 后，可直接从源码构建并上传：

```bash
pio run --target upload
```

仓库中的预编译“完整固件”可写入 `0x0`；源码构建的 `firmware.bin` 是应用镜像，单独烧录时使用 `0x10000`。完整镜像还包含 bootloader、分区表和 boot_app0。

本次发布整理时，四个正式 PlatformIO 工程均已在本机成功编译。由于工具链元数据和构建环境可能变化，重新编译的二进制 SHA-256 不保证与归档中的预编译文件逐字节相同；功能源码和固定 PlatformIO 平台版本保持一致。

## 1. V1 Direct HID Edition / V1 免安装版

正式的无 Fn Bridge 工程位于：

```text
variants/1-three-key-k1-voice-direct-hid/source/firmware
```

它使用与 V1 Fn Bridge Edition / V1 桥接兼容版相同的 PlatformIO、Arduino、TinyUSB Audio 和硬件配置，只把 K1 的 F13 Keyboard report 替换为 Consumer HID `0x029D`。构建和上传命令与其他固件相同。预编译的一体化镜像及分立镜像保存在该版本的 `firmware/` 中。

详细实现与实机结果见 [`DIRECT_GLOBE_HID.md`](DIRECT_GLOBE_HID.md)。Test A/Test B 的原始验证工程位于 `experiments/`。

## 2. V1 Fn Bridge Edition / V1 桥接兼容版

进入 `variants/1-three-key-k1-voice/source/macos`，运行：

```bash
./build-macos.command
```

脚本使用系统自带的 `xcrun clang` 同时构建 arm64 和 x86_64，并在 `build/Fn Bridge.app` 生成 ad-hoc 签名的 Universal App。

`fn_bridge.m` 是当前预编译 App 对应的主要 Objective-C 实现。目录中的 Swift 文件是开发期实现和诊断工具源码，保留用于审计、测试和后续修改。

## 3. V2 的固件与 Fn Bridge

V2 固件位于 `variants/2-three-key-voice-send-cancel/source/firmware`，Mac 源码位于同一版本的 `source/macos`。固件使用前述 `pio run` 命令构建，Fn Bridge 使用 `./build-macos.command` 构建。

## 4. V3 的固件与两个 Mac App

进入 `variants/3-three-key-traework/source/macos`，运行：

```bash
./build-macos.command
```

脚本将生成：

- `build/Fn Bridge.app`
- `build/TraeWork Bridge.app`

两个 App 都是 arm64 + x86_64 Universal Binary，并使用 ad-hoc 签名。若要公开分发并减少 Gatekeeper 提示，需要使用自己的 Apple Developer ID 完成签名和公证；任何签名私钥、证书密码或公证凭据都不应提交到仓库。

## 可重复构建的边界

本仓库支持从公开源码重建功能等价的固件和 Mac 程序，但不承诺 bit-for-bit reproducible build。编译器版本、SDK、链接器、签名和构建时间等因素都可能改变最终文件哈希。
