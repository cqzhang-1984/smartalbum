#!/bin/bash
# SmartAlbum 低内存服务器部署脚本
# 适用于内存不足 4GB 的轻量服务器

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取 docker compose 命令
get_docker_compose() {
    if docker compose version &>/dev/null; then
        echo "docker compose -f docker-compose.prod.yml"
    else
        echo "docker-compose -f docker-compose.prod.yml"
    fi
}

# 检查内存
check_memory() {
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local avail_mem=$(free -m | awk '/^Mem:/{print $7}')
    print_info "系统总内存: ${total_mem}MB, 可用内存: ${avail_mem}MB"
    
    if [ "$total_mem" -lt 4096 ]; then
        print_warning "检测到内存小于 4GB，建议增加 Swap 空间"
        return 1
    fi
    return 0
}

# 设置 Swap
setup_swap() {
    print_info "检查 Swap 配置..."
    
    # 检查是否已有 swap
    if swapon --show | grep -q "swapfile"; then
        print_success "Swap 已存在"
        swapon --show
        return 0
    fi
    
    # 获取内存大小
    local mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    local swap_size=2048
    
    # 根据内存大小设置 swap
    if [ "$mem_mb" -lt 2048 ]; then
        swap_size=4096  # 内存小于 2G，swap 设为 4G
    elif [ "$mem_mb" -lt 4096 ]; then
        swap_size=2048  # 内存小于 4G，swap 设为 2G
    else
        swap_size=1024  # 内存大于 4G，swap 设为 1G
    fi
    
    print_info "创建 ${swap_size}MB 的 Swap 文件..."
    
    # 创建 swap 文件
    sudo fallocate -l ${swap_size}M /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=${swap_size}
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    
    # 永久生效
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    
    # 优化 swappiness
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
    sudo sysctl vm.swappiness=10
    
    print_success "Swap 配置完成"
    free -h
}

# 清理内存
free_memory() {
    print_info "清理系统缓存..."
    
    # 清理 Docker 缓存
    docker system prune -f 2>/dev/null || true
    
    # 清理系统缓存（需要 root）
    if [ -f /proc/sys/vm/drop_caches ]; then
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    fi
    
    sleep 2
    
    local avail_mem=$(free -m | awk '/^Mem:/{print $7}')
    print_success "清理完成，当前可用内存: ${avail_mem}MB"
}

# 停止所有容器释放资源
stop_services() {
    print_info "停止现有容器释放资源..."
    local DC=$(get_docker_compose)
    $DC down --remove-orphans 2>/dev/null || true
    
    # 清理所有停止的容器
    docker container prune -f 2>/dev/null || true
}

# 分步构建 - 先构建基础镜像
build_backend() {
    print_info "=========================================="
    print_info "开始构建后端镜像（内存消耗较大，请耐心等待）"
    print_info "=========================================="
    
    # 单独构建后端，使用内存限制
    # --memory 限制容器内存，防止 OOM
    # --build-arg 传递构建参数
    # --progress plain 减少内存占用
    
    local DC=$(get_docker_compose)
    
    # 先构建不使用缓存，减少内存使用
    COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 $DC build \
        --no-cache \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        backend 2>&1
    
    print_success "后端镜像构建完成"
    
    # 构建后清理
    free_memory
}

# 分步构建前端
build_frontend() {
    print_info "=========================================="
    print_info "开始构建前端镜像"
    print_info "=========================================="
    
    local DC=$(get_docker_compose)
    
    COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 $DC build \
        --no-cache \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        frontend 2>&1
    
    print_success "前端镜像构建完成"
    
    # 构建后清理
    free_memory
}

# 拉取基础镜像
pull_base_images() {
    print_info "拉取基础镜像..."
    
    # 拉取轻量级镜像
    docker pull python:3.11-slim || print_warning "Python 镜像拉取失败，将使用本地缓存"
    docker pull node:20-alpine || print_warning "Node 镜像拉取失败，将使用本地缓存"
    docker pull nginx:alpine || print_warning "Nginx 镜像拉取失败，将使用本地缓存"
    docker pull redis:7-alpine || print_warning "Redis 镜像拉取失败，将使用本地缓存"
    
    print_success "基础镜像拉取完成"
}

# 启动服务
start_services() {
    print_info "启动服务..."
    
    local DC=$(get_docker_compose)
    
    # 仅启动，不构建
    $DC up -d --no-build
    
    print_success "服务启动完成"
}

# 检查服务状态
check_status() {
    print_info "等待服务启动..."
    sleep 10
    
    local DC=$(get_docker_compose)
    $DC ps
    
    echo ""
    print_info "测试服务..."
    
    # 测试后端
    if curl -s http://localhost:9000/api/health > /dev/null 2>&1; then
        print_success "后端服务正常"
    else
        print_warning "后端服务可能未就绪，稍后再试"
    fi
    
    # 测试前端
    if curl -s http://localhost > /dev/null 2>&1; then
        print_success "前端服务正常"
    else
        print_warning "前端服务可能未就绪"
    fi
}

# 完整部署流程
deploy() {
    print_info "=========================================="
    print_info "SmartAlbum 低内存部署模式"
    print_info "=========================================="
    
    # 1. 检查并设置 swap
    setup_swap
    
    # 2. 检查内存
    check_memory || true
    
    # 3. 创建目录
    mkdir -p data storage/originals storage/thumbnails storage/ai_generated backend/logs
    
    # 4. 释放内存
    free_memory
    
    # 5. 停止旧服务
    stop_services
    
    # 6. 拉取基础镜像
    pull_base_images
    
    # 7. 分步构建 - 先构建后端
    build_backend
    
    # 8. 分步构建 - 再构建前端
    build_frontend
    
    # 9. 启动服务
    start_services
    
    # 10. 检查状态
    check_status
    
    echo ""
    print_success "部署完成！"
    print_info "访问地址: http://$(curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"
}

# 快速启动（不重新构建）
start() {
    print_info "启动服务..."
    local DC=$(get_docker_compose)
    $DC up -d
    check_status
}

# 停止服务
stop() {
    print_info "停止服务..."
    local DC=$(get_docker_compose)
    $DC down
    print_success "服务已停止"
}

# 查看日志
logs() {
    local DC=$(get_docker_compose)
    $DC logs -f --tail=100
}

# 显示帮助
show_help() {
    echo "SmartAlbum 低内存部署脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  deploy    完整部署（自动配置 swap、分步构建）"
    echo "  start     启动现有容器（不重新构建）"
    echo "  stop      停止服务"
    echo "  swap      仅配置 swap"
    echo "  clean     清理缓存释放内存"
    echo "  logs      查看日志"
    echo "  help      显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 deploy   # 首次部署或完整重新部署"
    echo "  $0 start    # 仅启动已有容器"
}

# 主函数
main() {
    cd "$(dirname "$0")"
    
    case "${1:-deploy}" in
        deploy)
            deploy
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        swap)
            setup_swap
            ;;
        clean)
            free_memory
            ;;
        logs)
            logs
            ;;
        help)
            show_help
            ;;
        *)
            print_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
