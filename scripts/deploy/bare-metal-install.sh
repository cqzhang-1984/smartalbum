#!/bin/bash
# SmartAlbum 裸机一键安装脚本
# 用途: 首次部署到全新的 Ubuntu 服务器

set -euo pipefail

# 配置
APP_DIR="/opt/smartalbum"
APP_USER="ubuntu"
LOG_FILE="/var/log/smartalbum-install.log"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1" | tee -a $LOG_FILE; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $1" | tee -a $LOG_FILE; }
error() { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $1" | tee -a $LOG_FILE; }
section() {
    echo -e "\n${CYAN}========================================${NC}" | tee -a $LOG_FILE
    echo -e "${CYAN}  $1${NC}" | tee -a $LOG_FILE
    echo -e "${CYAN}========================================${NC}\n" | tee -a $LOG_FILE
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请以 root 权限运行: sudo $0"
        exit 1
    fi
}

# 检查系统要求
check_system() {
    section "检查系统要求"
    
    # 检查 Ubuntu 版本
    if ! grep -q "Ubuntu" /etc/os-release; then
        error "此脚本仅支持 Ubuntu 系统"
        exit 1
    fi
    
    UBUNTU_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    log "Ubuntu 版本: $UBUNTU_VERSION"
    
    # 检查内存
    MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    log "总内存: ${MEM_TOTAL}MB"
    
    if [ "$MEM_TOTAL" -lt 1024 ]; then
        warn "内存不足 1GB，建议使用至少 2GB 内存的服务器"
        read -p "是否继续? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # 检查磁盘
    DISK_AVAIL=$(df / | awk 'NR==2{print $4}')
    log "可用磁盘: $(($DISK_AVAIL/1024))MB"
    
    if [ "$DISK_AVAIL" -lt 5242880 ]; then  # 5GB
        error "磁盘空间不足 5GB"
        exit 1
    fi
    
    log "✓ 系统检查通过"
}

# 安装依赖
install_dependencies() {
    section "安装系统依赖"
    
    log "更新软件源..."
    apt-get update
    
    log "安装基础包..."
    apt-get install -y \
        software-properties-common \
        curl wget git \
        htop vim \
        sqlite3
    
    log "安装 Python 3.11..."
    add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
    apt-get update
    apt-get install -y python3.11 python3.11-venv python3.11-distutils python3-pip
    
    log "安装 Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    
    log "安装 Redis..."
    apt-get install -y redis-server
    
    log "安装 Nginx..."
    apt-get install -y nginx
    
    log "安装编译依赖..."
    apt-get install -y build-essential cmake \
        libglib2.0-0 libsm6 libxext6 libxrender-dev
    
    log "✓ 依赖安装完成"
}

# 创建目录结构
setup_directories() {
    section "创建应用目录"
    
    log "创建目录: $APP_DIR"
    mkdir -p $APP_DIR/{backend,frontend,data,storage,logs,backup,scripts}
    
    log "设置权限..."
    chown -R $APP_USER:$APP_USER $APP_DIR
    chmod 750 $APP_DIR
    chmod 700 $APP_DIR/data
    chmod 700 $APP_DIR/logs
    chmod 700 $APP_DIR/backup
    
    log "✓ 目录创建完成"
}

# 部署后端
deploy_backend() {
    section "部署后端"
    
    cd $APP_DIR
    
    # 检查代码是否存在
    if [ ! -d "backend/app" ]; then
        error "后端代码不存在！请先将代码上传到 $APP_DIR/backend/"
        error "你可以使用: scp -r backend/ ubuntu@服务器IP:$APP_DIR/"
        exit 1
    fi
    
    cd backend
    
    log "创建 Python 虚拟环境..."
    python3.11 -m venv venv
    source venv/bin/activate
    
    log "配置 pip 国内镜像..."
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
    pip install --upgrade pip setuptools wheel
    
    log "安装依赖（这可能需要几分钟）..."
    # 先安装关键依赖
    pip install --no-cache-dir fastapi uvicorn sqlalchemy aiosqlite
    pip install --no-cache-dir redis celery
    
    # 然后安装全部依赖
    if [ -f "requirements.txt" ]; then
        pip install --no-cache-dir -r requirements.txt || {
            warn "部分依赖安装失败，尝试跳过..."
        }
    fi
    
    log "创建 .env 配置文件..."
    if [ ! -f ".env" ]; then
        cat > .env << 'EOF'
ENVIRONMENT=production
DEBUG=false
SECRET_KEY=change-this-to-a-random-string-min-32-chars
DEFAULT_USERNAME=admin
DEFAULT_PASSWORD=admin123
CORS_ORIGINS=http://localhost,http://127.0.0.1
DATABASE_URL=sqlite+aiosqlite:///opt/smartalbum/data/smartalbum.db
REDIS_URL=redis://localhost:6379/0
STORAGE_PATH=/opt/smartalbum/storage
AI_API_KEY=your-api-key-here
EOF
        chown $APP_USER:$APP_USER .env
        chmod 600 .env
        warn "请编辑 $APP_DIR/backend/.env 文件，设置 SECRET_KEY 和 AI_API_KEY"
    fi
    
    log "✓ 后端部署完成"
}

# 部署前端
deploy_frontend() {
    section "部署前端"
    
    cd $APP_DIR
    
    if [ ! -d "frontend/src" ]; then
        error "前端代码不存在！"
        exit 1
    fi
    
    cd frontend
    
    log "配置 npm 镜像..."
    sudo -u $APP_USER npm config set registry https://registry.npmmirror.com
    
    log "安装依赖..."
    sudo -u $APP_USER bash -c 'export NODE_OPTIONS="--max-old-space-size=1024" && npm install --no-audit --no-fund'
    
    log "构建生产版本..."
    sudo -u $APP_USER npm run build
    
    if [ ! -d "dist" ]; then
        error "前端构建失败！"
        exit 1
    fi
    
    log "✓ 前端部署完成"
}

# 配置 Systemd
setup_systemd() {
    section "配置系统服务"
    
    log "创建后端服务..."
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
ExecStart=$APP_DIR/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 9999 --workers 1
Restart=always
RestartSec=5
MemoryLimit=512M

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable smartalbum-backend
    
    log "✓ 服务配置完成"
}

# 配置 Nginx
setup_nginx() {
    section "配置 Nginx"
    
    log "创建站点配置..."
    cat > /etc/nginx/sites-available/smartalbum << EOF
upstream backend {
    server 127.0.0.1:9999;
}

server {
    listen 80;
    server_name _;
    
    access_log /var/log/nginx/smartalbum-access.log;
    error_log /var/log/nginx/smartalbum-error.log;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    location /api/ {
        proxy_pass http://backend/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        client_max_body_size 100M;
    }
    
    location /storage/ {
        alias $APP_DIR/storage/;
        expires 30d;
    }
    
    location / {
        root $APP_DIR/frontend/dist;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/smartalbum /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx
    systemctl enable nginx
    
    log "✓ Nginx 配置完成"
}

# 配置 Redis
setup_redis() {
    section "配置 Redis"
    
    log "配置低内存模式..."
    
    # 创建配置目录（如果不存在）
    mkdir -p /etc/redis/redis.conf.d
    
    cat > /etc/redis/redis.conf.d/smartalbum.conf << EOF
maxmemory 64mb
maxmemory-policy allkeys-lru
save ""
appendonly yes
bind 127.0.0.1
EOF
    
    # 确保主配置包含该目录
    if ! grep -q "include /etc/redis/redis.conf.d/*.conf" /etc/redis/redis.conf 2>/dev/null; then
        echo "include /etc/redis/redis.conf.d/*.conf" >> /etc/redis/redis.conf
    fi
    
    systemctl restart redis-server
    systemctl enable redis-server
    
    log "✓ Redis 配置完成"
}

# 初始化数据库
init_database() {
    section "初始化数据库"
    
    cd $APP_DIR/backend
    source venv/bin/activate
    
    log "初始化数据库..."
    python -c "
import asyncio
import sys
sys.path.insert(0, '.')
from app.database import init_db
asyncio.run(init_db())
" || {
        error "数据库初始化失败"
        exit 1
    }
    
    chown $APP_USER:$APP_USER $APP_DIR/data/smartalbum.db
    
    log "✓ 数据库初始化完成"
}

# 启动服务
start_services() {
    section "启动服务"
    
    log "启动 Redis..."
    systemctl start redis-server
    
    log "启动后端..."
    systemctl start smartalbum-backend
    
    log "等待服务启动（10秒）..."
    sleep 10
    
    log "检查服务状态..."
    if systemctl is-active --quiet smartalbum-backend; then
        log "✓ 后端服务运行中"
    else
        error "后端服务启动失败，检查日志: journalctl -u smartalbum-backend -n 50"
        exit 1
    fi
    
    # 健康检查
    if curl -sf http://localhost:9999/api/health > /dev/null; then
        log "✓ 健康检查通过"
    else
        warn "健康检查未通过，服务可能还在启动中"
    fi
    
    log "✓ 服务启动完成"
}

# 完成信息
show_completion() {
    section "安装完成"
    
    IP=$(curl -s ifconfig.me 2>/dev/null || echo "你的服务器IP")
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  SmartAlbum 安装成功！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "访问地址:"
    echo "  http://$IP"
    echo ""
    echo "管理命令:"
    echo "  查看状态: sudo systemctl status smartalbum-backend"
    echo "  查看日志: sudo journalctl -u smartalbum-backend -f"
    echo "  重启服务: sudo systemctl restart smartalbum-backend"
    echo "  重启 Nginx: sudo systemctl restart nginx"
    echo ""
    echo "配置文件:"
    echo "  后端环境变量: $APP_DIR/backend/.env"
    echo "  Nginx 配置: /etc/nginx/sites-available/smartalbum"
    echo ""
    echo "重要提醒:"
    echo "  ⚠ 请编辑 $APP_DIR/backend/.env 修改默认密码和 API 密钥！"
    echo ""
    echo "日志文件: $LOG_FILE"
    echo -e "${GREEN}========================================${NC}"
}

# 主函数
main() {
    mkdir -p /var/log/smartalbum
    touch $LOG_FILE
    
    section "SmartAlbum 裸机安装"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "安装目录: $APP_DIR"
    log ""
    
    check_root
    check_system
    install_dependencies
    setup_directories
    deploy_backend
    deploy_frontend
    setup_systemd
    setup_nginx
    setup_redis
    init_database
    start_services
    show_completion
}

# 运行
main "$@"
