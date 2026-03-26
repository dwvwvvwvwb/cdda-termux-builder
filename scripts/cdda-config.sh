#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

WORK_DIR="${WORK_DIR:-$HOME/Cataclysm-DDA}"

YES_MODE=false
TAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y)
            YES_MODE=true
            shift
            ;;
        *)
            if [ -z "$TAG" ]; then
                TAG="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$TAG" ]; then
    TAG="latest"
fi

if [ "$TAG" = "latest" ]; then
    log_step "获取最新发布标签..."
    if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
        log_error "需要 curl 和 jq 来获取最新标签，请先运行安装脚本"
        exit 1
    fi
    response=$(curl -s -w "%{http_code}" "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    if [ "$http_code" -ne 200 ]; then
        log_error "GitHub API 请求失败 (HTTP $http_code)"
        exit 1
    fi
    latest_tag=$(echo "$body" | jq -r '.[0].tag_name')
    if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
        log_error "无法解析最新标签"
        exit 1
    fi
    TAG="$latest_tag"
    log_info "最新标签: $TAG"
fi

if [ ! -d "$WORK_DIR" ]; then
    log_info "克隆 CDDA 源码（浅克隆）..."
    git clone --depth 1 https://github.com/CleverRaven/Cataclysm-DDA.git "$WORK_DIR"
fi

if [ -n "$TAG" ]; then
    log_info "切换到标签 $TAG ..."
    cd "$WORK_DIR"
    if ! git diff-index --quiet HEAD --; then
        log_warn "检测到本地未提交修改"
        if [ "$YES_MODE" = false ]; then
            read -p "是否强制切换标签（会丢失未提交修改）？(y/N) " answer
            if [[ ! "$answer" =~ ^[Yy]$ ]]; then
                log_info "取消切换"
                exit 0
            fi
        else
            log_info "自动模式，将强制切换"
        fi
        git checkout --force "tags/$TAG"
    else
        git checkout "tags/$TAG"
    fi
fi

cd "$WORK_DIR/android" || { log_error "android 目录不存在，请检查源码是否完整"; exit 1; }

log_step "配置 local.properties ..."
cat > local.properties <<EOF
sdk.dir=$ANDROID_HOME
ndk.dir=$ANDROID_NDK_HOME
override_ndkVersion=$NDK_VERSION
override_compileSdkVersion=$(find_platform_version)
override_targetSdkVersion=$(find_platform_version)
EOF

log_info "项目配置完成！"