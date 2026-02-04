#!/bin/bash
set -euo pipefail

# ===================== 配置区 =====================
HARBOR_DOMAIN="harbor.geekops.local"
HARBOR_PROJECT="rancher"
HARBOR_USER="admin"
HARBOR_PASS="admin123"
HARBOR_CERT_PATH="/etc/pki/ca-trust/source/anchors/harbor.crt"

# RKE2 镜像清单文件（来自 Rancher Release）
IMAGE_LIST_FILE="./rke2-images-all.linux-amd64.txt"

IMAGES=()

# ===================== 输出样式 =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_separator() {
    echo -e "${BLUE}╭─────────────────────────────────────────────────╮${NC}"
}

print_separator_end() {
    echo -e "${BLUE}╰─────────────────────────────────────────────────╯${NC}"
}

print_info() {
    echo -e "${BLUE}[$(date '+%F %T')] [INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[$(date '+%F %T')] [SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date '+%F %T')] [ERROR]${NC} $1"
}

# ===================== 读取镜像清单 =====================
load_images() {
    print_separator
    print_info "加载 RKE2 镜像清单：${PURPLE}${IMAGE_LIST_FILE}${NC}"

    if [ ! -f "${IMAGE_LIST_FILE}" ]; then
        print_error "镜像清单文件不存在：${IMAGE_LIST_FILE}"
        print_separator_end
        exit 1
    fi

    mapfile -t IMAGES < <(
        sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${IMAGE_LIST_FILE}"
    )

    if [ "${#IMAGES[@]}" -eq 0 ]; then
        print_error "镜像清单为空，终止执行"
        print_separator_end
        exit 1
    fi

    print_success "成功加载 ${#IMAGES[@]} 个镜像"
    print_separator_end
}

# ===================== 证书处理 =====================
import_harbor_cert() {
    print_separator
    print_info "开始处理 Harbor 自签名证书..."

    if [ "$(id -u)" -ne 0 ]; then
        print_error "请使用 root 用户执行（需要写入 CA 信任目录）"
        print_separator_end
        exit 1
    fi

    if [ ! -f "${HARBOR_CERT_PATH}" ]; then
        print_info "自动获取 Harbor 证书..."
        openssl s_client \
            -showcerts \
            -connect "${HARBOR_DOMAIN}:443" \
            -servername "${HARBOR_DOMAIN}" \
            </dev/null 2>/dev/null \
            | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' \
            > "${HARBOR_CERT_PATH}"

        if [ ! -s "${HARBOR_CERT_PATH}" ]; then
            print_error "获取 Harbor 证书失败"
            print_separator_end
            exit 1
        fi

        print_success "证书已保存到 ${HARBOR_CERT_PATH}"
    else
        print_info "已存在 Harbor 证书，跳过获取"
    fi

    print_info "更新系统 CA 信任库..."
    update-ca-trust extract
    print_success "Harbor 证书已加入系统信任"
    print_separator_end
}

# ===================== Harbor 登录 =====================
login_harbor() {
    print_separator
    print_info "登录 Harbor：${PURPLE}${HARBOR_DOMAIN}${NC}"

    skopeo login "${HARBOR_DOMAIN}" \
        -u "${HARBOR_USER}" \
        -p "${HARBOR_PASS}" \
        --tls-verify=false

    print_success "Harbor 登录成功"
    print_separator_end
}

# ===================== 镜像同步 =====================
sync_image() {
    local src_image="$1"
    local image_path="${src_image#docker.io/}"
    local dest_image="${HARBOR_DOMAIN}/${image_path}"

    print_separator
    print_info "源镜像: ${PURPLE}${src_image}${NC}"
    print_info "目标镜像: ${PURPLE}${dest_image}${NC}"

    if skopeo copy \
        --preserve-digests \
        --insecure-policy \
        --src-tls-verify=false \
        --dest-tls-verify=false \
        "docker://${src_image}" \
        "docker://${dest_image}"
    then
        print_success "✅ 同步完成"
        print_separator_end
        return 0
    else
        print_error "❌ 同步失败"
        print_separator_end
        return 1
    fi
}

# ===================== 主流程 =====================
main() {
    if ! command -v skopeo >/dev/null 2>&1; then
        print_error "未安装 skopeo，请执行：dnf install -y skopeo"
        exit 1
    fi

    load_images
    import_harbor_cert
    login_harbor

    print_separator
    print_info "开始同步 ${#IMAGES[@]} 个 RKE2 镜像"
    print_separator_end

    success_count=0
    fail_count=0
    FAILED_IMAGES=()

    for image in "${IMAGES[@]}"; do
        if sync_image "${image}"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
            FAILED_IMAGES+=("${image}")
        fi
    done

    print_separator
    print_info "同步完成：成功 ${success_count} 个 | 失败 ${fail_count} 个"
    if [ "${fail_count}" -ne 0 ]; then
        print_error "失败镜像列表："
        for img in "${FAILED_IMAGES[@]}"; do
            echo " - ${img}"
        done
    else
        print_success "🎉 所有镜像同步成功"
    fi
    print_separator_end
}

main
