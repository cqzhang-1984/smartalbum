# SmartAlbum 裸机部署升级完整方案

> **版本**: v1.0  
> **适用环境**: Ubuntu 22.04/24.04 LTS  
> **内存要求**: 最低 1GB，推荐 2GB+  
> **部署方式**: 裸机部署（无 Docker）

---

## 📋 方案概述

### 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    腾讯云服务器                              │
│                     Ubuntu 24.04                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Nginx      │  │   Backend    │  │    Redis     │      │
│  │   :80        │  │   :9999      │  │   :6379      │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                 │                  │              │
│         └─────────────────┴──────────────────┘              │
│                           │                                 │
│                    ┌──────┴──────┐                         │
│                    │   Systemd   │                         │
│                    │  服务管理    │                         │
│                    └─────────────┘                         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  /opt/smartalbum/                                   │   │
│  │  ├── backend/     # Python FastAPI                 │   │
│  │  ├── frontend/    # Vue 前端                       │   │
│  │  ├── data/        # SQLite 数据库                  │   │
│  │  ├── storage/     # 照片存储                       │   │
│  │  ├── logs/        # 日志文件                       │   │
│  │  └── backup/      # 备份文件                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 核心组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| Nginx | latest | 80 | 反向代理 + 静态文件 |
| Python | 3.11 | - | FastAPI 后端 |
| Node.js | 20 | - | Vue 前端构建 |
| Redis | 7 | 6379 | 缓存 + 任务队列 |
| SQLite | 3 | - | 数据持久化 |

---

## 🚀 第一部分：首次部署

### 步骤 1：准备服务器

```bash
# 1.1 SSH 登录服务器
ssh ubuntu@你的腾讯云IP

# 1.2 更新系统
sudo apt update && sudo apt upgrade -y

# 1.3 安装基础依赖
sudo apt install -y \
    python3.11 python3.11-venv python3-pip \
    nodejs npm \
    redis-server \
    nginx \
    git curl wget \
    htop sqlite3 \
    supervisor

# 1.4 配置时区
sudo timedatectl set-timezone Asia/Shanghai
```

### 步骤 2：创建应用目录

```bash
# 创建目录结构
sudo mkdir -p /opt/smartalbum/{backend,frontend,data,storage,logs,backup}
sudo chown -R ubuntu:ubuntu /opt/smartalbum

# 设置权限
chmod 755 /opt/smartalbum
chmod 750 /opt/smartalbum/data
```

### 步骤 3：部署后端

```bash
# 3.1 进入后端目录
cd /opt/smartalbum

# 3.2 克隆或解压代码（根据实际情况选择）
# 方式 A：Git 克隆
git clone https://github.com/cqzhang-1984/smartalbum.git temp
cp -r temp/backend/* backend/
rm -rf temp

# 方式 B：解压上传的代码
# unzip ~/smartalbum.zip -d /tmp/
# cp -r /tmp/smartalbum/backend/* backend/

# 3.3 创建虚拟环境
cd backend
python3.11 -m venv venv
source venv/bin/activate

# 3.4 安装依赖（使用国内镜像）
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip install --upgrade pip setuptools wheel

# 3.5 分步安装依赖（避免内存不足）
pip install --no-cache-dir fastapi uvicorn sqlalchemy aiosqlite
pip install --no-cache-dir redis celery pillow
pip install --no-cache-dir -r requirements.txt

# 3.6 配置环境变量
sudo tee /opt/smartalbum/backend/.env << 'EOF'
ENVIRONMENT=production
DEBUG=false
SECRET_KEY=your-256-bit-secret-key-change-this
DEFAULT_USERNAME=admin
DEFAULT_PASSWORD=your-secure-password
CORS_ORIGINS=http://localhost,http://127.0.0.1
DATABASE_URL=sqlite+aiosqlite:///opt/smartalbum/data/smartalbum.db
REDIS_URL=redis://localhost:6379/0
STORAGE_PATH=/opt/smartalbum/storage
AI_API_KEY=your-ai-api-key
EOF

sudo chmod 600 /opt/smartalbum/backend/.env
sudo chown ubuntu:ubuntu /opt/smartalbum/backend/.env
```

### 步骤 4：配置 Systemd 服务

```bash
# 创建后端服务
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

# 启动命令
ExecStart=/opt/smartalbum/backend/venv/bin/uvicorn \
    app.main:app \
    --host 0.0.0.0 \
    --port 9999 \
    --workers 1 \
    --loop uvloop \
    --http h11 \
    --access-log \
    --error-log

# 重启策略
Restart=always
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

# 资源限制
MemoryLimit=512M
CPUQuota=100%

# 日志
StandardOutput=append:/opt/smartalbum/logs/backend.log
StandardError=append:/opt/smartalbum/logs/backend-error.log

[Install]
WantedBy=multi-user.target
EOF

# 设置权限
sudo chmod 644 /etc/systemd/system/smartalbum-backend.service

# 重载配置
sudo systemctl daemon-reload
sudo systemctl enable smartalbum-backend
```

### 步骤 5：部署前端

```bash
# 5.1 复制前端代码
cd /opt/smartalbum
cp -r ~/smartalbum/frontend/* frontend/ 2>/dev/null || echo "请确保前端代码已上传"

# 5.2 进入前端目录
cd frontend

# 5.3 配置 npm 国内镜像
npm config set registry https://registry.npmmirror.com

# 5.4 安装依赖（限制内存使用）
export NODE_OPTIONS="--max-old-space-size=1024"
npm install --no-audit --no-fund

# 5.5 构建生产版本
npm run build

# 5.6 验证构建
ls -la dist/
```

### 步骤 6：配置 Nginx

```bash
# 6.1 创建 Nginx 配置
sudo tee /etc/nginx/sites-available/smartalbum << 'EOF'
# 上游后端服务
upstream smartalbum_backend {
    server 127.0.0.1:9999;
    keepalive 32;
}

server {
    listen 80;
    server_name _;
    
    # 日志配置
    access_log /var/log/nginx/smartalbum-access.log;
    error_log /var/log/nginx/smartalbum-error.log;
    
    # 安全响应头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
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
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 上传文件大小限制
        client_max_body_size 100M;
    }
    
    # 存储文件访问
    location /storage/ {
        alias /opt/smartalbum/storage/;
        expires 30d;
        add_header Cache-Control "public, immutable";
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

# 6.2 启用配置
sudo ln -sf /etc/nginx/sites-available/smartalbum /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 6.3 测试并重载
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl enable nginx
```

### 步骤 7：配置 Redis

```bash
# 7.1 配置 Redis（低内存模式）
sudo tee /etc/redis/redis.conf.d/smartalbum.conf << 'EOF'
# 内存限制
maxmemory 64mb
maxmemory-policy allkeys-lru

# 持久化配置
save ""
appendonly yes
appendfsync everysec

# 安全配置
bind 127.0.0.1
protected-mode yes
EOF

# 7.2 重启 Redis
sudo systemctl restart redis-server
sudo systemctl enable redis-server
```

### 步骤 8：初始化并启动

```bash
# 8.1 初始化数据库
cd /opt/smartalbum/backend
source venv/bin/activate
python -c "
import asyncio
import sys
sys.path.insert(0, '.')
from app.database import init_db
asyncio.run(init_db())
print('✓ 数据库初始化完成')
"

# 8.2 启动后端服务
sudo systemctl start smartalbum-backend

# 8.3 等待服务启动
sleep 5

# 8.4 验证部署
echo "=== 部署验证 ==="
curl -s http://localhost:9999/api/health && echo " ✓ 后端正常"
curl -s http://localhost/ | head -1 && echo " ✓ 前端正常"
systemctl is-active smartalbum-backend && echo " ✓ 服务运行中"

echo ""
echo "=== 部署完成 ==="
echo "访问地址: http://$(curl -s ifconfig.me 2>/dev/null || echo '你的服务器IP')"
```

---

## 🔄 第二部分：升级更新

### 升级流程图

```
┌─────────────────────────────────────────────────────────┐
│                    升级流程                              │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. 备份数据 ───→ 2. 上传新代码 ───→ 3. 停止服务         │
│       │                │                │               │
│       ▼                ▼                ▼               │
│  4. 更新后端 ───→ 5. 更新前端 ───→ 6. 数据库迁移         │
│       │                │                │               │
│       └────────────────┴────────────────┘               │
│                     │                                   │
│                     ▼                                   │
│              7. 启动服务 ───→ 8. 健康检查               │
│                     │                                   │
│              失败？←─┴─→ 9. 回滚                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 升级脚本

```bash
#!/bin/bash
# upgrade.sh - 升级脚本

set -e

APP_DIR="/opt/smartalbum"
BACKUP_DIR="/opt/smartalbum/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== SmartAlbum 升级脚本 ==="
echo "时间: $TIMESTAMP"
echo ""

# 1. 备份
echo "[1/8] 备份数据..."
mkdir -p $BACKUP_DIR
sudo systemctl stop smartalbum-backend
cp $APP_DIR/data/smartalbum.db $BACKUP_DIR/smartalbum_$TIMESTAMP.db
tar czf $BACKUP_DIR/frontend_$TIMESTAMP.tar.gz -C $APP_DIR frontend/dist 2>/dev/null || true
echo "✓ 备份完成"

# 2. 上传新代码（手动上传后执行）
echo "[2/8] 请确保新代码已上传到 ~/smartalbum-new/"
read -p "按回车继续..."

# 3. 停止服务
echo "[3/8] 停止服务..."
sudo systemctl stop smartalbum-backend
echo "✓ 服务已停止"

# 4. 更新后端
echo "[4/8] 更新后端..."
cd $APP_DIR/backend
source venv/bin/activate

# 保留 .env 文件
cp .env .env.backup

# 更新代码
rm -rf app/
cp -r ~/smartalbum-new/backend/app ./
cp ~/smartalbum-new/backend/requirements.txt ./

# 恢复 .env
mv .env.backup .env

# 安装新依赖
pip install -r requirements.txt --upgrade
echo "✓ 后端更新完成"

# 5. 更新前端
echo "[5/8] 更新前端..."
cd $APP_DIR/frontend
cp -r ~/smartalbum-new/frontend/src ./
cp ~/smartalbum-new/frontend/package*.json ./
npm install
npm run build
echo "✓ 前端更新完成"

# 6. 数据库迁移
echo "[6/8] 数据库迁移..."
cd $APP_DIR/backend
python -c "
import asyncio
from app.database import init_db
asyncio.run(init_db())
"
echo "✓ 数据库迁移完成"

# 7. 启动服务
echo "[7/8] 启动服务..."
sudo systemctl start smartalbum-backend
sudo systemctl reload nginx
sleep 5
echo "✓ 服务已启动"

# 8. 健康检查
echo "[8/8] 健康检查..."
if curl -sf http://localhost:9999/api/health > /dev/null; then
    echo "✓ 升级成功！"
else
    echo "✗ 健康检查失败，准备回滚..."
    # 回滚逻辑
    sudo systemctl stop smartalbum-backend
    cp $BACKUP_DIR/smartalbum_$TIMESTAMP.db $APP_DIR/data/smartalbum.db
    sudo systemctl start smartalbum-backend
    echo "✓ 已回滚到之前版本"
fi

echo ""
echo "=== 升级完成 ==="
echo "备份文件: $BACKUP_DIR/smartalbum_$TIMESTAMP.db"
```

---

## 🛡️ 第三部分：备份与回滚

### 自动备份脚本

```bash
#!/bin/bash
# backup.sh - 定时备份

APP_DIR="/opt/smartalbum"
BACKUP_DIR="/opt/smartalbum/backup"
REMOTE_BACKUP="your-backup-server:/backups/smartalbum"  # 可选

mkdir -p $BACKUP_DIR

# 备份数据库
cp $APP_DIR/data/smartalbum.db $BACKUP_DIR/smartalbum_$(date +%Y%m%d).db

# 备份配置
cp $APP_DIR/backend/.env $BACKUP_DIR/env_$(date +%Y%m%d).backup

# 压缩前端
tar czf $BACKUP_DIR/frontend_$(date +%Y%m%d).tar.gz -C $APP_DIR frontend/dist

# 保留最近 7 天的备份
find $BACKUP_DIR -name "*.db" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
find $BACKUP_DIR -name "*.backup" -mtime +7 -delete

# 可选：同步到远程
# rsync -avz $BACKUP_DIR/ $REMOTE_BACKUP/
```

### 一键回滚脚本

```bash
#!/bin/bash
# rollback.sh - 回滚脚本

APP_DIR="/opt/smartalbum"
BACKUP_DIR="/opt/smartalbum/backup"

# 列出可用备份
echo "可用备份:"
ls -lt $BACKUP_DIR/*.db | head -10

echo ""
read -p "输入要恢复的备份文件名（如: smartalbum_20260415_120000.db）: " BACKUP_FILE

if [ ! -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
    echo "错误: 备份文件不存在"
    exit 1
fi

echo "=== 开始回滚 ==="

# 停止服务
sudo systemctl stop smartalbum-backend

# 备份当前状态（防止回滚失败）
cp $APP_DIR/data/smartalbum.db $BACKUP_DIR/smartalbum_before_rollback_$(date +%Y%m%d%H%M%S).db

# 恢复数据
cp $BACKUP_DIR/$BACKUP_FILE $APP_DIR/data/smartalbum.db
chown ubuntu:ubuntu $APP_DIR/data/smartalbum.db

# 重启服务
sudo systemctl start smartalbum-backend

# 验证
sleep 3
if curl -sf http://localhost:9999/api/health > /dev/null; then
    echo "✓ 回滚成功！"
else
    echo "✗ 回滚后服务异常，请检查日志"
fi
```

---

## 📊 第四部分：监控与维护

### 健康检查脚本

```bash
#!/bin/bash
# health-check.sh

HEALTH_URL="http://localhost:9999/api/health"
LOG_FILE="/opt/smartalbum/logs/health-check.log"

# 检查后端
if ! curl -sf $HEALTH_URL > /dev/null; then
    echo "$(date): 后端服务异常，尝试重启..." >> $LOG_FILE
    sudo systemctl restart smartalbum-backend
fi

# 检查磁盘空间
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 85 ]; then
    echo "$(date): 磁盘空间不足: ${DISK_USAGE}%" >> $LOG_FILE
fi

# 检查内存
MEM_AVAILABLE=$(free -m | awk 'NR==2{print $7}')
if [ $MEM_AVAILABLE -lt 100 ]; then
    echo "$(date): 可用内存不足: ${MEM_AVAILABLE}MB" >> $LOG_FILE
fi
```

### 定时任务配置

```bash
# 编辑 crontab
sudo crontab -e

# 添加以下内容
# 每 5 分钟检查健康状态
*/5 * * * * /opt/smartalbum/scripts/health-check.sh

# 每天凌晨 3 点备份
0 3 * * * /opt/smartalbum/scripts/backup.sh

# 每周清理日志
0 0 * * 0 find /opt/smartalbum/logs -name "*.log" -size +100M -delete
```

### 常用管理命令

```bash
# 查看服务状态
sudo systemctl status smartalbum-backend
sudo systemctl status nginx
sudo systemctl status redis

# 查看日志
sudo journalctl -u smartalbum-backend -f -n 100
sudo tail -f /opt/smartalbum/logs/backend.log
sudo tail -f /var/log/nginx/error.log

# 重启服务
sudo systemctl restart smartalbum-backend
sudo systemctl reload nginx

# 更新代码后重启
sudo systemctl restart smartalbum-backend

# 查看资源使用
htop
sudo netstat -tlnp
```

---

## 📁 文件清单

```
/opt/smartalbum/
├── backend/              # 后端代码
│   ├── app/             # 应用代码
│   ├── venv/            # Python 虚拟环境
│   ├── requirements.txt
│   └── .env             # 环境变量
├── frontend/            # 前端代码
│   ├── src/             # 源代码
│   └── dist/            # 构建产物
├── data/                # 数据库
│   └── smartalbum.db
├── storage/             # 照片存储
│   ├── originals/
│   └── thumbnails/
├── logs/                # 日志文件
├── backup/              # 备份文件
└── scripts/             # 脚本
    ├── deploy.sh        # 首次部署
    ├── upgrade.sh       # 升级
    ├── backup.sh        # 备份
    ├── rollback.sh      # 回滚
    └── health-check.sh  # 健康检查
```

---

## ✅ 部署检查清单

首次部署前请确认：

- [ ] 服务器内存 >= 1GB
- [ ] Ubuntu 22.04/24.04 LTS
- [ ] 已配置 SSH 密钥登录
- [ ] 已配置环境变量（SECRET_KEY、AI_API_KEY 等）
- [ ] 防火墙开放 80 端口
- [ ] 域名解析已配置（如有域名）

---

**方案完成！有任何问题请随时询问。**
