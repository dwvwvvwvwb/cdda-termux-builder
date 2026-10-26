# CDDA Termux Builder (English)

**Language / 语言:** [简体中文](https://github.com/dwvwvvwvwb/cdda-termux-builder/blob/zh-CN/README.md) · English

> This is the English version. For the Chinese version, see the `zh-CN` branch.

Build the Cataclysm: Dark Days Ahead (CDDA) Android client on an Android phone via Termux with a single command, producing an Android APK.

The script handles everything automatically: installing dependencies, downloading the NDK/SDK, fetching the latest source, configuring the environment, building the APK, and retrying on failure.

## Features

- **One-command setup** – Automatically installs Termux packages, the Android NDK, and the SDK.
- **Source management** – Clones CDDA and checks out the latest tag (or any specified tag).
- **Auto-configuration** – Sets `buildToolsVersion`, `override_ndkVersion`, and SDK versions.
- **Retry on failure** – Retries the build up to 3 times.
- **APK validation** – Rejects empty or sub-1MB invalid APKs.
- **Optional notifications** – Sends a notification via Termux:API when the build finishes.
- **Customizable** – Configure the source directory, build variant, and notifications via environment variables.

## Requirements

- An Android device (6GB+ RAM recommended, 15GB+ free storage)
- Termux (the [F-Droid version](https://f-droid.org/repo/com.termux_118.apk) is recommended)
- A stable network connection (~600MB NDK/SDK download on first run)

## Quick Start

```bash
# Clone this repository (English version)
git clone --depth 1 --branch main https://github.com/dwvwvvwvwb/cdda-termux-builder.git
cd cdda-termux-builder/scripts

# Make scripts executable
chmod +x *.sh

# Full automated build of the latest release (skip all confirmations)
./cdda.sh all --yes latest
```

On success, the APK is located at `~/Cataclysm-DDA/android/app/build/outputs/apk/`.

## Usage

```
./cdda.sh [command] [options]

Commands:
  setup [--yes]              Install system dependencies and the SDK/NDK (first run)
  config [--yes] [tag]       Configure the project (tag can be a specific tag name or "latest")
  build [--clean] [--yes]    Build the APK (--clean cleans first)
  all [--yes] [tag]          Run setup, config, and build in sequence
  clean                      Remove build artifacts only
  help                       Show help

Environment variables:
  WORK_DIR        Source directory (default: ~/Cataclysm-DDA)
  BUILD_VARIANT   Build variant: release/debug (default: release)
  NOTIFY          Send notifications: true/false (default: true)
  GITHUB_TOKEN    Optional GitHub Personal Access Token (see "GitHub Token" below)
```

## Examples

```bash
# Interactive build of the latest release
./cdda.sh all latest

# Non-interactive build of a specific tag
./cdda.sh all --yes cdda-experimental-2026-03-24-2310

# Configure only (switch to the latest tag)
./cdda.sh config latest

# Build a debug variant without notifications
BUILD_VARIANT=debug NOTIFY=false ./cdda.sh build
```

## GitHub Token (Recommended)

When `TAG=latest`, the script queries the GitHub Releases API to resolve the latest tag. This endpoint works anonymously, but the rate limits differ significantly:

| Mode | Rate limit | Notes |
|------|------------|-------|
| With `GITHUB_TOKEN` | 5000 requests/hour | Per token |
| Anonymous | 60 requests/hour | Per IP; shared IPs (VPS, CI runners, proxy pools) are easily rate-limited |

If you hit a mysterious `403` while fetching the latest tag, it is almost always anonymous rate limiting. Setting a token avoids it:

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
./cdda.sh all --yes latest
```

- Classic token: the `repo` scope is enough (public repos may work without it, but including it is safer).
- Fine-grained token: select `CleverRaven/Cataclysm-DDA` and grant **Contents: Read**.
- Without a token the script still works; it just warns about the lower limit and continues anonymously.

## Signing the APK (Optional)

To produce a signed APK, place a `keystore.properties` file in `Cataclysm-DDA/android/` before building.

Example content:

```
storeFile=/path/to/keystore.jks
storePassword=your_store_password
keyAlias=your_key_alias
keyPassword=your_key_password
```

Gradle reads it automatically and signs the build.

## Speeding Up Subsequent Builds with ccache

`ccache` is installed automatically and enabled by default during builds. It caches compilation artifacts and significantly reduces rebuild time.

1. To tune cache behavior (e.g. compression or size limits), set environment variables before running the script:
   ```bash
   export CCACHE_COMPRESS=1          # Enable compression to save space
   export CCACHE_MAXSIZE=5G          # Limit the cache to 5GB
   ```

2. The cache is stored in `~/.ccache` by default. Use `ccache -s` to view stats and `ccache -C` to clear it.
3. Run the build command as usual (e.g. `./cdda.sh all --yes latest`).

## How It Works

1. **Setup** – Installs `git`, `make`, `clang`, `curl`, `jq`, `7zip`, `gettext`, `openjdk-17`, `coreutils`, `which`, `cmake`, `ninja`, and `ccache` via `pkg`. Downloads and verifies the NDK and SDK from `lzhiyong/termux-ndk`, and creates `cmake`/`ninja` symlinks in the SDK directory.
2. **Configure** – Shallow-clones the CDDA source and checks out the specified tag. Creates `local.properties` with the SDK/NDK paths and version overrides.
3. **Build** – Temporarily adds `buildToolsVersion` to `app/build.gradle`, forces the correct NDK toolchain (`linux-x86_64`), and runs `./gradlew assembleRelease` (or `debug`). On success, locates the APK (>1MB) and sends a notification.

## Troubleshooting

### "Permission denied" for `clang++` in the NDK

The script fixes the symlinks automatically. If the problem persists, delete `~/android-ndk-r29` and rerun `./cdda.sh setup`.

### Gradle tries to download build-tools 30.0.3

The script adds `buildToolsVersion "35.0.0"` (or your highest local version) to `build.gradle` to block the download. Make sure the SDK contains at least one build-tools version (e.g. 35.0.0).

### Wrong Java version

The script sets `JAVA_HOME` to OpenJDK 17 automatically. If multiple Java installations exist, ensure `java -version` reports OpenJDK 17.

### Out of disk space

Clean old build artifacts and logs: `rm -rf ~/Cataclysm-DDA ~/android-ndk-r29 ~/android-sdk .cdda_build_logs/*`. The script checks free space at startup and warns.

### HTTP 403 when fetching the latest tag

Almost always anonymous rate limiting (60 requests/hour per IP). Set `GITHUB_TOKEN` as described in "GitHub Token" above. The API response body (`Bad credentials`, `API rate limit exceeded`, etc.) is printed in the logs to help distinguish authentication failures from rate limiting.

## Acknowledgements

- [lzhiyong](https://github.com/lzhiyong) for the Termux-compatible Android NDK and SDK packages.
- The Cataclysm-DDA development team.

## License

This project is licensed under the GNU General Public License v3.0 – see the `LICENSE` file for details.

## Language Branches

- English – `main` branch
- Chinese – `zh-CN` branch
