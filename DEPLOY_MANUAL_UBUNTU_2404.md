# SmartAlbum 腾讯云服务器部署手册

> **服务器信息**  
> IP: `49.235.173.214`  
> 系统: Ubuntu 24.04 LTS  
> 配置: 4核 CPU / 4G 内存 / 40G 硬盘  
> 用户: `ubuntu` / 密码: `zhang11#`  
> 部署方式: 裸机部署（无 Docker）

---

## 目录

1. [连接服务器](#一连接服务器)
2. [环境准备](#二环境准备)
3. [项目部署](#三项目部署)
4. [服务配置](#四服务配置)
5. [启动验证](#五启动验证)
6. [日常运维](#六日常运维)
7. [故障排查](#七故障排查)

---

## 一、连接服务器

### 1.1 SSH 登录

```bash
# Windows PowerShell 或 CMD
ssh ubuntu@49.235.173.214

# 输入密码: zhang11#
```

### 1.2 首次登录配置

```bash
# 修改 root 密码（可选，建议设置）
sudo passwd root

# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装基础工具
sudo apt install -y curl wget vim git htop net-tools

# 设置时区
sudo timedatectl set-timezone Asia/Shanghai
```

---

## 二、环境准备

### 2.1 安装 Python 3.11

```bash
# 添加 Python 3.11 PPA
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update

# 安装 Python 3.11 及依赖
sudo apt install -y python3.11 python3.11-venv python3.11-dev python3-pip

# 设置 Python 3.11 为默认版本（可选）
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# 验证安装
python3 --version  # 应显示 Python 3.11.x
```

### 2.2 安装 Node.js 20

```bash
# 使用 NodeSource 安装 Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 验证安装
node --version   # 应显示 v20.x.x
npm --version    # 应显示 10.x.x

# 配置国内镜像（加速下载）
npm config set registry https://registry.npmmirror.com
```

### 2.3 安装 Redis

```bash
sudo apt install -y redis-server

# 配置 Redis（低内存优化）
sudo tee /etc/redis/redis.conf.d/smartalbum.conf << 'EOF'
# 内存限制（4G内存，分配128MB给Redis）
maxmemory 128mb
maxmemory-policy allkeys-lru

# 持久化配置
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec

# 安全配置 - 只允许本地访问
bind 127.0.0.1
protected-mode yes
port 6379
EOF

# 重启 Redis
sudo systemctl restart redis-server
sudo systemctl enable redis-server

# 验证 Redis
redis-cli ping  # 应返回 PONG
```

### 2.4 安装 Nginx

```bash
sudo apt install -y nginx

# 移除默认配置
sudo rm -f /etc/nginx/sites-enabled/default

# 验证 Nginx
sudo nginx -t
sudo systemctl enable nginx
```

### 2.5 安装其他依赖

```bash
# 安装图片处理库
sudo apt install -y libjpeg-dev libpng-dev libwebp-dev

# 安装人脸识别依赖（可选）
sudo apt install -y cmake libopenblas-dev liblapack-dev

# 创建应用目录
sudo mkdir -p /opt/smartalbum/{backend,frontend,data,storage,logs,backup,scripts}
sudo chown -R ubuntu:ubuntu /opt/smartalbum
```

---

## 三、项目部署

### 3.1 上传项目代码

**方式一：使用 SCP（从本地上传）**

```bash
# 在本地 PowerShell 执行，将项目压缩后上传
# 1. 先在本地压缩项目
# Compress-Archive -Path "C:\Users\zhang\SmartAlbum\*" -DestinationPath "C:\Users\zhang\smartalbum.zip"

# 2. 上传到服务器
scp C:\Users\zhang\smartalbum.zip ubuntu@49.235.173.214:/tmp/

# 3. SSH 登录后解压
ssh ubuntu@49.235.173.214
unzip /tmp/smartalbum.zip -d /tmp/smartalbum/
```

**方式二：使用 Git 克隆（如果代码在 GitHub）**

```bash
cd /tmp
git clone https://github.com/your-repo/smartalbum.git
```

**方式三：使用 rsync（推荐，增量同步）**

```bash
# 在本地执行
rsync -avz --exclude='venv' --exclude='node_modules' \
  /c/Users/zhang/SmartAlbum/ \
  ubuntu@49.235.173.214:/tmp/smartalbum/
```

### 3.2 部署后端

```bash
# 复制后端代码
cp -r /tmp/smartalbum/backend/* /opt/smartalbum/backend/
cd /opt/smartalbum/backend

# 创建 Python 虚拟环境
python3.11 -m venv venv
source venv/bin/activate

# 配置 pip 国内镜像
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn

# 升级基础工具
pip install --upgrade pip setuptools wheel

# 分批安装依赖（避免内存不足）
echo "安装核心依赖..."
pip install --no-cache-dir fastapi uvicorn[standard] pydantic pydantic-settings

echo "安装数据库依赖..."
pip install --no-cache-dir sqlalchemy[asyncio] aiosqlite alembic

echo "安装 AI 和工具依赖..."
pip install --no-cache-dir openai httpx redis pillow python-multipart

echo "安装其他依赖..."
pip install --no-cache-dir -r requirements.txt 2>/dev/null || echo "requirements.txt 不存在或已安装完成"

# 创建生产环境配置文件
cat > /opt/smartalbum/backend/.env << 'EOF'
# ==========================================
# SmartAlbum 生产环境配置
# ==========================================

# 基础配置
APP_NAME=SmartAlbum
ENVIRONMENT=production
DEBUG=false

# 安全密钥（请修改为随机字符串，至少32字符）
SECRET_KEY=smartalbum-production-secret-key-change-me-2024

# 默认管理员账号
DEFAULT_USERNAME=admin
DEFAULT_PASSWORD=admin123

# 数据库配置（SQLite）
DATABASE_URL=sqlite+aiosqlite:///opt/smartalbum/data/smartalbum.db

# Redis 配置
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# 存储路径
STORAGE_PATH=/opt/smartalbum/storage
ORIGINALS_PATH=/opt/smartalbum/storage/originals
THUMBNAILS_PATH=/opt/smartalbum/storage/thumbnails
AI_GENERATED_PATH=/opt/smartalbum/storage/ai_generated

# AI 模型配置（豆包）
AI_MODEL_NAME=doubao-seed-2-0-mini
AI_MODEL_ID=doubao-seed-2-0-mini-260215
AI_API_KEY=your-doubao-api-key
AI_API_BASE=https://ark.cn-beijing.volces.com/api/v3
AI_API_PATH=/responses

# 火山引擎图片生成
IMAGE_GEN_MODEL_NAME=doubao-seedream-5-0
IMAGE_GEN_MODEL_ID=doubao-seedream-5-0-260128
IMAGE_GEN_API_KEY=your-volcengine-api-key
IMAGE_GEN_API_BASE=https://ark.cn-beijing.volces.com/api/v3
IMAGE_GEN_API_PATH=/images/generations

# Embedding 配置
EMBEDDING_MODEL_NAME=bce-embedding
EMBEDDING_MODEL_ID=bce-embedding
EMBEDDING_API_KEY=your-embedding-api-key
EMBEDDING_API_BASE=http://your-embedding-server/v1
EMBEDDING_API_PATH=/embeddings
EMBEDDING_DIMENSIONS=1536

# 腾讯云 COS 配置（可选）
COS_ENABLED=false
COS_SECRET_ID=
COS_SECRET_KEY=
COS_BUCKET=
COS_REGION=ap-guangzhou

# CORS 配置（根据实际域名修改）
CORS_ORIGINS=http://49.235.173.214,http://localhost

# 限流配置
RATE_LIMIT_ENABLED=true
RATE_LIMIT_DEFAULT=100/minute
RATE_LIMIT_UPLOAD=10/minute
RATE_LIMIT_AI=30/minute

# 日志配置
LOG_LEVEL=INFO
LOG_FORMAT=text
LOG_FILE_ENABLED=true
LOG_FILE_PATH=/opt/smartalbum/logs/backend.log
EOF

# 设置环境变量文件权限
chmod 600 /opt/smartalbum/backend/.env

# 初始化数据库
python -c "
import asyncio
import sys
sys.path.insert(0, '/opt/smartalbum/backend')
from app.database import init_db
asyncio.run(init_db())
print('数据库初始化完成')
"
```

### 3.3 部署前端

```bash
# 复制前端代码
cp -r /tmp/smartalbum/frontend/* /opt/smartalbum/frontend/
cd /opt/smartalbum/frontend

# 配置 API 地址（修改为你的服务器IP）
cat > .env.production << 'EOF'
VITE_API_BASE_URL=http://49.235.173.214/api
VITE_APP_ENV=production
EOF

# 安装依赖并构建
export NODE_OPTIONS="--max-old-space-size=2048"
npm install --no-audit --no-fund

# 构建生产版本
npm run build

# 验证构建结果
ls -la dist/
```

---

## 四、服务配置

### 4.1 创建 Systemd 后端服务

```bash
sudo tee /etc/systemd/system/smartalbum-backend.service << 'EOF'
[Unit]
Description=SmartAlbum Backend Service
After=network.target redis.service
Wants=redis.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/smartalbum/backend
Environment=PATH=/opt/smartalbum/backend/venv/bin
Environment=PYTHONUNBUFFERED=1
Environment=ENVIRONMENT=production

# 启动命令（4核4G配置，使用2个worker）
ExecStart=/opt/smartalbum/backend/venv/bin/uvicorn \
    app.main:app \
    --host 127.0.0.1 \
    --port 9999 \
    --workers 2 \
    --loop uvloop \
    --access-log \
    --proxy-headers

# 重启策略
Restart=always
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

# 资源限制（4G内存，后端限制1G）
MemoryLimit=1G
CPUQuota=200%

# 日志输出到 journal
StandardOutput=journal
StandardError=journal
SyslogIdentifier=smartalbum-backend

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 /etc/systemd/system/smartalbum-backend.service
sudo systemctl daemon-reload
sudo systemctl enable smartalbum-backend
```

### 4.2 配置 Nginx

```bash
sudo tee /etc/nginx/sites-available/smartalbum << 'EOF'
# 上游后端服务
upstream smartalbum_backend {
    server 127.0.0.1:9999;
    keepalive 32;
}

# HTTP 配置（后续可添加 HTTPS）
server {
    listen 80;
    server_name 49.235.173.214;
    
    # 日志配置
    access_log /var/log/nginx/smartalbum-access.log;
    error_log /var/log/nginx/smartalbum-error.log;
    
    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    
    # 安全响应头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # 静态文件缓存（前端构建文件）
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        root /opt/smartalbum/frontend/dist;
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # API 代理
    location /api/ {
        proxy_pass http://smartalbum_backend/;
        proxy_http_version 1.1;
        
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        
        # 超时设置（AI接口需要较长时间）
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        
        # 上传文件大小限制（50MB）
        client_max_body_size 50M;
    }
    
    # 存储文件访问（照片原图和缩略图）
    location /storage/ {
        alias /opt/smartalbum/storage/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        add_header Access-Control-Allow-Origin "*";
    }
    
    # 前端静态资源
    location / {
        root /opt/smartalbum/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
    
    # 健康检查
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# 启用配置
sudo ln -sf /etc/nginx/sites-available/smartalbum /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### 4.3 配置防火墙

```bash
# 安装 UFW（如果未安装）
sudo apt install -y ufw

# 默认策略
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 允许 SSH
sudo ufw allow 22/tcp

# 允许 HTTP
sudo ufw allow 80/tcp

# 启用防火墙（确认 SSH 连接正常后再执行）
sudo ufw --force enable

# 查看状态
sudo ufw status
```

---

## 五、启动验证

### 5.1 启动所有服务

```bash
# 启动 Redis
sudo systemctl start redis-server

# 启动后端
sudo systemctl start smartalbum-backend

# 启动 Nginx
sudo systemctl start nginx

# 等待服务启动
sleep 5
```

### 5.2 验证服务状态

```bash
echo "=== 服务状态检查 ==="
echo ""

echo "1. Redis 状态:"
sudo systemctl is-active redis-server

echo ""
echo "2. 后端状态:"
sudo systemctl is-active smartalbum-backend

echo ""
echo "3. Nginx 状态:"
sudo systemctl is-active nginx

echo ""
echo "4. 后端健康检查:"
curl -s http://127.0.0.1:9999/api/health || echo "后端未响应"

echo ""
echo "5. Nginx 代理检查:"
curl -s http://127.0.0.1/api/health || echo "Nginx 代理失败"

echo ""
echo "6. 前端页面检查:"
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ || echo "前端访问失败"

echo ""
echo "=== 资源使用 ==="
free -h
df -h /
```

### 5.3 浏览器访问测试

```bash
echo ""
echo "=== 部署完成 ==="
echo "访问地址: http://49.235.173.214"
echo "默认账号: admin"
echo "默认密码: admin123"
echo ""
echo "如果无法访问，请检查:"
echo "1. 安全组是否开放 80 端口"
echo "2. 防火墙规则是否正确"
echo "3. 服务日志是否有错误"
```

---

## 六、日常运维

### 6.1 常用管理命令

```bash
# 查看服务状态
sudo systemctl status smartalbum-backend
sudo systemctl status nginx
sudo systemctl status redis-server

# 查看日志（实时）
sudo journalctl -u smartalbum-backend -f -n 100
sudo tail -f /var/log/nginx/error.log

# 重启服务
sudo systemctl restart smartalbum-backend
sudo systemctl reload nginx

# 停止服务
sudo systemctl stop smartalbum-backend

# 查看资源使用
htop
```

### 6.2 创建运维脚本

```bash
# 创建脚本目录
mkdir -p /opt/smartalbum/scripts

# 健康检查脚本
cat > /opt/smartalbum/scripts/health-check.sh << 'EOF'
#!/bin/bash
HEALTH_URL="http://127.0.0.1:9999/api/health"
LOG_FILE="/opt/smartalbum/logs/health-check.log"

mkdir -p $(dirname $LOG_FILE)

# 检查后端
if ! curl -sf $HEALTH_URL > /dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): 后端服务异常，尝试重启..." >> $LOG_FILE
    sudo systemctl restart smartalbum-backend
fi

# 检查磁盘空间
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 85 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): 磁盘空间不足: ${DISK_USAGE}%" >> $LOG_FILE
fi
EOF
chmod +x /opt/smartalbum/scripts/health-check.sh

# 备份脚本
cat > /opt/smartalbum/scripts/backup.sh << 'EOF'
#!/bin/bash
APP_DIR="/opt/smartalbum"
BACKUP_DIR="/opt/smartalbum/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# 备份数据库
cp $APP_DIR/data/smartalbum.db $BACKUP_DIR/smartalbum_$TIMESTAMP.db

# 备份配置
cp $APP_DIR/backend/.env $BACKUP_DIR/env_$TIMESTAMP.backup

# 压缩前端（如果存在）
if [ -d "$APP_DIR/frontend/dist" ]; then
    tar czf $BACKUP_DIR/frontend_$TIMESTAMP.tar.gz -C $APP_DIR frontend/dist
fi

# 保留最近 7 天的备份
find $BACKUP_DIR -name "*.db" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "备份完成: $TIMESTAMP"
EOF
chmod +x /opt/smartalbum/scripts/backup.sh

# 快速重启脚本
cat > /opt/smartalbum/scripts/restart.sh << 'EOF'
#!/bin/bash
echo "重启 SmartAlbum 服务..."
sudo systemctl restart redis-server
sleep 1
sudo systemctl restart smartalbum-backend
sleep 2
sudo systemctl reload nginx
echo "重启完成"
sleep 2
curl -s http://127.0.0.1/api/health && echo "服务正常" || echo "服务异常"
EOF
chmod +x /opt/smartalbum/scripts/restart.sh
```

### 6.3 配置定时任务

```bash
# 编辑 crontab
sudo crontab -e

# 添加以下内容
# 每 5 分钟检查健康状态
*/5 * * * * /opt/smartalbum/scripts/health-check.sh

# 每天凌晨 3 点备份
0 3 * * * /opt/smartalbum/scripts/backup.sh

# 每周清理日志（删除大于100M的日志）
0 0 * * 0 find /opt/smartalbum/logs -name "*.log" -size +100M -delete
```

---

## 七、故障排查

### 7.1 后端无法启动

```bash
# 查看详细错误
sudo journalctl -u smartalbum-backend -n 50 --no-pager

# 检查虚拟环境
source /opt/smartalbum/backend/venv/bin/activate
cd /opt/smartalbum/backend
python -c "from app.main import app; print('导入成功')"

# 检查端口占用
sudo netstat -tlnp | grep 9999
sudo fuser -k 9999/tcp  # 强制释放端口
```

### 7.2 前端无法访问

```bash
# 检查 Nginx 配置
sudo nginx -t

# 检查前端文件是否存在
ls -la /opt/smartalbum/frontend/dist/

# 查看 Nginx 错误日志
sudo tail -f /var/log/nginx/error.log

# 检查端口监听
sudo netstat -tlnp | grep 80
```

### 7.3 数据库连接失败

```bash
# 检查数据库文件权限
ls -la /opt/smartalbum/data/
sudo chown -R ubuntu:ubuntu /opt/smartalbum/data/

# 检查 SQLite
sqlite3 /opt/smartalbum/data/smartalbum.db ".tables"
```

### 7.4 Redis 连接失败

```bash
# 检查 Redis 状态
sudo systemctl status redis-server
redis-cli ping

# 检查 Redis 配置
cat /etc/redis/redis.conf | grep -E "^(bind|port|protected-mode)"
```

### 7.5 内存不足

```bash
# 查看内存使用
free -h

# 查看进程内存占用
ps aux --sort=-%mem | head -10

# 重启服务释放内存
sudo systemctl restart smartalbum-backend

# 增加 Swap（如果物理内存不足）
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## 八、安全加固（可选）

### 8.1 配置 HTTPS（使用 Let's Encrypt）

```bash
# 安装 certbot
sudo apt install -y certbot python3-certbot-nginx

# 申请证书（需要有域名解析到服务器）
sudo certbot --nginx -d your-domain.com

# 自动续期
echo "0 0 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
```

### 8.2 修改默认密码

```bash
# 编辑环境变量文件
vim /opt/smartalbum/backend/.env

# 修改以下配置
SECRET_KEY=your-random-secret-key-$(openssl rand -hex 32)
DEFAULT_PASSWORD=your-secure-password

# 重启服务
sudo systemctl restart smartalbum-backend
```

---

## 附录：一键部署脚本

将以下内容保存为 `deploy.sh`，在服务器上执行即可自动部署：

```bash
#!/bin/bash
set -e

APP_DIR="/opt/smartalbum"
SERVER_IP="49.235.173.214"

echo "=== SmartAlbum 一键部署脚本 ==="
echo "服务器: $SERVER_IP"
echo ""

# 1. 系统更新
echo "[1/10] 更新系统..."
sudo apt update && sudo apt upgrade -y

# 2. 安装依赖
echo "[2/10] 安装系统依赖..."
sudo apt install -y python3.11 python3.11-venv python3-pip nodejs npm redis-server nginx git curl

# 3. 创建目录
echo "[3/10] 创建应用目录..."
sudo mkdir -p $APP_DIR/{backend,frontend,data,storage,logs,backup,scripts}
sudo chown -R ubuntu:ubuntu $APP_DIR

# 4. 配置 Redis
echo "[4/10] 配置 Redis..."
sudo systemctl enable redis-server
sudo systemctl start redis-server

# 5. 部署后端（假设代码已在 /tmp/smartalbum）
echo "[5/10] 部署后端..."
if [ -d "/tmp/smartalbum/backend" ]; then
    cp -r /tmp/smartalbum/backend/* $APP_DIR/backend/
fi

cd $APP_DIR/backend
python3.11 -m venv venv
source venv/bin/activate
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip install --upgrade pip
pip install fastapi uvicorn sqlalchemy aiosqlite openai redis pillow

# 创建默认配置文件
cat > .env << EOF
ENVIRONMENT=production
DEBUG=false
SECRET_KEY=change-me-$(date +%s)
DATABASE_URL=sqlite+aiosqlite://$APP_DIR/data/smartalbum.db
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_DB=0
STORAGE_PATH=$APP_DIR/storage
CORS_ORIGINS=http://$SERVER_IP
EOF

# 6. 部署前端
echo "[6/10] 部署前端..."
if [ -d "/tmp/smartalbum/frontend" ]; then
    cp -r /tmp/smartalbum/frontend/* $APP_DIR/frontend/
fi

cd $APP_DIR/frontend
npm config set registry https://registry.npmmirror.com
npm install
npm run build

# 7. 配置 Systemd
echo "[7/10] 配置 Systemd 服务..."
sudo tee /etc/systemd/system/smartalbum-backend.service > /dev/null << EOF
[Unit]
Description=SmartAlbum Backend
After=network.target redis.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=$APP_DIR/backend
Environment=PATH=$APP_DIR/backend/venv/bin
ExecStart=$APP_DIR/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 9999 --workers 2
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable smartalbum-backend

# 8. 配置 Nginx
echo "[8/10] 配置 Nginx..."
sudo tee /etc/nginx/sites-available/smartalbum > /dev/null << EOF
server {
    listen 80;
    server_name $SERVER_IP;
    
    location /api/ {
        proxy_pass http://127.0.0.1:9999/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        client_max_body_size 50M;
    }
    
    location /storage/ {
        alias $APP_DIR/storage/;
    }
    
    location / {
        root $APP_DIR/frontend/dist;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/smartalbum /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 9. 启动服务
echo "[9/10] 启动服务..."
sudo systemctl start smartalbum-backend

# 10. 验证
echo "[10/10] 验证部署..."
sleep 3
if curl -sf http://127.0.0.1/api/health > /dev/null; then
    echo ""
    echo "=== 部署成功 ==="
    echo "访问地址: http://$SERVER_IP"
    echo "默认账号: admin"
    echo "默认密码: admin123"
else
    echo "部署可能存在问题，请检查日志:"
    echo "sudo journalctl -u smartalbum-backend -n 20"
fi
```

---

**部署手册完成！如有问题请随时询问。**
