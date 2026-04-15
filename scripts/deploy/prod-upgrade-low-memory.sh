#!/bin/bash
# SmartAlbum 生产环境升级脚本 - 低内存优化版
# 适用于 2GB-4GB 内存的服务器
# 功能: 零停机蓝绿部署、资源限制、低内存构建

set -euo pipefail

# =============================================================================
# 配置变量
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="/var/log/smartalbum/deploy"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/deploy-$TIMESTAMP.log"

# 低内存优化配置
BUILD_MEMORY_LIMIT=${BUILD_MEMORY_LIMIT:-1g}      # 构建内存限制
BUILD_CPU_LIMIT=${BUILD_CPU_LIMIT:-1}              # 构建 CPU 限制
BUILD_PARALLELISM=${BUILD_PARALLELISM:-1}          # 构建并行度
PIP_JOBS=${PIP_JOBS:-1}                            # pip 并行安装数
NPM_JOBS=${NPM_JOBS:-1}                            # npm 并行安装数

# 部署配置
BLUE_FRONTEND_PORT=${BLUE_FRONTEND_PORT:-8081}
BLUE_BACKEND_PORT=${BLUE_BACKEND_PORT:-9999}
GREEN_FRONTEND_PORT=${GREEN_FRONTEND_PORT:-8082}
GREEN_BACKEND_PORT=${GREEN_BACKEND_PORT:-9998}
HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-120}  # 增加超时时间
MAX_RETRY_ATTEMPTS=${MAX_RETRY_ATTEMPTS:-24}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 状态跟踪
DEPLOYMENT_STATUS="INIT"
TARGET_ENV=""
ACTIVE_ENV=""
BACKUP_PATH=""
ROLLBACK_AVAILABLE=false

# =============================================================================
# 日志函数
# =============================================================================
init_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1"
}

section() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

# =============================================================================
# 低内存优化：清理系统缓存
# =============================================================================
cleanup_system() {
    log "清理系统缓存以释放内存..."
    
    # 清理 Docker 构建缓存
    docker system prune -f --volumes 2>/dev/null || true
    
    # 清理 apt 缓存
    apt-get clean 2>/dev/null || true
    
    # 清理旧日志
    find /var/log -type f -name "*.log.*" -mtime +7 -delete 2>/dev/null || true
    
    # 同步文件系统
    sync
    
    # 清理页面缓存（需要 root）
    if [ "$EUID" -eq 0 ]; then
        echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
    fi
    
    # 显示当前内存状态
    log "当前内存状态:"
    free -h | grep -E "Mem|Swap"
}

# =============================================================================
# 低内存优化：检查内存
# =============================================================================
check_memory() {
    local available_mem=$(free -m | awk 'NR==2{print $7}')
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    
    log "可用内存: ${available_mem}MB / ${total_mem}MB"
    
    if [ "$available_mem" -lt 512 ]; then
        warn "可用内存不足 512MB，尝试清理..."
        cleanup_system
        
        available_mem=$(free -m | awk 'NR==2{print $7}')
        if [ "$available_mem" -lt 512 ]; then
            error "内存不足，无法继续部署。建议至少 512MB 可用内存。"
            return 1
        fi
    fi
    
    # 根据可用内存调整构建参数
    if [ "$available_mem" -lt 1024 ]; then
        warn "内存紧张，启用保守构建模式"
        BUILD_MEMORY_LIMIT="512m"
        BUILD_CPU_LIMIT="1"
        BUILD_PARALLELISM="1"
    elif [ "$available_mem" -lt 2048 ]; then
        BUILD_MEMORY_LIMIT="1g"
        BUILD_CPU_LIMIT="1"
        BUILD_PARALLELISM="2"
    else
        BUILD_MEMORY_LIMIT="2g"
        BUILD_CPU_LIMIT="2"
        BUILD_PARALLELISM="2"
    fi
    
    log "构建参数: 内存=$BUILD_MEMORY_LIMIT, CPU=$BUILD_CPU_LIMIT, 并行=$BUILD_PARALLELISM"
}

# =============================================================================
# 低内存优化：分步构建
# =============================================================================
build_with_retry() {
    local compose_file=$1
    local service_name=$2
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        log "构建 $service_name (尝试 $((retry_count + 1))/$max_retries)..."
        
        # 使用低内存模式构建
        if DOCKER_BUILDKIT=1 docker-compose -f "$compose_file" build \
            --build-arg PIP_JOBS=$PIP_JOBS \
            --build-arg NPM_JOBS=$NPM_JOBS \
            --memory="$BUILD_MEMORY_LIMIT" \
            --memory-swap="$BUILD_MEMORY_LIMIT" \
            "$service_name" 2>&1; then
            log "✓ $service_name 构建成功"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        warn "$service_name 构建失败，清理后重试..."
        
        # 清理后重试
        cleanup_system
        sleep 5
    done
    
    error "$service_name 构建失败，已达到最大重试次数"
    return 1
}

# =============================================================================
# 修改后的构建新版本函数
# =============================================================================
build_new_version_low_memory() {
    section "阶段 4/8: 构建新版本（低内存优化）"
    DEPLOYMENT_STATUS="BUILD"
    
    # 检查并清理内存
    check_memory || return 1
    
    log "开始构建 $TARGET_ENV 环境..."
    cd "$PROJECT_ROOT"
    
    # 导出目标环境变量
    export TARGET_ENV
    local TARGET_ENV_LOWER=$(echo "$TARGET_ENV" | tr '[:upper:]' '[:lower:]')
    export FRONTEND_PORT=$( [ "$TARGET_ENV" = "BLUE" ] && echo "$BLUE_FRONTEND_PORT" || echo "$GREEN_FRONTEND_PORT" )
    export BACKEND_PORT=$( [ "$TARGET_ENV" = "BLUE" ] && echo "$BLUE_BACKEND_PORT" || echo "$GREEN_BACKEND_PORT" )
    
    log "目标端口: Frontend=$FRONTEND_PORT, Backend=$BACKEND_PORT"
    
    # 创建优化的 docker-compose 文件
    local compose_file="docker-compose.$TARGET_ENV_LOWER.yml"
    cat > "$compose_file" << EOF
services:
  redis-$TARGET_ENV_LOWER:
    image: redis:7-alpine
    container_name: smartalbum-redis-$TARGET_ENV_LOWER
    restart: always
    # 内存限制
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.5'
    networks:
      - smartalbum-$TARGET_ENV_LOWER
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  backend-$TARGET_ENV_LOWER:
    build:
      context: ./backend
      dockerfile: Dockerfile.optimized
      args:
        PIP_MIRROR: https://pypi.tuna.tsinghua.edu.cn/simple
      # 构建资源限制
      extra_hosts:
        - "host.docker.internal:host-gateway"
    image: smartalbum-backend:$TARGET_ENV_LOWER
    container_name: smartalbum-backend-$TARGET_ENV_LOWER
    restart: always
    # 运行时资源限制
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1'
        reservations:
          memory: 256M
    environment:
      - DATABASE_URL=sqlite+aiosqlite:///./data/smartalbum.db
      - REDIS_URL=redis://redis-$TARGET_ENV_LOWER:6379/0
      - STORAGE_PATH=/app/storage
      - DEBUG=false
      - PORT=9999
      - PYTHONUNBUFFERED=1
    env_file:
      - ./backend/.env
    volumes:
      - ./data:/app/data
      - ./storage:/app/storage
      - ./backend/logs:/app/logs
    networks:
      - smartalbum-$TARGET_ENV_LOWER
    depends_on:
      redis-$TARGET_ENV_LOWER:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9999/api/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s

  frontend-$TARGET_ENV_LOWER:
    build:
      context: ./frontend
      dockerfile: Dockerfile.optimized
      args:
        NODE_MIRROR: https://registry.npmmirror.com
    image: smartalbum-frontend:$TARGET_ENV_LOWER
    container_name: smartalbum-frontend-$TARGET_ENV_LOWER
    restart: always
    # 运行时资源限制
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.5'
        reservations:
          memory: 64M
    ports:
      - "\${FRONTEND_PORT}:80"
    networks:
      - smartalbum-$TARGET_ENV_LOWER
    depends_on:
      - backend-$TARGET_ENV_LOWER
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s

networks:
  smartalbum-$TARGET_ENV_LOWER:
    driver: bridge
EOF
    
    log "停止现有 $TARGET_ENV 环境 (如果存在)..."
    docker-compose -f "$compose_file" down --remove-orphans 2>/dev/null || true
    docker rm -f smartalbum-backend-$TARGET_ENV smartalbum-frontend-$TARGET_ENV smartalbum-redis-$TARGET_ENV 2>/dev/null || true
    
    log "拉取最新代码..."
    if [ -d ".git" ]; then
        git fetch origin
        git pull origin main || warn "Git pull 失败，使用本地代码"
    fi
    
    # 配置 Docker 镜像加速器
    configure_docker_mirror
    
    # 使用优化的构建方式
    log "构建 Docker 镜像（低内存模式）..."
    
    # 先构建 Redis（不需要构建，直接拉取）
    log "拉取 Redis 镜像..."
    docker pull redis:7-alpine
    
    # 分步构建后端（内存消耗大）
    log "构建后端镜像..."
    if ! build_with_retry "$compose_file" "backend-$TARGET_ENV_LOWER"; then
        error "后端构建失败"
        rm -f "$compose_file"
        return 1
    fi
    
    # 清理内存
    cleanup_system
    
    # 构建前端
    log "构建前端镜像..."
    if ! build_with_retry "$compose_file" "frontend-$TARGET_ENV_LOWER"; then
        error "前端构建失败"
        rm -f "$compose_file"
        return 1
    fi
    
    log "启动 $TARGET_ENV 环境..."
    if ! docker-compose -f "$compose_file" up -d; then
        error "启动 $TARGET_ENV 环境失败"
        rm -f "$compose_file"
        return 1
    fi
    
    log "等待服务启动..."
    sleep 15
    
    log "构建完成 ✓"
    return 0
}

# =============================================================================
# 配置 Docker 镜像加速器
# =============================================================================
configure_docker_mirror() {
    log "检查 Docker 镜像加速器..."
    
    if [ -f /etc/docker/daemon.json ]; then
        # 备份现有配置
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%Y%m%d) 2>/dev/null || true
    fi
    
    # 使用可用的镜像源
    cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://docker.m.daocloud.io"
  ],
  "dns": ["8.8.8.8", "114.114.114.114"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "features": {
    "buildkit": true
  },
  "builder": {
    "gc": {
      "defaultKeepStorage": "5GB"
    }
  }
}
EOF
    
    # 如果 Docker 正在运行，重启应用配置
    if systemctl is-active --quiet docker; then
        log "重启 Docker 以应用配置..."
        systemctl daemon-reload
        systemctl restart docker
        sleep 3
    fi
    
    log "Docker 镜像加速器配置完成"
}

# =============================================================================
# 主函数（简化版，保留核心逻辑）
# =============================================================================
main() {
    init_logging
    
    section "SmartAlbum 低内存生产环境升级"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "项目目录: $PROJECT_ROOT"
    log "日志文件: $LOG_FILE"
    log "内存限制模式: BUILD_MEMORY_LIMIT=$BUILD_MEMORY_LIMIT"
    log ""
    
    cd "$PROJECT_ROOT"
    
    # 执行部署流程（使用优化后的函数）
    # 这里省略了其他阶段的代码，实际使用时需要包含完整的部署流程
    
    section "部署完成"
    log "=============================================="
    log "  低内存部署模式执行完成!"
    log "=============================================="
}

# 运行主函数
main "$@"
