# CDDA Termux 构建器（中文版）

**语言 / Language:** [English](README.md) · 简体中文

在 Android 手机（通过 Termux）上一条命令构建 Cataclysm: Dark Days Ahead (CDDA) 游戏客户端，生成 Android APK。

脚本自动完成：安装依赖、下载 NDK/SDK、获取最新源码、配置环境、构建 APK，并内置重试机制。

## 功能特点

- **一条命令安装** – 在全新 Termux 粘贴一条命令，自动补齐 `git`、克隆仓库、跑完整构建。
- **源码管理** – 自动克隆 CDDA 并切换到最新标签（或任意指定标签）。
- **自动配置** – 设置 `buildToolsVersion`、`override_ndkVersion` 和 SDK 版本。
- **失败重试** – 构建失败自动重试最多 3 次。
- **APK 验证** – 拒绝空文件或小于 1MB 的无效 APK。
- **可选通知** – 使用 Termux:API 在构建完成时发送通知。
- **界面本地化** – 支持英文和简体中文，运行时切换。
- **可定制** – 通过环境变量自定义源码目录、构建变体、通知开关、语言等。

## 系统要求

- Android 设备（建议 6GB+ 内存，剩余存储空间 15GB+）
- Termux（推荐 [F-Droid 版本](https://f-droid.org/repo/com.termux_118.apk)）
- 稳定的网络连接（首次运行需下载约 600MB 的 NDK/SDK）

## 快速开始

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/dwvwvvwvwb/cdda-termux-builder/main/install.sh)"
```

就这样。引导脚本会在缺少 git 时自动安装，克隆或更新构建器，然后执行 ./scripts/cdda.sh all --yes latest。

如果希望先检查引导脚本再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/dwvwvvwvwb/cdda-termux-builder/main/install.sh -o install.sh
less install.sh
bash install.sh
```

可以通过引导脚本透传任意子命令或选项：

```bash
# 构建指定标签
bash -c "$(curl -fsSL .../install.sh)" all --yes cdda-experimental-2026-03-24-2310

# 仅安装依赖
bash -c "$(curl -fsSL .../install.sh)" setup --yes
```

构建成功后，APK 位于 ~/Cataclysm-DDA/android/app/build/outputs/apk/。

使用说明

```
./cdda.sh [命令] [选项]

命令:
  setup [--yes]              安装系统依赖和 SDK/NDK（首次运行）
  config [--yes] [tag]       配置项目（tag 可以是具体标签名或 "latest" 获取最新）
  build [--clean] [--yes]    构建 APK（--clean 可清理后构建）
  all [--yes] [tag]          依次执行 setup, config, build
  clean                      仅清理构建产物
  lang [zh_CN|en]            设置或显示界面语言
  help                       显示帮助

环境变量:
  WORK_DIR        源码目录（默认 ~/Cataclysm-DDA）
  BUILD_VARIANT   构建变体 release/debug（默认 release）
  NOTIFY          是否发送通知 true/false（默认 true）
  CDDA_LANG       界面语言 en/zh_CN（默认自动检测）
  GITHUB_TOKEN    可选的 GitHub Personal Access Token（见下方"GitHub 令牌"）
```

界面语言

界面文本通过 main 分支下的单一 locales/zh_CN.po 文件维护。首次运行时，语言按以下顺序解析：

1. CDDA_LANG 环境变量
2. ~/.config/cdda-termux-builder/lang（由 ./cdda.sh lang ... 写入）
3. getprop persist.sys.locale（Android / Termux）
4. LANG 前缀（标准 Linux）
5. en

可用语言由 locales/*.po 自动发现。新增语言只需把 .po 文件放进该目录，无需改代码。翻译新语言时，复制 locales/zh_CN.po，修改 Language: 头，翻译 msgstr，运行 ./check-i18n.sh 校验。

持久切换语言：

```bash
./cdda.sh lang zh_CN
./cdda.sh lang en
```

或临时切换：

```bash
CDDA_LANG=zh_CN ./cdda.sh all --yes latest
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

GitHub 令牌（推荐）

当 TAG=latest 时，脚本会请求 GitHub Releases API 解析最新标签。该端点可匿名访问，但限流差异很大：

方式 限流 说明
设置 GITHUB_TOKEN 5000 次/小时 按令牌计
匿名 60 次/小时 按 IP 计；VPS、CI runner、代理池等共享 IP 极易被连坐限流

如果在获取最新标签时遇到莫名的 403，几乎都是匿名限流。设置令牌即可避免：

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
./cdda.sh all --yes latest
```

· classic token：勾选 repo 即可（公开仓库不勾通常也能读，但勾了更稳）。
· fine-grained token：选择 CleverRaven/Cataclysm-DDA，权限给 Contents: Read。
· 不设令牌脚本也能跑，只是会警告限流较低并继续匿名请求。

签名 APK（可选）

如需生成已签名的 APK，请在构建前将 keystore.properties 文件放入 Cataclysm-DDA/android/ 目录。

文件内容示例：

```
storeFile=/path/to/keystore.jks
storePassword=your_store_password
keyAlias=your_key_alias
keyPassword=your_key_password
```

构建时 Gradle 会自动读取并签名。

使用 ccache 加速后续构建

ccache 已自动安装，并在构建时默认启用。它可以缓存编译产物，显著减少重复构建的时间。

1. 如需调整缓存行为（如压缩或限制大小），可以在运行脚本前设置环境变量：
   ```bash
   export CCACHE_COMPRESS=1          # 启用压缩，节省空间
   export CCACHE_MAXSIZE=5G          # 限制缓存大小为 5GB
   ```
2. 缓存默认保存在 ~/.ccache 目录。使用 ccache -s 查看统计，ccache -C 清理缓存。
3. 正常执行构建命令（如 ./cdda.sh all --yes latest）。

工作原理

1. 引导 – install.sh 在缺少 git 时安装，浅克隆构建器仓库到 ~/cdda-termux-builder，然后 exec 进入 ./scripts/cdda.sh。
2. 安装阶段 – 通过 pkg 安装 git、make、clang、curl、jq、xz-utils、gettext、openjdk-17、coreutils、which、cmake、ninja、ccache。从 lzhiyong/termux-ndk 下载并校验 NDK 和 SDK，并自动创建 cmake/ninja 符号链接到 SDK 目录。
3. 配置阶段 – 浅克隆 CDDA 源码，切换到指定标签。创建 local.properties，写入 SDK/NDK 路径和版本覆盖。
4. 构建阶段 – 临时向 app/build.gradle 添加 buildToolsVersion，强制使用正确的 NDK 工具链（linux-x86_64），运行 ./gradlew assembleRelease（或 debug）。成功后定位 APK（>1MB）并发送通知。

常见问题

NDK 中 clang++ 权限被拒绝

脚本会自动修复符号链接。如果问题持续，删除 ~/android-ndk-r29 并重新运行 ./cdda.sh setup。

Gradle 试图下载 build-tools 30.0.3

脚本会在 build.gradle 中添加 buildToolsVersion "35.0.0"（或你本地最高版本），阻止下载。请确保 SDK 中至少有一个 build-tools 版本（如 35.0.0）。

Java 版本错误

脚本会自动设置 JAVA_HOME 指向 OpenJDK 17。如果安装了多个 Java，确保 java -version 显示为 OpenJDK 17。

磁盘空间不足

清理旧构建产物和日志：rm -rf ~/Cataclysm-DDA ~/android-ndk-r29 ~/android-sdk ~/.cdda_build_logs/*。脚本启动时会检查空间并警告。

获取最新标签时 HTTP 403

几乎都是匿名限流（60 次/小时，按 IP 计）。按上方"GitHub 令牌"设置 GITHUB_TOKEN 即可。API 响应体（Bad credentials、API rate limit exceeded 等）会打印在日志里，便于区分认证失败与限流。

致谢

· lzhiyong 提供了 Termux 兼容的 Android NDK 和 SDK 包。
· Cataclysm-DDA 开发团队。

许可证

本项目采用 GNU General Public License v3.0 – 详见 LICENSE 文件。