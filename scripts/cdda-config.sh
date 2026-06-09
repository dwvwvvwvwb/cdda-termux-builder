#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

WORK_DIR="${WORK_DIR:-$HOME/Cataclysm-DDA}"

YES_MODE=false
TAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) YES_MODE=true; shift ;;
        *) [ -z "$TAG" ] && TAG="$1"; shift ;;
    esac
done

[ -z "$TAG" ] && TAG="latest"

if [ "$TAG" = "latest" ]; then
    log_step "获取最新发布标签..."
    command -v curl &>/dev/null || { log_error "需要 curl 命令"; exit 1; }
    command -v jq &>/dev/null || { log_error "需要 jq 命令"; exit 1; }

    # 用 if 包裹，防止 set -e 直接退出
    if ! response=$(curl -s -f -w "%{http_code}" --connect-timeout 15 --max-time 60 \
        "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1" 2>&1); then
        # curl 自身失败（如无法解析域名、连接超时），通常返回 000
        log_error "网络请求失败，请检查网络连接或代理设置"
        log_error "可能的原因：网络不通、DNS 解析失败、代理未配置"
        exit 1
    fi

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    case "$http_code" in
        200)
            # 正常处理
            latest_tag=$(echo "$body" | jq -r '.[0].tag_name')
            if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
                log_error "无法解析最新标签，API 响应格式可能异常"
                exit 1
            fi
            TAG="$latest_tag"
            log_info "最新标签: $TAG"
            ;;
        403)
            log_error "GitHub API 请求被拒绝（HTTP 403）"
            log_error "常见原因："
            log_error "  - 请求频率过高，触发了 GitHub 的限流机制"
            log_error "  - IP 地址被临时限制"
            log_error "解决方法：请等待几分钟后重试，或使用代理网络"
            exit 1
            ;;
        000)
            # 理论上 curl 失败时已处理，但此处以防万一
            log_error "网络连接失败（HTTP 000）"
            log_error "请检查网络连接、代理设置，或尝试手动访问 GitHub"
            exit 1
            ;;
        *)
            log_error "GitHub API 请求失败 (HTTP $http_code)"
            [ -n "$body" ] && log_error "响应内容: $body"
            exit 1
            ;;
    esac
fi

if [ ! -d "$WORK_DIR" ]; then
    log_info "浅克隆标签 $TAG ..."
    git clone --depth 1 --branch "$TAG" https://github.com/CleverRaven/Cataclysm-DDA.git "$WORK_DIR"
else
    log_info "更新到标签 $TAG ..."
    cd "$WORK_DIR"
    # 尝试浅拉取标签本身
    if git fetch origin "+refs/tags/$TAG:refs/tags/$TAG" --depth 1 ; then
        git checkout "tags/$TAG"
    # 若失败，尝试拉取标签指向的提交
    elif git fetch origin "+refs/tags/$TAG^{}:refs/tags/$TAG" --depth 1 ; then
        git checkout "tags/$TAG"
    else
        log_error "无法使用浅克隆获取标签 $TAG。"
        log_error "请删除目录 '$WORK_DIR' 后重新运行，或手动完整克隆。"
        exit 1
    fi
fi

cd "$WORK_DIR/android" || { log_error "android 目录不存在"; exit 1; }
log_step "写入 local.properties ..."
cat > local.properties <<EOF
j=$(nproc)
sdk.dir=$ANDROID_HOME
ndk.dir=$ANDROID_NDK_HOME
override_ndkVersion=$NDK_VERSION
override_compileSdkVersion=$(find_platform_version)
override_targetSdkVersion=$(find_platform_version)
EOF

log_info "项目配置完成！"
