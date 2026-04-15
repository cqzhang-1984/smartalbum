#!/bin/bash
# SmartAlbum 部署脚本
# 用于在腾讯云 Lighthouse Ubuntu 24.04 上部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印信息
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

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        return 1
    fi
    return 0
}

# 安装 Docker
install_docker() {
    print_info "正在安装 Docker..."
    
    # 更新包索引
    sudo apt-get update
    
    # 安装必要的包
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # 添加 Docker 官方 GPG 密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 设置 Docker 仓库
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装 Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # 添加当前用户到 docker 组
    sudo usermod -aG docker $USER
    
    print_success "Docker 安装完成"
    print_warning "请注销并重新登录以应用 docker 组权限，或运行: newgrp docker"
}

# 安装 Docker Compose
install_docker_compose() {
    print_info "正在安装 Docker Compose..."
    
    # 下载 Docker Compose
    DOCKER_COMPOSE_VERSION="v2.24.0"
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # 添加执行权限
    sudo chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    print_success "Docker Compose 安装完成"
}

# 系统初始化
init_system() {
    print_info "初始化系统环境..."
    
    # 更新系统
    sudo apt-get update && sudo apt-get upgrade -y
    
    # 安装常用工具
    sudo apt-get install -y git curl wget vim htop unzip
    
    # 安装 Docker（如果不存在）
    if ! check_command docker; then
        install_docker
    else
        print_success "Docker 已安装: $(docker --version)"
    fi
    
    # 安装 Docker Compose（如果不存在）
    if ! check_command docker-compose; then
        install_docker_compose
    else
        print_success "Docker Compose 已安装: $(docker-compose --version)"
    fi
    
    print_success "系统初始化完成"
}

# 配置防火墙
setup_firewall() {
    print_info "配置防火墙..."
    
    # 检查 ufw 是否安装
    if check_command ufw; then
        # 允许 HTTP/HTTPS
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        
        # 可选：允许 SSH（如果尚未允许）
        sudo ufw allow 22/tcp
        
        # 启用防火墙（如果尚未启用）
        sudo ufw --force enable
        
        print_success "防火墙配置完成"
        sudo ufw status
    else
        print_warning "ufw 未安装，跳过防火墙配置"
    fi
}

# 创建目录结构
create_directories() {
    print_info "创建数据目录..."
    
    mkdir -p data storage/originals storage/thumbnails storage/ai_generated
    mkdir -p backend/logs
    
    print_success "目录创建完成"
}

# 构建和启动服务
deploy_services() {
    print_info "构建和启动服务..."
    
    # 使用 docker compose (v2) 或 docker-compose (v1)
    local DC
    if docker compose version &>/dev/null; then
        DC="docker compose -f docker-compose.prod.yml"
    else
        DC="docker-compose -f docker-compose.prod.yml"
    fi
    
    # 停止旧服务
    print_info "停止旧服务..."
    $DC down 2>/dev/null || true
    
    # 拉取最新镜像
    print_info "拉取基础镜像..."
    $DC pull
    
    # 构建镜像
    print_info "构建 Docker 镜像..."
    $DC build --no-cache
    
    # 启动服务
    print_info "启动服务..."
    $DC up -d
    
    print_success "服务启动完成"
}

# 检查服务状态
check_status() {
    print_info "检查服务状态..."
    
    sleep 5
    
    # 使用 docker compose (v2) 或 docker-compose (v1)
    local DC
    if docker compose version &>/dev/null; then
        DC="docker compose -f docker-compose.prod.yml"
    else
        DC="docker-compose -f docker-compose.prod.yml"
    fi
    
    # 检查容器状态
    $DC ps
    
    echo ""
    print_info "测试服务可用性..."
    
    # 测试后端
    if curl -s http://localhost/api/health > /dev/null; then
        print_success "后端服务正常"
    else
        print_error "后端服务异常"
    fi
    
    # 测试前端
    if curl -s http://localhost/ > /dev/null; then
        print_success "前端服务正常"
    else
        print_error "前端服务异常"
    fi
}

# 查看日志
show_logs() {
    print_info "查看服务日志（按 Ctrl+C 退出）..."
    if docker compose version &>/dev/null; then
        docker compose -f docker-compose.prod.yml logs -f
    else
        docker-compose -f docker-compose.prod.yml logs -f
    fi
}

# 备份数据
backup_data() {
    print_info "备份数据..."
    
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 备份数据库
    if [ -f "data/smartalbum.db" ]; then
        cp data/smartalbum.db "$BACKUP_DIR/"
        print_success "数据库已备份到 $BACKUP_DIR/smartalbum.db"
    fi
    
    # 备份向量数据
    if [ -f "data/vectors.json" ]; then
        cp data/vectors.json "$BACKUP_DIR/"
        print_success "向量数据已备份到 $BACKUP_DIR/vectors.json"
    fi
    
    print_success "备份完成: $BACKUP_DIR"
}

# 更新服务
update_services() {
    print_info "更新服务..."
    
    # 备份数据
    backup_data
    
    # 拉取代码更新
    print_info "拉取最新代码..."
    git pull origin main 2>/dev/null || print_warning "Git 拉取失败或不是 Git 仓库"
    
    # 重新部署
    deploy_services
    check_status
    
    print_success "更新完成"
}

# 显示使用帮助
show_help() {
    echo "SmartAlbum 部署脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  init      初始化系统环境（安装 Docker 等）"
    echo "  deploy    构建并部署服务（默认）"
    echo "  start     启动服务"
    echo "  stop      停止服务"
    echo "  restart   重启服务"
    echo "  update    更新服务（拉取代码并重新部署）"
    echo "  status    查看服务状态"
    echo "  logs      查看服务日志"
    echo "  backup    备份数据"
    echo "  clean     清理 Docker 资源"
    echo "  help      显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 init       # 首次部署前初始化系统"
    echo "  $0 deploy     # 部署服务"
    echo "  $0 update     # 更新到最新版本"
}

# 主函数
main() {
    cd "$(dirname "$0")"
    
    case "${1:-deploy}" in
        init)
            init_system
            setup_firewall
            create_directories
            ;;
        deploy)
            create_directories
            deploy_services
            check_status
            print_success "部署完成！"
            print_info "访问地址: http://$(curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"
            ;;
        start)
            docker-compose -f docker-compose.prod.yml up -d
            check_status
            ;;
        stop)
            docker-compose -f docker-compose.prod.yml down
            print_success "服务已停止"
            ;;
        restart)
            docker-compose -f docker-compose.prod.yml restart
            check_status
            ;;
        update)
            update_services
            ;;
        status)
            docker-compose -f docker-compose.prod.yml ps
            check_status
            ;;
        logs)
            show_logs
            ;;
        backup)
            backup_data
            ;;
        clean)
            print_warning "清理 Docker 资源..."
            docker system prune -f
            docker volume prune -f
            print_success "清理完成"
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
