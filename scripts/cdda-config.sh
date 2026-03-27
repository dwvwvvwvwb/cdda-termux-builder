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
    # 增加超时和错误检测
    response=$(curl -s -f -w "%{http_code}" --connect-timeout 10 --max-time 30 \
        "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1" 2>&1)
    curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        log_error "网络请求失败，请检查网络连接"
        exit 1
    fi
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    if [ "$http_code" -ne 200 ]; then
        log_error "GitHub API 请求失败 (HTTP $http_code)"
        log_info "你也可以手动指定标签：./cdda.sh config <标签名>"
        exit 1
    fi
    latest_tag=$(echo "$body" | jq -r '.[0].tag_name')
    if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
        log_error "无法解析最新标签，请检查网络或稍后重试"
        exit 1
    fi
    TAG="$latest_tag"
    log_info "最新标签: $TAG"
fi

# 克隆或更新代码
if [ ! -d "$WORK_DIR" ]; then
    log_info "浅克隆 CDDA 源码（仅最新提交）..."
    git clone --depth 1 https://github.com/CleverRaven/Cataclysm-DDA.git "$WORK_DIR"
fi

# 切换标签
if [ -n "$TAG" ]; then
    log_info "切换到标签 $TAG ..."
    cd "$WORK_DIR"
    # 检查本地是否有该标签
    if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
        log_info "本地未找到标签，尝试拉取..."
        if git fetch origin "tags/$TAG" --depth 1 2>/dev/null; then
            log_info "标签拉取成功"
            # 尝试使用 FETCH_HEAD 检出
            if git checkout FETCH_HEAD 2>/dev/null; then
                log_info "已通过 FETCH_HEAD 检出"
            else
                log_error "检出标签 $TAG 失败，请检查标签是否存在"
                exit 1
            fi
        else
            log_error "浅克隆无法获取标签 $TAG。"
            log_error "这可能是因为该标签不在最新的提交历史中。"
            log_error "请删除目录 '$WORK_DIR' 后重新运行，或手动完整克隆："
            log_error "  rm -rf '$WORK_DIR'"
            log_error "  git clone https://github.com/CleverRaven/Cataclysm-DDA.git '$WORK_DIR'"
            log_error "  cd '$WORK_DIR' && git fetch --tags && git checkout tags/$TAG"
            exit 1
        fi
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