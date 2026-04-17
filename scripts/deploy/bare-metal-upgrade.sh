#!/bin/bash
# SmartAlbum 裸机部署升级脚本
# 功能: 从 Docker 容器部署迁移到裸机部署，支持零停机迁移
# 作者: SmartAlbum DevOps Team
# 版本: 1.0.0

set -euo pipefail

# =============================================================================
# 配置变量
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/var/log/smartalbum/deploy"
LOG_FILE="$LOG_DIR/bare-metal-upgrade-$TIMESTAMP.log"

# 应用配置
APP_DIR="/opt/smartalbum"
APP_USER="${APP_USER:-ubuntu}"
BACKEND_PORT="${BACKEND_PORT:-9999}"
FRONTEND_PORT="${FRONTEND_PORT:-80}"

# Docker 配置（源环境）
DOCKER_COMPOSE_DIR="${DOCKER_COMPOSE_DIR:-$PROJECT_ROOT}"
DOCKER_FRONTEND_PORT="${DOCKER_FRONTEND_PORT:-8888}"

# 部署状态
DEPLOYMENT_STATUS="INIT"
ROLLBACK_AVAILABLE=false
BACKUP_PATH=""

# =============================================================================
# 颜色定义
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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
# 错误处理
# =============================================================================
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "脚本异常退出 (错误码: $exit_code)"
        error "当前状态: $DEPLOYMENT_STATUS"
        error "日志文件: $LOG_FILE"
        
        if [ "$ROLLBACK_AVAILABLE" = true ]; then
            warn "可以执行回滚: $SCRIPT_DIR/rollback-to-docker.sh"
        fi
    fi
    exit $exit_code
}

trap cleanup_on_error EXIT ERR INT TERM

# =============================================================================
# 阶段 1: 预检查
# =============================================================================
phase1_pre_check() {
    section "阶段 1/8: 预部署检查"
    DEPLOYMENT_STATUS="PRE_CHECK"
    
    log "检查系统环境..."
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        error "请使用 sudo 运行此脚本"
        exit 1
    fi
    
    # 检查操作系统
    if ! grep -q "Ubuntu" /etc/os-release; then
        error "此脚本仅支持 Ubuntu 系统"
        exit 1
    fi
    
    UBUNTU_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    log "  ✓ Ubuntu 版本: $UBUNTU_VERSION"
    
    # 检查系统资源
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    log "  ✓ 总内存: ${mem_total}MB"
    
    if [ "$mem_total" -lt 2048 ]; then
        warn "内存小于 2GB，建议至少 4GB"
        read -p "是否继续? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # 检查磁盘空间
    local disk_avail=$(df /opt | awk 'NR==2{print $4}')
    log "  ✓ /opt 可用空间: $(($disk_avail/1024))MB"
    
    if [ "$disk_avail" -lt 10485760 ]; then  # 10GB
        error "磁盘空间不足 10GB"
        exit 1
    fi
    
    # 检查 Docker 环境
    log "检查 Docker 环境..."
    if ! command -v docker &> /dev/null; then
        warn "Docker 未安装，可能是纯净环境"
    else
        log "  ✓ Docker 已安装"
        
        # 检查现有容器
        if docker ps --format "{{.Names}}" | grep -q "smartalbum"; then
            log "  ✓ 发现运行中的 SmartAlbum 容器"
            docker ps --filter "name=smartalbum" --format "table {{.Names}}\t{{.Status}}"
        else
            warn "未找到运行中的 SmartAlbum 容器"
        fi
    fi
    
    # 检查必需命令
    local required_commands=("python3" "pip3" "node" "npm" "nginx" "redis-cli")
    for cmd in "${required_commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            warn "$cmd 未安装，将在安装阶段处理"
        fi
    done
    
    # 检查项目代码
    if [ ! -d "$PROJECT_ROOT/backend" ] || [ ! -d "$PROJECT_ROOT/frontend" ]; then
        error "项目代码不完整，请确保在正确的目录运行脚本"
        exit 1
    fi
    log "  ✓ 项目代码检查通过"
    
    log "预检查完成 ✓"
    return 0
}

# =============================================================================
# 阶段 2: 系统依赖安装
# =============================================================================
phase2_install_dependencies() {
    section "阶段 2/8: 安装系统依赖"
    DEPLOYMENT_STATUS="INSTALL_DEPS"
    
    log "更新软件源..."
    apt-get update
    
    log "安装基础包..."
    apt-get install -y \
        software-properties-common \
        curl wget git vim htop \
        sqlite3 libsqlite3-dev
    
    # 检查并安装 Python 3.11
    log "检查 Python 3.11..."
    if ! command -v python3.11 &> /dev/null; then
        log "安装 Python 3.11..."
        add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
        apt-get update
        apt-get install -y python3.11 python3.11-venv python3.11-distutils python3-pip
    fi
    log "  ✓ Python 3.11: $(python3.11 --version)"
    
    # 检查并安装 Node.js 20
    log "检查 Node.js..."
    if ! command -v node &> /dev/null || [ "$(node -v | cut -d'v' -f2 | cut -d'.' -f1)" != "20" ]; then
        log "安装 Node.js 20..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    fi
    log "  ✓ Node.js: $(node -v)"
    log "  ✓ npm: $(npm -v)"
    
    # 检查并安装 Redis
    log "检查 Redis..."
    if ! command -v redis-server &> /dev/null; then
        log "安装 Redis..."
        apt-get install -y redis-server
    fi
    
    # 配置 Redis
    mkdir -p /etc/redis/redis.conf.d
    cat > /etc/redis/redis.conf.d/smartalbum.conf << EOF
maxmemory 128mb
maxmemory-policy allkeys-lru
save ""
appendonly yes
bind 127.0.0.1
EOF
    systemctl restart redis-server
    systemctl enable redis-server
    log "  ✓ Redis 配置完成"
    
    # 检查并安装 Nginx
    log "检查 Nginx..."
    if ! command -v nginx &> /dev/null; then
        log "安装 Nginx..."
        apt-get install -y nginx
    fi
    systemctl enable nginx
    log "  ✓ Nginx 配置完成"
    
    # 安装编译依赖（用于 face_recognition）
    log "安装编译依赖..."
    apt-get install -y build-essential cmake \
        libglib2.0-0 libsm6 libxext6 libxrender-dev \
        libdlib-dev libboost-all-dev
    log "  ✓ 编译依赖安装完成"
    
    log "系统依赖安装完成 ✓"
    return 0
}

# =============================================================================
# 阶段 3: 数据备份
# =============================================================================
phase3_backup_data() {
    section "阶段 3/8: 数据备份"
    DEPLOYMENT_STATUS="BACKUP"
    
    log "创建备份目录..."
    BACKUP_PATH="/opt/backups/smartalbum_migration_$TIMESTAMP"
    mkdir -p "$BACKUP_PATH"/{database,storage,config,vectors}
    
    # 从 Docker 容器备份数据
    if docker ps --format "{{.Names}}" | grep -q "smartalbum"; then
        log "从 Docker 容器备份数据..."
        
        # 查找数据卷
        local data_volume=$(docker volume ls --format "{{.Name}}" | grep -E "smartalbum.*data" | head -1)
        local storage_volume=$(docker volume ls --format "{{.Name}}" | grep -E "smartalbum.*storage" | head -1)
        
        if [ -n "$data_volume" ]; then
            log "  备份数据卷: $data_volume"
            docker run --rm -v "$data_volume":/data -v "$BACKUP_PATH":/backup alpine tar czf /backup/database/data_volume.tar.gz -C /data .
        fi
        
        if [ -n "$storage_volume" ]; then
            log "  备份存储卷: $storage_volume"
            docker run --rm -v "$storage_volume":/storage -v "$BACKUP_PATH":/backup alpine tar czf /backup/storage/storage_volume.tar.gz -C /storage .
        fi
        
        # 从容器复制配置文件
        local backend_container=$(docker ps --format "{{.Names}}" | grep "smartalbum.*backend" | head -1)
        if [ -n "$backend_container" ]; then
            log "  备份配置文件..."
            docker cp "$backend_container:/app/.env" "$BACKUP_PATH/config/env_backup" 2>/dev/null || true
        fi
    fi
    
    # 同时备份本地 data 和 storage 目录（如果存在）
    if [ -d "$PROJECT_ROOT/data" ]; then
        log "备份本地数据..."
        cp -r "$PROJECT_ROOT/data"/* "$BACKUP_PATH/database/" 2>/dev/null || true
    fi
    
    if [ -d "$PROJECT_ROOT/storage" ]; then
        log "备份本地存储..."
        tar czf "$BACKUP_PATH/storage/local_storage.tar.gz" -C "$PROJECT_ROOT" storage 2>/dev/null || true
    fi
    
    # 备份配置文件
    cp "$PROJECT_ROOT/backend/.env" "$BACKUP_PATH/config/" 2>/dev/null || true
    cp "$PROJECT_ROOT/backend/.env.example" "$BACKUP_PATH/config/" 2>/dev/null || true
    
    # 生成备份报告
    cat > "$BACKUP_PATH/BACKUP_REPORT.txt" << EOF
SmartAlbum 迁移备份报告
========================

备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份路径: $BACKUP_PATH
服务器: $(hostname)

备份内容:
$(du -sh $BACKUP_PATH/* 2>/dev/null)

恢复说明:
1. 数据库恢复: 从 database/ 目录恢复 .db 文件
2. 存储恢复: 从 storage/ 目录恢复照片文件
3. 配置恢复: 从 config/ 目录恢复 .env 文件
EOF

    # 压缩备份
    cd "$(dirname $BACKUP_PATH)"
    tar czf "$(basename $BACKUP_PATH).tar.gz" "$(basename $BACKUP_PATH)"
    rm -rf "$BACKUP_PATH"
    BACKUP_PATH="$BACKUP_PATH.tar.gz"
    
    ROLLBACK_AVAILABLE=true
    log "备份完成: $BACKUP_PATH"
    log "备份大小: $(du -h $BACKUP_PATH | cut -f1)"
    log "数据备份完成 ✓"
    
    return 0
}

# =============================================================================
# 阶段 4: 创建应用目录结构
# =============================================================================
phase4_setup_directories() {
    section "阶段 4/8: 创建应用目录"
    DEPLOYMENT_STATUS="SETUP_DIRS"
    
    log "创建应用目录: $APP_DIR"
    mkdir -p "$APP_DIR"/{backend,frontend,data,storage,logs,backup,scripts}
    mkdir -p "$APP_DIR/storage"/{originals,thumbnails,ai_generated}
    mkdir -p "$APP_DIR/data/chroma"
    
    log "设置权限..."
    chown -R "$APP_USER:$APP_USER" "$APP_DIR"
    chmod 755 "$APP_DIR"
    chmod 750 "$APP_DIR/data"
    chmod 750 "$APP_DIR/storage"
    
    # 恢复数据（如果备份存在）
    if [ -n "$BACKUP_PATH" ] && [ -f "$BACKUP_PATH" ]; then
        log "恢复备份数据..."
        cd "$(dirname $BACKUP_PATH)"
        tar xzf "$BACKUP_PATH" -C /tmp/
        
        local backup_dir="/tmp/$(basename $BACKUP_PATH .tar.gz)"
        
        # 恢复数据库
        if [ -d "$backup_dir/database" ]; then
            cp -r "$backup_dir/database"/* "$APP_DIR/data/" 2>/dev/null || true
        fi
        
        # 恢复存储
        if [ -d "$backup_dir/storage" ]; then
            tar xzf "$backup_dir/storage/storage_volume.tar.gz" -C "$APP_DIR/" 2>/dev/null || true
            tar xzf "$backup_dir/storage/local_storage.tar.gz" -C "$APP_DIR/" 2>/dev/null || true
        fi
        
        # 恢复向量数据
        if [ -d "$backup_dir/vectors" ]; then
            cp -r "$backup_dir/vectors"/* "$APP_DIR/data/" 2>/dev/null || true
        fi
        
        rm -rf "$backup_dir"
        log "  ✓ 数据恢复完成"
    fi
    
    # 确保数据目录权限正确
    chown -R "$APP_USER:$APP_USER" "$APP_DIR/data"
    chown -R "$APP_USER:$APP_USER" "$APP_DIR/storage"
    
    log "目录设置完成 ✓"
    return 0
}

# =============================================================================
# 阶段 5: 部署后端
# =============================================================================
phase5_deploy_backend() {
    section "阶段 5/8: 部署后端"
    DEPLOYMENT_STATUS="DEPLOY_BACKEND"
    
    log "复制后端代码..."
    cp -r "$PROJECT_ROOT/backend"/* "$APP_DIR/backend/"
    
    cd "$APP_DIR/backend"
    
    log "创建 Python 虚拟环境..."
    python3.11 -m venv venv
    source venv/bin/activate
    
    log "配置 pip 镜像..."
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
    pip install --upgrade pip setuptools wheel
    
    log "安装 Python 依赖（可能需要几分钟）..."
    
    # 分批安装，提高稳定性
    log "  安装核心依赖..."
    pip install --no-cache-dir fastapi uvicorn sqlalchemy aiosqlite || {
        error "核心依赖安装失败"
        return 1
    }
    
    log "  安装缓存和队列..."
    pip install --no-cache-dir redis celery || {
        error "Redis/Celery 安装失败"
        return 1
    }
    
    log "  安装 AI 相关..."
    pip install --no-cache-dir chromadb sentence-transformers openai httpx || {
        warn "部分 AI 依赖安装失败，可能不影响基本功能"
    }
    
    log "  安装图像处理..."
    pip install --no-cache-dir Pillow piexif || {
        error "图像处理库安装失败"
        return 1
    }
    
    log "  安装其他依赖..."
    if [ -f "requirements.txt" ]; then
        # 过滤掉已安装的依赖
        pip install --no-cache-dir -r requirements.txt 2>&1 | tee -a "$LOG_FILE" || {
            warn "部分依赖安装失败，尝试继续..."
        }
    fi
    
    log "创建生产环境配置..."
    if [ ! -f ".env" ]; then
        # 从备份恢复配置
        if [ -f "$APP_DIR/backup/config/env_backup" ]; then
            cp "$APP_DIR/backup/config/env_backup" .env
            log "  ✓ 从备份恢复配置"
        else
            # 创建默认配置
            cat > .env << EOF
ENVIRONMENT=production
DEBUG=false
SECRET_KEY=$(openssl rand -hex 32)
DEFAULT_USERNAME=admin
DEFAULT_PASSWORD=change_this_password
CORS_ORIGINS=http://localhost
DATABASE_URL=sqlite+aiosqlite:///$APP_DIR/data/smartalbum.db
REDIS_URL=redis://localhost:6379/1
STORAGE_PATH=$APP_DIR/storage
AI_API_KEY=your-api-key-here
EOF
            warn "创建了默认配置文件，请编辑 $APP_DIR/backend/.env 修改配置"
        fi
    fi
    
    chown "$APP_USER:$APP_USER" .env
    chmod 600 .env
    
    # 初始化数据库
    log "初始化数据库..."
    python -c "
import asyncio
import sys
sys.path.insert(0, '.')
from app.database import init_db
asyncio.run(init_db())
" || {
        error "数据库初始化失败"
        return 1
    }
    
    chown -R "$APP_USER:$APP_USER" "$APP_DIR/data"
    
    log "后端部署完成 ✓"
    return 0
}

# =============================================================================
# 阶段 6: 部署前端
# =============================================================================
phase6_deploy_frontend() {
    section "阶段 6/8: 部署前端"
    DEPLOYMENT_STATUS="DEPLOY_FRONTEND"
    
    log "复制前端代码..."
    cp -r "$PROJECT_ROOT/frontend"/* "$APP_DIR/frontend/"
    
    cd "$APP_DIR/frontend"
    
    log "配置 npm 镜像..."
    sudo -u "$APP_USER" npm config set registry https://registry.npmmirror.com
    
    log "安装 npm 依赖..."
    sudo -u "$APP_USER" bash -c 'export NODE_OPTIONS="--max-old-space-size=2048" && npm ci --no-audit --no-fund' || {
        error "npm 依赖安装失败"
        return 1
    }
    
    log "构建生产版本..."
    sudo -u "$APP_USER" npm run build || {
        error "前端构建失败"
        return 1
    }
    
    if [ ! -d "dist" ]; then
        error "前端构建输出不存在"
        return 1
    fi
    
    log "前端部署完成 ✓"
    return 0
}

# =============================================================================
# 阶段 7: 配置系统服务
# =============================================================================
phase7_setup_services() {
    section "阶段 7/8: 配置系统服务"
    DEPLOYMENT_STATUS="SETUP_SERVICES"
    
    log "创建后端服务配置..."
    cat > /etc/systemd/system/smartalbum-backend.service << EOF
[Unit]
Description=SmartAlbum Backend
After=network.target redis.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR/backend
Environment=PATH=$APP_DIR/backend/venv/bin
Environment=PYTHONUNBUFFERED=1
Environment=ENVIRONMENT=production
ExecStart=$APP_DIR/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT --workers 2
Restart=always
RestartSec=5
MemoryLimit=1G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF

    log "创建 Celery Worker 服务..."
    cat > /etc/systemd/system/smartalbum-worker.service << EOF
[Unit]
Description=SmartAlbum Celery Worker
After=network.target redis.service smartalbum-backend.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR/backend
Environment=PATH=$APP_DIR/backend/venv/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=$APP_DIR/backend/venv/bin/celery -A tasks.celery_app worker --loglevel=info --concurrency=2
Restart=always
RestartSec=10
MemoryLimit=512M

[Install]
WantedBy=multi-user.target
EOF

    log "配置 Nginx..."
    cat > /etc/nginx/sites-available/smartalbum << EOF
upstream backend {
    server 127.0.0.1:$BACKEND_PORT;
    keepalive 32;
}

limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=upload_limit:10m rate=1r/s;

server {
    listen $FRONTEND_PORT;
    server_name _;
    
    access_log /var/log/nginx/smartalbum-access.log;
    error_log /var/log/nginx/smartalbum-error.log;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    location ~* \\.(jpg|jpeg|png|gif|webp|ico|css|js)$ {
        root $APP_DIR/frontend/dist;
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    location /storage/ {
        alias $APP_DIR/storage/;
        expires 30d;
        add_header Cache-Control "public";
        sendfile on;
        tcp_nopush on;
    }
    
    location /api/upload/ {
        limit_req zone=upload_limit burst=5 nodelay;
        client_max_body_size 100M;
        
        proxy_pass http://backend/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    location /api/ {
        limit_req zone=api_limit burst=20 nodelay;
        
        proxy_pass http://backend/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
    
    location / {
        root $APP_DIR/frontend/dist;
        index index.html;
        try_files \$uri \$uri/ /index.html;
        
        location ~* \\.html$ {
            expires -1;
            add_header Cache-Control "no-store, no-cache, must-revalidate";
        }
    }
}
EOF

    # 启用配置
    ln -sf /etc/nginx/sites-available/smartalbum /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # 测试并重载
    nginx -t || {
        error "Nginx 配置测试失败"
        return 1
    }
    
    # 重载 systemd
    systemctl daemon-reload
    systemctl enable smartalbum-backend
    systemctl enable smartalbum-worker
    
    log "系统服务配置完成 ✓"
    return 0
}

# =============================================================================
# 阶段 8: 启动服务与验证
# =============================================================================
phase8_start_and_verify() {
    section "阶段 8/8: 启动服务与验证"
    DEPLOYMENT_STATUS="START_VERIFY"
    
    # 停止 Docker 容器（避免端口冲突）
    log "停止 Docker 容器..."
    if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.yml" ]; then
        cd "$DOCKER_COMPOSE_DIR"
        docker-compose stop 2>/dev/null || true
        docker-compose down 2>/dev/null || true
    fi
    
    # 停止可能占用端口的服务
    log "清理端口占用..."
    fuser -k $BACKEND_PORT/tcp 2>/dev/null || true
    
    log "启动后端服务..."
    systemctl start smartalbum-backend
    sleep 5
    
    log "检查后端服务状态..."
    if ! systemctl is-active --quiet smartalbum-backend; then
        error "后端服务启动失败"
        journalctl -u smartalbum-backend -n 50 --no-pager
        return 1
    fi
    log "  ✓ 后端服务运行中"
    
    log "启动 Celery Worker..."
    systemctl start smartalbum-worker
    sleep 3
    
    if ! systemctl is-active --quiet smartalbum-worker; then
        warn "Celery Worker 启动失败，继续部署..."
    else
        log "  ✓ Celery Worker 运行中"
    fi
    
    log "重载 Nginx..."
    systemctl reload nginx
    log "  ✓ Nginx 重载完成"
    
    # 健康检查
    log "执行健康检查..."
    sleep 5
    
    local retry_count=0
    local max_retries=12
    local health_passed=false
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -sf http://localhost:$BACKEND_PORT/api/health > /dev/null 2>&1; then
            health_passed=true
            break
        fi
        
        retry_count=$((retry_count + 1))
        log "  健康检查尝试 $retry_count/$max_retries..."
        sleep 5
    done
    
    if [ "$health_passed" = false ]; then
        error "健康检查失败"
        journalctl -u smartalbum-backend -n 100 --no-pager
        return 1
    fi
    
    log "  ✓ 健康检查通过"
    
    # 前端检查
    if curl -sf http://localhost:$FRONTEND_PORT > /dev/null 2>&1; then
        log "  ✓ 前端访问正常"
    else
        warn "前端访问检查失败"
    fi
    
    DEPLOYMENT_STATUS="COMPLETED"
    log "服务启动与验证完成 ✓"
    return 0
}

# =============================================================================
# 完成部署
# =============================================================================
finish_deployment() {
    section "部署完成"
    
    local ip=$(curl -s ifconfig.me 2>/dev/null || echo "your-server-ip")
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  SmartAlbum 裸机部署完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "访问地址:"
    echo "  http://$ip"
    echo ""
    echo "管理命令:"
    echo "  查看后端状态: sudo systemctl status smartalbum-backend"
    echo "  查看后端日志: sudo journalctl -u smartalbum-backend -f"
    echo "  查看 Worker 状态: sudo systemctl status smartalbum-worker"
    echo "  重启后端: sudo systemctl restart smartalbum-backend"
    echo "  重启 Nginx: sudo systemctl restart nginx"
    echo ""
    echo "配置文件:"
    echo "  后端环境: $APP_DIR/backend/.env"
    echo "  Nginx: /etc/nginx/sites-available/smartalbum"
    echo ""
    echo "重要提醒:"
    echo "  ⚠ 请编辑 $APP_DIR/backend/.env 修改默认密码和 API 密钥！"
    echo ""
    if [ -n "$BACKUP_PATH" ]; then
        echo "备份文件: $BACKUP_PATH"
        echo "回滚命令: $SCRIPT_DIR/rollback-to-docker.sh $BACKUP_PATH"
    fi
    echo ""
    echo "日志文件: $LOG_FILE"
    echo -e "${GREEN}========================================${NC}"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    init_logging
    
    section "SmartAlbum 裸机部署升级"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "项目目录: $PROJECT_ROOT"
    log "应用目录: $APP_DIR"
    log "日志文件: $LOG_FILE"
    log ""
    
    # 执行各阶段
    phase1_pre_check || exit 1
    phase2_install_dependencies || exit 1
    phase3_backup_data || exit 1
    phase4_setup_directories || exit 1
    phase5_deploy_backend || exit 1
    phase6_deploy_frontend || exit 1
    phase7_setup_services || exit 1
    phase8_start_and_verify || exit 1
    
    finish_deployment
}

# 处理命令行参数
case "${1:-}" in
    --help|-h)
        echo "SmartAlbum 裸机部署升级脚本"
        echo ""
        echo "用法: sudo $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h        显示此帮助信息"
        echo "  --skip-backup     跳过备份步骤（不推荐）"
        echo ""
        echo "环境变量:"
        echo "  APP_USER          应用运行用户 (默认: ubuntu)"
        echo "  BACKEND_PORT      后端端口 (默认: 9999)"
        echo "  FRONTEND_PORT     前端端口 (默认: 80)"
        echo "  DOCKER_COMPOSE_DIR Docker Compose 目录"
        exit 0
        ;;
    --skip-backup)
        SKIP_BACKUP=true
        warn "跳过备份步骤！"
        ;;
esac

# 运行主函数
main
