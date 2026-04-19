# CDDA Termux 构建器（中文版）

> 本仓库为中文版本，英文版请查看 `main` 分支。

在 Android 手机（通过 Termux）上一键构建 Cataclysm: Dark Days Ahead (CDDA) 游戏客户端，生成 Android APK。

脚本自动完成：安装依赖、下载 NDK/SDK、获取最新源码、配置环境、构建 APK，并内置重试机制。

## 功能特点

- **一键安装** – 自动安装 Termux 软件包、Android NDK 和 SDK。
- **源码管理** – 自动克隆 CDDA 并切换到最新标签（或任意指定标签）。
- **自动配置** – 设置 `buildToolsVersion`、`override_ndkVersion` 和 SDK 版本。
- **失败重试** – 构建失败自动重试最多 3 次。
- **APK 验证** – 拒绝空文件或小于 1MB 的无效 APK。
- **可选通知** – 使用 Termux:API 在构建完成时发送通知。
- **可定制** – 通过环境变量自定义源码目录、构建变体、通知开关等。

## 系统要求

- Android 设备（建议 6GB+ 内存，剩余存储空间 15GB+）
- Termux（推荐 [F-Droid 版本](https://f-droid.org/repo/com.termux_118.apk)）
- 稳定的网络连接（首次运行需下载约 600MB 的 NDK/SDK）

## 快速开始

```bash
# 克隆本仓库（中文版）
git clone --depth 1 --branch zh-CN https://github.com/dwvwvvwvwb/cdda-termux-builder.git
cd cdda-termux-builder/scripts

# 赋予执行权限
chmod +x *.sh

# 全自动构建最新版本（跳过所有确认）
./cdda.sh all --yes latest
```

构建成功后，APK 位于 ~/Cataclysm-DDA/android/app/build/outputs/apk/。

使用说明

```
./cdda.sh [命令] [选项]

命令:
  setup [--yes]    安装系统依赖和 SDK/NDK（首次运行）
  config [--yes] [tag]  配置项目（tag 可以是具体标签名或 "latest" 获取最新）
  build [--clean] [--yes] 构建 APK（--clean 可清理后构建）
  all [--yes] [tag]      依次执行 setup, config, build
  clean                  仅清理构建产物
  help                   显示帮助

环境变量:
  WORK_DIR        源码目录（默认 ~/Cataclysm-DDA）
  BUILD_VARIANT   构建变体 release/debug（默认 release）
  NOTIFY          是否发送通知 true/false（默认 true）
```

示例

```bash
# 交互式构建最新版本
./cdda.sh all latest

# 自动确认并构建指定标签
./cdda.sh all --yes cdda-experimental-2026-03-24-2310

# 仅配置项目（切换到最新标签）
./cdda.sh config latest

# 构建 debug 版本，不发送通知
BUILD_VARIANT=debug NOTIFY=false ./cdda.sh build
```

## 签名 APK（可选）

如需生成已签名的 APK，请在构建前将 `keystore.properties` 文件放入 `Cataclysm-DDA/android/` 目录。  
文件内容示例：
```

storeFile=/path/to/keystore.jks
storePassword=your_store_password
keyAlias=your_key_alias
keyPassword=your_key_password

```
构建时 Gradle 会自动读取并签名。

## 使用 ccache 加速后续构建（可选）

如果您需要频繁构建，可以使用 `ccache` 缓存编译产物，减少构建时间。

1. 安装 ccache：
   ```bash
   pkg install ccache
   ```

1. 运行脚本前设置环境变量启用缓存：
   ```bash
   export USE_CCACHE=1
   ```
   如需节省存储空间，可同时启用压缩：
   ```bash
   export CCACHE_COMPRESS=1
   ```
   缓存默认保存在 ~/.ccache 目录。您可以用 ccache -s 查看大小，用 ccache -C 清理缓存。
2. 正常执行构建命令（如 ./cdda.sh all --yes latest）。

工作原理

1. 安装阶段 – 通过 pkg 安装 git、make、clang、curl、jq、7zip、gettext、openjdk-17、coreutils、which。从 lzhiyong/termux-ndk 下载并校验 NDK 和 SDK。
2. 配置阶段 – 浅克隆 CDDA 源码，切换到指定标签。创建 local.properties，写入 SDK/NDK 路径和版本覆盖。
3. 构建阶段 – 临时向 app/build.gradle 添加 buildToolsVersion，强制使用正确的 NDK 工具链（linux-x86_64），运行 ./gradlew assembleRelease（或 debug）。成功后定位 APK（>1MB）并发送通知。

常见问题

NDK 中 clang++ 权限被拒绝

脚本会自动修复符号链接。如果问题持续，删除 ~/android-ndk-r29 并重新运行 ./cdda.sh setup。

Gradle 试图下载 build-tools 30.0.3

脚本会在 build.gradle 中添加 buildToolsVersion "35.0.0"（或你本地最高版本），阻止下载。请确保 SDK 中至少有一个 build-tools 版本（如 35.0.0）。

Java 版本错误

脚本会自动设置 JAVA_HOME 指向 OpenJDK 17。如果安装了多个 Java，确保 java -version 显示为 OpenJDK 17。

磁盘空间不足

清理旧构建产物和日志：rm -rf ~/Cataclysm-DDA ~/android-ndk-r29 ~/android-sdk .cdda_build_logs/*。脚本启动时会检查空间并警告。

致谢

· lzhiyong 提供了 Termux 兼容的 Android NDK 和 SDK 包。
· Cataclysm-DDA 开发团队。

许可证

本项目采用 GNU General Public License v3.0 – 详见 LICENSE 文件。

语言分支

· 英文版 – main 分支
· 中文版 – zh-CN 分支
