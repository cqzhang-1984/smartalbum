#!/bin/bash
# SmartAlbum 裸机部署脚本（不使用 Docker）
# 适用于低内存服务器（1GB-2GB 内存）

set -euo pipefail

# =============================================================================
# 配置变量
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="/var/log/smartalbum/deploy"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/deploy-$TIMESTAMP.log"

# 部署配置
APP_USER=${APP_USER:-ubuntu}
APP_DIR=${APP_DIR:-/opt/smartalbum}
BACKEND_PORT=${BACKEND_PORT:-9999}
FRONTEND_PORT=${FRONTEND_PORT:-80}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] [INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARN]${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $1"; }
section() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

# =============================================================================
# 阶段 1: 系统准备
# =============================================================================
prepare_system() {
    section "阶段 1/8: 系统准备"
    
    log "更新系统包..."
    apt-get update && apt-get upgrade -y
    
    log "安装必要依赖..."
    apt-get install -y \
        python3 python3-pip python3-venv \
        nodejs npm \
        redis-server \
        nginx \
        git \
        curl \
        htop \
        sqlite3 \
        libglib2.0-0 libsm6 libxext6 libxrender-dev \
        build-essential cmake \
        || {
            error "依赖安装失败"
            exit 1
        }
    
    log "系统准备完成 ✓"
}

# =============================================================================
# 阶段 2: 创建应用目录
# =============================================================================
setup_directories() {
    section "阶段 2/8: 创建应用目录"
    
    log "创建应用目录: $APP_DIR"
    mkdir -p "$APP_DIR"/{backend,frontend,data,storage,logs}
    
    # 设置权限
    chown -R $APP_USER:$APP_USER "$APP_DIR"
    
    log "目录创建完成 ✓"
}

# =============================================================================
# 阶段 3: 部署后端
# =============================================================================
deploy_backend() {
    section "阶段 3/8: 部署后端"
    
    log "复制后端代码..."
    cp -r "$PROJECT_ROOT/backend"/* "$APP_DIR/backend/"
    
    cd "$APP_DIR/backend"
    
    log "创建 Python 虚拟环境..."
    python3 -m venv venv
    source venv/bin/activate
    
    log "升级 pip..."
    pip install --upgrade pip setuptools wheel
    
    log "安装 Python 依赖（低内存模式）..."
    # 使用国内镜像，减少内存使用
    pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple \
        --no-deps -r requirements.txt 2>/dev/null || {
        # 如果失败，逐个安装
        log "逐个安装依赖..."
        while read package; do
            [[ "$package" =~ ^#.*$ ]] && continue
            [[ -z "$package" ]] && continue
            log "  安装: $package"
            pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple "$package" || warn "安装失败: $package"
        done < requirements.txt
    }
    
    # 创建 systemd 服务
    log "创建后端服务..."
    cat > /etc/systemd/system/smartalbum-backend.service << EOF
[Unit]
Description=SmartAlbum Backend
After=network.target redis-server.service

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR/backend
Environment=PATH=$APP_DIR/backend/venv/bin
Environment=DATABASE_URL=sqlite+aiosqlite:///$APP_DIR/data/smartalbum.db
Environment=REDIS_URL=redis://localhost:6379/0
Environment=STORAGE_PATH=$APP_DIR/storage
Environment=DEBUG=false
Environment=PYTHONUNBUFFERED=1
ExecStart=$APP_DIR/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT --workers 1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable smartalbum-backend
    
    log "后端部署完成 ✓"
}

# =============================================================================
# 阶段 4: 部署前端
# =============================================================================
deploy_frontend() {
    section "阶段 4/8: 部署前端"
    
    log "复制前端代码..."
    cp -r "$PROJECT_ROOT/frontend"/* "$APP_DIR/frontend/"
    
    cd "$APP_DIR/frontend"
    
    log "配置 npm 国内镜像..."
    npm config set registry https://registry.npmmirror.com
    
    log "安装 Node 依赖..."
    # 限制内存使用
    export NODE_OPTIONS="--max-old-space-size=512"
    npm install --no-audit --no-fund || {
        warn "npm install 失败，尝试使用 yarn"
        npm install -g yarn
        yarn install
    }
    
    log "构建前端..."
    npm run build || yarn build
    
    # 配置 Nginx
    log "配置 Nginx..."
    cat > /etc/nginx/sites-available/smartalbum << EOF
server {
    listen $FRONTEND_PORT;
    server_name _;
    
    root $APP_DIR/frontend/dist;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api/ {
        proxy_pass http://localhost:$BACKEND_PORT/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        client_max_body_size 100M;
    }
    
    location /storage/ {
        alias $APP_DIR/storage/;
        expires 30d;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/smartalbum /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx
    systemctl enable nginx
    
    log "前端部署完成 ✓"
}

# =============================================================================
# 阶段 5: 配置 Redis
# =============================================================================
setup_redis() {
    section "阶段 5/8: 配置 Redis"
    
    log "配置 Redis（低内存模式）..."
    cat > /etc/redis/redis.conf.d/smartalbum.conf << EOF
# 低内存配置
maxmemory 64mb
maxmemory-policy allkeys-lru
appendonly yes
save ""
EOF
    
    systemctl restart redis-server
    systemctl enable redis-server
    
    log "Redis 配置完成 ✓"
}

# =============================================================================
# 安全配置生成
# =============================================================================
generate_secure_key() {
    openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p | head -c 64
}

# =============================================================================
# 阶段 6: 配置环境变量
# =============================================================================
setup_environment() {
    section "阶段 6/8: 配置环境变量"
    
    log "创建环境变量文件..."
    if [ ! -f "$APP_DIR/backend/.env" ]; then
        # 生成安全的随机密钥
        local generated_key
        generated_key=$(generate_secure_key)
        
        cat > "$APP_DIR/backend/.env" << EOF
# 基础配置
ENVIRONMENT=production
DEBUG=false

# 安全配置（已自动生成，建议修改）
SECRET_KEY=${generated_key}
DEFAULT_USERNAME=admin
DEFAULT_PASSWORD=

# CORS 配置
CORS_ORIGINS=http://localhost,http://127.0.0.1

# AI API 配置（请填写）
AI_API_KEY=

# 其他配置保持默认...
EOF
        warn "请编辑 $APP_DIR/backend/.env 文件，配置："
        warn "  1. DEFAULT_PASSWORD - 设置管理员密码（必填）"
        warn "  2. AI_API_KEY - 设置AI服务API密钥（必填）"
        warn "  3. SECRET_KEY - 建议修改为自定义密钥"
    else
        log "环境变量文件已存在，跳过创建"
    fi
    
    # 严格设置权限
    chown $APP_USER:$APP_USER "$APP_DIR/backend/.env"
    chmod 600 "$APP_DIR/backend/.env"
    
    # 验证权限
    local perms
    perms=$(stat -c "%a" "$APP_DIR/backend/.env" 2>/dev/null || stat -f "%Lp" "$APP_DIR/backend/.env")
    if [ "$perms" != "600" ]; then
        error ".env 文件权限设置失败，当前权限: $perms"
        exit 1
    fi
    
    log "环境变量配置完成 ✓"
}

# =============================================================================
# 阶段 7: 初始化数据库
# =============================================================================
init_database() {
    section "阶段 7/8: 初始化数据库"
    
    cd "$APP_DIR/backend"
    source venv/bin/activate
    
    log "初始化数据库..."
    python -c "
import asyncio
import sys
sys.path.insert(0, '.')
from app.database import init_db
asyncio.run(init_db())
print('数据库初始化完成')
"
    
    log "数据库初始化完成 ✓"
}

# =============================================================================
# 阶段 8: 启动服务
# =============================================================================
start_services() {
    section "阶段 8/8: 启动服务"
    
    log "启动 Redis..."
    systemctl start redis-server
    
    log "启动后端..."
    systemctl start smartalbum-backend
    
    log "重启 Nginx..."
    systemctl restart nginx
    
    log "等待服务启动..."
    sleep 5
    
    # 健康检查
    if curl -sf "http://localhost:$BACKEND_PORT/api/health" > /dev/null 2>&1; then
        log "✓ 后端服务启动成功"
    else
        warn "后端服务可能未完全启动，检查日志: journalctl -u smartalbum-backend -n 50"
    fi
    
    if curl -sf "http://localhost:$FRONTEND_PORT" > /dev/null 2>&1; then
        log "✓ 前端服务启动成功"
    else
        warn "前端服务可能未完全启动"
    fi
    
    log "服务启动完成 ✓"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    init_logging
    
    section "SmartAlbum 裸机部署"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "项目目录: $PROJECT_ROOT"
    log "应用目录: $APP_DIR"
    log "后端端口: $BACKEND_PORT"
    log "前端端口: $FRONTEND_PORT"
    log ""
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        error "请以 root 权限运行此脚本"
        exit 1
    fi
    
    # 执行部署流程
    prepare_system
    setup_directories
    deploy_backend
    deploy_frontend
    setup_redis
    setup_environment
    init_database
    start_services
    
    section "部署完成"
    log "=============================================="
    log "  裸机部署成功完成!"
    log "=============================================="
    log ""
    log "访问地址:"
    log "  - 前端: http://$(curl -s ifconfig.me || echo 'your-server-ip'):$FRONTEND_PORT"
    log "  - API: http://$(curl -s ifconfig.me || echo 'your-server-ip'):$BACKEND_PORT"
    log ""
    log "管理命令:"
    log "  - 查看后端日志: journalctl -u smartalbum-backend -f"
    log "  - 重启后端: systemctl restart smartalbum-backend"
    log "  - 重启 Nginx: systemctl restart nginx"
    log "  - 重启 Redis: systemctl restart redis-server"
    log ""
    log "日志文件: $LOG_FILE"
    log "=============================================="
}

# 运行主函数
main "$@"
