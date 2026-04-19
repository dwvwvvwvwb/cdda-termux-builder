# CDDA Termux Builder

![Build Status](https://img.shields.io/badge/build-passing-brightgreen) ![License](https://img.shields.io/badge/license-GPLv3-blue)

Build [Cataclysm: Dark Days Ahead](https://github.com/CleverRaven/Cataclysm-DDA) (CDDA) natively on Android using Termux.  
Generate APK (Android) or Linux executable without a PC.

This script automates the entire process: install dependencies, download NDK/SDK, fetch the latest CDDA source, configure the build environment, and build the APK with automatic retries.

## Features

- **One-command setup** – installs Termux packages, Android NDK, and SDK.
- **Automatic source management** – clones CDDA and checks out the latest tag (or any specified tag).
- **Build configuration** – automatically sets `buildToolsVersion`, `override_ndkVersion`, and SDK versions.
- **Retry on failure** – builds retry up to 3 times for transient issues.
- **APK validation** – rejects empty or corrupted APKs (<1MB).
- **Optional notifications** – uses Termux:API to notify when build finishes.
- **Customizable** – via environment variables (`WORK_DIR`, `BUILD_VARIANT`, `NOTIFY`).

## Requirements

- Android device with at least 6 GB RAM and 15 GB free storage.
- [Termux](https://f-droid.org/repo/com.termux_118.apk) (F-Droid version recommended).
- Stable internet connection (first run downloads ~600 MB NDK/SDK).

## Quick Start

```bash
# Clone this repository
git clone --depth 1 https://github.com/dwvwvvwvwb/cdda-termux-builder.git
cd cdda-termux-builder/scripts

# Make scripts executable
chmod +x *.sh

# Full build (latest release) – skip confirmations
./cdda.sh all --yes latest
```

After success, the APK will be in ~/Cataclysm-DDA/android/app/build/outputs/apk/.

Usage

```
./cdda.sh [command] [options]

Commands:
  setup [--yes]      Install system dependencies, NDK, and SDK.
  config [--yes] [tag]   Configure project (tag can be "latest" or a specific tag).
  build [--clean]    Build the APK (--clean cleans before build).
  all [--yes] [tag]  Run setup, config, and build in sequence.
  clean              Only clean build artifacts.
  help               Show this help.

Environment variables:
  WORK_DIR          Source directory (default: ~/Cataclysm-DDA)
  BUILD_VARIANT     release or debug (default: release)
  NOTIFY            true/false (default: true)
```

Examples

```bash
# Build the latest release (interactive)
./cdda.sh all latest

# Build a specific tag with automatic confirmation
./cdda.sh all --yes cdda-experimental-2026-03-24-2310

# Only configure the project for latest tag
./cdda.sh config latest

# Build with debug variant and no notifications
BUILD_VARIANT=debug NOTIFY=false ./cdda.sh build
```

## Signing the APK (Optional)

To generate a signed APK, place a `keystore.properties` file in `Cataclysm-DDA/android/` before building.  
Example:
```

storeFile=/path/to/keystore.jks
storePassword=your_store_password
keyAlias=your_key_alias
keyPassword=your_key_password

```
The build will automatically sign the APK.

## Speed up subsequent builds with ccache (Optional)

If you build frequently, `ccache` can cache compiled objects and reduce build time.

1. Install ccache:
   ```bash
   pkg install ccache
   ```

1. Enable ccache by setting the environment variable before running the script:
   ```bash
   export USE_CCACHE=1
   ```
   To save disk space, you can also enable compression:
   ```bash
   export CCACHE_COMPRESS=1
   ```
   The cache is stored in ~/.ccache by default. You can check its size with ccache -s and clean it with ccache -C if needed.
2. Run the build script as usual (e.g., ./cdda.sh all --yes latest).

How It Works

1. Setup – installs git, make, clang, curl, jq, 7zip, gettext, openjdk-17, coreutils, which via pkg. Downloads and verifies NDK and SDK from lzhiyong/termux-ndk releases.
2. Config – clones CDDA (shallow clone) and checks out the specified tag. Creates local.properties with SDK/NDK paths and version overrides.
3. Build – temporarily adds buildToolsVersion to app/build.gradle, forces use of the correct NDK toolchain (linux-x86_64), and runs ./gradlew assembleRelease (or debug). On success, locates the APK (>1MB) and sends a notification.

Troubleshooting

"Permission denied" for clang++ in NDK

The script automatically fixes this by recreating the symbolic link. If it persists, delete ~/android-ndk-r29 and run ./cdda.sh setup again.

Gradle tries to download build-tools 30.0.3

The script adds buildToolsVersion "35.0.0" (or your highest available) to build.gradle to prevent this. Ensure your SDK contains at least one build-tools version (e.g., 35.0.0).

Build fails with Java version error

The script sets JAVA_HOME automatically for OpenJDK 17. If you have multiple Java versions, ensure OpenJDK 17 is the default (java -version).

Disk space insufficient

Clean up old builds and logs: rm -rf ~/Cataclysm-DDA ~/android-ndk-r29 ~/android-sdk .cdda_build_logs/*. The script checks free space and warns.

Credits

· lzhiyong for providing Termux-compatible Android NDK and SDK packages.
· Cataclysm-DDA team for the game.

License

This project is licensed under the GNU General Public License v3.0 – see the LICENSE file for details.

Language Branches

· English version – this main branch.
· Chinese version – available in the zh-CN branch.
    Switch with git checkout zh-CN to get Chinese documentation and scripts.
