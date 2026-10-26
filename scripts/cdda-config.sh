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
    command -v jq   &>/dev/null || { log_error "需要 jq 命令"; exit 1; }

    API_URL="https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1"

    # 令牌可选：公开仓库可匿名访问，但有令牌限流宽松得多
    #   有令牌：5000 次/小时（按令牌计）
    #   无令牌：60 次/小时（按 IP 计），且共享 IP 易被连坐限流
    curl_args=(
        -sS
        -w "\n__CODE__%{http_code}"
        --connect-timeout 15
        --max-time 60
        -H "Accept: application/vnd.github+json"
    )
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
        log_info "使用 GITHUB_TOKEN 认证请求"
    else
        log_warn "未设置 GITHUB_TOKEN，将以匿名方式请求"
        log_warn "匿名限流仅 60 次/小时（按 IP），共享 IP 易被连坐限流"
        log_warn "建议 export GITHUB_TOKEN=ghp_xxx 以避免莫名 403"
    fi

    if response=$(curl "${curl_args[@]}" "$API_URL" 2>&1); then
        curl_rc=0
    else
        curl_rc=$?
    fi

    # ===== 网络层失败：curl 非 0 退出，此时不存在可信的 HTTP 响应 =====
    if [ "$curl_rc" -ne 0 ]; then
        case "$curl_rc" in
            6)  reason="DNS 解析失败（域名错误 / DNS 服务不可用）" ;;
            7)  reason="TCP 连接失败（端口错误 / 防火墙拦截 / 代理不通）" ;;
            28) reason="请求超时（--connect-timeout 或 --max-time 触发）" ;;
            5)  reason="无法解析代理主机" ;;
            35) reason="TLS/SSL 握手失败（证书问题）" ;;
            18) reason="传输中断，数据不完整" ;;
            *)  reason="其他网络错误" ;;
        esac
        log_error "网络层失败（curl 退出码 ${curl_rc}）：${reason}"
        log_error "curl 输出：${response}"
        exit 1
    fi

    # ===== HTTP 层：解析状态码与响应体 =====
    http_code=$(printf '%s\n' "$response" | sed -n 's/.*__CODE__\([0-9]\{3\}\)$/\1/p')
    body=$(printf '%s' "$response" | sed 's/__CODE__[0-9]\{3\}$//')

    case "$http_code" in
        200)
            latest_tag=$(printf '%s' "$body" | jq -r '.[0].tag_name // empty')
            if [ -z "$latest_tag" ]; then
                log_error "无法解析最新标签，API 响应：$body"
                exit 1
            fi
            TAG="$latest_tag"
            log_info "最新标签: $TAG"
            ;;
        401)
            log_error "GitHub 认证失败（HTTP 401）：令牌无效、过期或被撤销"
            log_error "响应：$body"
            exit 1
            ;;
        403)
            log_error "GitHub API 被拒绝（HTTP 403）：权限不足或触发限流"
            if [ -z "${GITHUB_TOKEN:-}" ]; then
                log_error "当前为匿名请求，极可能是 60 次/小时限流或共享 IP 连坐"
                log_error "建议：export GITHUB_TOKEN=ghp_xxx 后重试"
            else
                log_error "若为限流，请检查响应头 X-RateLimit-Remaining / Retry-After"
            fi
            log_error "响应：$body"
            exit 1
            ;;
        404)
            log_error "仓库或端点不存在（HTTP 404）：检查仓库名或令牌权限"
            log_error "响应：$body"
            exit 1
            ;;
        429)
            log_error "触发速率限制（HTTP 429）：请稍后重试"
            log_error "响应：$body"
            exit 1
            ;;
        000)
            # 防御性分支：curl 未拿到任何 HTTP 响应（正常应已被上面的 curl_rc 分支拦截）
            log_error "未收到 HTTP 响应（000）：网络层失败，无法从服务端获取更多信息"
            log_error "排查方向：网络连通性 / DNS 解析 / 代理配置 / 防火墙 / TLS 证书"
            [ -n "$body" ] && log_error "curl 输出：$body"
            exit 1
            ;;
        5??)
            log_error "GitHub 服务端错误（HTTP $http_code）：可稍后重试"
            log_error "响应：$body"
            exit 1
            ;;
        *)
            log_error "未知状态码（HTTP ${http_code:-空}）：既非预期 HTTP 码也非 000"
            [ -n "$body" ] && log_error "响应：$body"
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
