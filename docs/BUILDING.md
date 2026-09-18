# 从源码构建

V2、V3 和 V4 已包含功能复现所需的固件与 Mac 源码。V1 没有原始固件源码，公开版也不提供历史完整 Flash，因此只能阅读方案介绍。

## 固件构建

需要安装 PlatformIO。三个固件工程都固定使用 `espressif32 @ 6.13.0` 和 `seeed_xiao_esp32s3` 开发板定义。

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

本次发布整理时，三个 PlatformIO 工程均已在本机成功编译。由于工具链元数据和构建环境可能变化，重新编译的二进制 SHA-256 不保证与归档中的预编译文件逐字节相同；功能源码和固定 PlatformIO 平台版本保持一致。

## V2 和 V3 的 Fn Bridge

进入相应版本的 `source/macos`，运行：

```bash
./build-macos.command
```

脚本使用系统自带的 `xcrun clang` 同时构建 arm64 和 x86_64，并在 `build/Fn Bridge.app` 生成 ad-hoc 签名的 Universal App。

`fn_bridge.m` 是当前预编译 App 对应的主要 Objective-C 实现。目录中的 Swift 文件是开发期实现和诊断工具源码，保留用于审计、测试和后续修改。

## V4 的两个 Mac App

进入 `variants/4-three-key-traework/source/macos`，运行：

```bash
./build-macos.command
```

脚本将生成：

- `build/Fn Bridge.app`
- `build/TraeWork Bridge.app`

两个 App 都是 arm64 + x86_64 Universal Binary，并使用 ad-hoc 签名。若要公开分发并减少 Gatekeeper 提示，需要使用自己的 Apple Developer ID 完成签名和公证；任何签名私钥、证书密码或公证凭据都不应提交到仓库。

## 可重复构建的边界

本仓库支持从公开源码重建功能等价的固件和 Mac 程序，但不承诺 bit-for-bit reproducible build。编译器版本、SDK、链接器、签名和构建时间等因素都可能改变最终文件哈希。
