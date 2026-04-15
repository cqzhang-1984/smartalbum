#!/bin/bash
# SmartAlbum 手动部署脚本（不使用 docker-compose）
# 用于在腾讯云 Lighthouse Ubuntu 24.04 上部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 配置
PROJECT_NAME="smartalbum"
NETWORK_NAME="smartalbum-network"

# 创建网络
create_network() {
    print_info "创建 Docker 网络..."
    docker network create $NETWORK_NAME 2>/dev/null || true
    print_success "网络创建完成"
}

# 创建目录
create_directories() {
    print_info "创建数据目录..."
    mkdir -p data storage/originals storage/thumbnails storage/ai_generated
    mkdir -p backend/logs
    print_success "目录创建完成"
}

# 部署 Redis
deploy_redis() {
    print_info "部署 Redis..."
    
    docker run -d \
        --name ${PROJECT_NAME}-redis \
        --network $NETWORK_NAME \
        --restart always \
        -v redis_data:/data \
        redis:7-alpine
    
    print_success "Redis 部署完成"
}

# 构建后端镜像
build_backend() {
    print_info "构建后端镜像..."
    docker build -t ${PROJECT_NAME}-backend:latest ./backend
    print_success "后端镜像构建完成"
}

# 部署后端
deploy_backend() {
    print_info "部署后端服务..."
    
    docker run -d \
        --name ${PROJECT_NAME}-backend \
        --network $NETWORK_NAME \
        --restart always \
        -p 9000:9000 \
        -e DATABASE_URL=sqlite+aiosqlite:///./data/smartalbum.db \
        -e REDIS_URL=redis://${PROJECT_NAME}-redis:6379/0 \
        -e STORAGE_PATH=/app/storage \
        -e DEBUG=false \
        -e CORS_ORIGINS="*" \
        --env-file .env \
        -v $(pwd)/data:/app/data \
        -v $(pwd)/storage:/app/storage \
        -v $(pwd)/backend/logs:/app/logs \
        ${PROJECT_NAME}-backend:latest
    
    print_success "后端服务部署完成"
}

# 构建前端镜像
build_frontend() {
    print_info "构建前端镜像..."
    docker build -t ${PROJECT_NAME}-frontend:latest ./frontend
    print_success "前端镜像构建完成"
}

# 部署前端
deploy_frontend() {
    print_info "部署前端服务..."
    
    docker run -d \
        --name ${PROJECT_NAME}-frontend \
        --network $NETWORK_NAME \
        --restart always \
        -p 80:80 \
        ${PROJECT_NAME}-frontend:latest
    
    print_success "前端服务部署完成"
}

# 停止服务
stop_services() {
    print_info "停止服务..."
    docker rm -f ${PROJECT_NAME}-frontend ${PROJECT_NAME}-backend ${PROJECT_NAME}-redis 2>/dev/null || true
    print_success "服务已停止"
}

# 检查状态
check_status() {
    print_info "检查服务状态..."
    docker ps --filter "name=${PROJECT_NAME}"
    
    echo ""
    print_info "测试服务..."
    
    # 测试后端
    if curl -s http://localhost:9000/api/health > /dev/null 2>&1; then
        print_success "后端服务正常 (http://localhost:9000)"
    else
        print_error "后端服务异常"
    fi
    
    # 测试前端
    if curl -s http://localhost/ > /dev/null 2>&1; then
        print_success "前端服务正常 (http://localhost)"
    else
        print_error "前端服务异常"
    fi
}

# 查看日志
show_logs() {
    print_info "查看日志 (Ctrl+C 退出)..."
    docker logs -f ${PROJECT_NAME}-backend
}

# 主部署流程
deploy_all() {
    print_info "开始部署 SmartAlbum..."
    
    stop_services
    create_directories
    create_network
    
    # 先部署 Redis
    deploy_redis
    sleep 3
    
    # 构建并部署后端
    build_backend
    deploy_backend
    sleep 5
    
    # 构建并部署前端
    build_frontend
    deploy_frontend
    sleep 3
    
    check_status
    
    echo ""
    print_success "部署完成！"
    print_info "访问地址: http://$(curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"
}

# 帮助
show_help() {
    echo "SmartAlbum 手动部署脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  deploy    完整部署（默认）"
    echo "  stop      停止所有服务"
    echo "  restart   重启服务"
    echo "  status    查看状态"
    echo "  logs      查看后端日志"
    echo "  help      显示帮助"
}

# 主函数
main() {
    cd "$(dirname "$0")"
    
    case "${1:-deploy}" in
        deploy)
            deploy_all
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            deploy_all
            ;;
        status)
            check_status
            ;;
        logs)
            show_logs
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
