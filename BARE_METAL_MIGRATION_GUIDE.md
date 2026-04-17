# SmartAlbum 裸机部署迁移方案

> 本文档指导如何将现有的 Docker 容器部署迁移到裸机部署（非容器方式）
> 
> 适用场景：腾讯云主机生产环境从容器迁移到裸机部署

---

## 一、迁移概述

### 1.1 迁移背景

从容器部署迁移到裸机部署可以带来以下优势：
- **性能提升**：消除容器化开销，直接利用系统资源
- **简化运维**：无需 Docker 依赖，减少故障点
- **资源控制**：更精细的内存和 CPU 控制
- **快速启动**：服务启动速度更快

### 1.2 迁移策略

采用**蓝绿部署 + 数据同步**的迁移策略：

```
阶段1: 准备阶段
├── 数据全量备份
├── 裸机环境准备
└── 配置文件准备

阶段2: 并行部署
├── 裸机部署新版本（绿环境）
├── 容器环境继续运行（蓝环境）
└── 实时数据同步

阶段3: 流量切换
├── 健康检查
├── 流量切换到裸机
└── 监控验证

阶段4: 清理阶段
├── 确认裸机稳定运行
├── 停用容器环境
└── 回滚能力保留（72小时）
```

### 1.3 风险与应对

| 风险 | 概率 | 影响 | 应对措施 |
|------|------|------|----------|
| 数据丢失 | 低 | 极高 | 三重备份 + 实时同步 |
| 服务中断 | 中 | 高 | 蓝绿部署，快速回滚 |
| 配置错误 | 中 | 中 | 配置验证脚本 |
| 性能问题 | 低 | 中 | 预生产压测 |

---

## 二、环境要求

### 2.1 服务器配置

**最低配置：**
- CPU: 2核+
- 内存: 4GB+
- 磁盘: 50GB+（根据照片数量调整）
- 操作系统: Ubuntu 20.04/22.04 LTS

**推荐配置：**
- CPU: 4核+
- 内存: 8GB+
- 磁盘: 200GB+ SSD
- 带宽: 5Mbps+

### 2.2 软件依赖

```bash
# 系统级依赖
- Python 3.11+
- Node.js 20+
- Redis 7+
- Nginx
- SQLite3
- Git

# 编译依赖（用于 face_recognition）
- build-essential
- cmake
- libglib2.0-0
- libsm6
- libxext6
- libxrender-dev
```

---

## 三、迁移前准备

### 3.1 数据备份清单

| 数据类型 | 位置 | 备份方式 | 优先级 |
|----------|------|----------|--------|
| SQLite数据库 | data/smartalbum.db | 冷备份+热备份 | P0 |
| ChromaDB向量 | data/chroma/ | 全量备份 | P0 |
| 原图 | storage/originals/ | 增量备份 | P0 |
| 缩略图 | storage/thumbnails/ | 可选重新生成 | P1 |
| 配置文件 | backend/.env | 加密备份 | P0 |
| 日志文件 | backend/logs/ | 选择性备份 | P2 |

### 3.2 配置收集

从现有容器环境收集以下配置：

```bash
# 1. 导出环境变量
docker exec smartalbum-backend cat /app/.env > backup/container_env.txt

# 2. 检查端口映射
docker ps --format "table {{.Names}}\t{{.Ports}}"

# 3. 检查数据卷
docker volume ls | grep smartalbum
docker inspect <volume_name>

# 4. 检查资源限制
docker inspect smartalbum-backend | grep -A 10 "Memory\|Cpu"

# 5. 导出 Nginx 配置
cat /etc/nginx/sites-available/smartalbum > backup/nginx_config_backup.conf
```

### 3.3 网络规划

```
裸机部署端口规划：
├── 前端: 80/443 (Nginx)
├── 后端: 9999 (本地回环)
├── Redis: 6379 (本地回环)
└── 静态文件: /storage (Nginx直接服务)
```

---

## 四、迁移步骤详解

### 步骤1：系统初始化（预计30分钟）

```bash
# 1.1 更新系统
sudo apt update && sudo apt upgrade -y

# 1.2 安装基础依赖
sudo apt install -y \
    software-properties-common \
    curl wget git vim htop \
    sqlite3 nginx redis-server

# 1.3 安装 Python 3.11
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.11 python3.11-venv python3.11-distutils python3-pip

# 1.4 安装 Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 1.5 安装编译依赖
sudo apt install -y build-essential cmake \
    libglib2.0-0 libsm6 libxext6 libxrender-dev

# 1.6 配置 Redis
sudo tee /etc/redis/redis.conf.d/smartalbum.conf << EOF
maxmemory 128mb
maxmemory-policy allkeys-lru
save ""
appendonly yes
bind 127.0.0.1
EOF
sudo systemctl restart redis-server
sudo systemctl enable redis-server
```

### 步骤2：创建应用目录（预计10分钟）

```bash
# 2.1 创建目录结构
sudo mkdir -p /opt/smartalbum/{backend,frontend,data,storage,logs,backup,scripts}

# 2.2 设置权限
sudo chown -R $USER:$USER /opt/smartalbum
sudo chmod 755 /opt/smartalbum
sudo chmod 750 /opt/smartalbum/data

# 2.3 创建软链接（保持与容器路径兼容）
sudo ln -s /opt/smartalbum/data /data
sudo ln -s /opt/smartalbum/storage /storage
```

### 步骤3：数据迁移（预计时间取决于数据量）

```bash
# 3.1 停止容器写入（进入维护模式）
docker-compose stop backend frontend

# 3.2 导出数据库
sqlite3 data/smartalbum.db ".backup '/opt/smartalbum/backup/smartalbum_migration.db'"

# 3.3 复制数据文件
sudo cp -r data/* /opt/smartalbum/data/
sudo cp -r storage/* /opt/smartalbum/storage/

# 3.4 验证数据完整性
sqlite3 /opt/smartalbum/data/smartalbum.db "PRAGMA integrity_check;"

# 3.5 恢复权限
sudo chown -R $USER:$USER /opt/smartalbum/data
sudo chown -R $USER:$USER /opt/smartalbum/storage
```

### 步骤4：部署后端（预计20分钟）

```bash
cd /opt/smartalbum/backend

# 4.1 复制代码
sudo cp -r /path/to/your/backend/* .

# 4.2 创建虚拟环境
python3.11 -m venv venv
source venv/bin/activate

# 4.3 配置 pip 镜像
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip install --upgrade pip setuptools wheel

# 4.4 安装依赖（分批安装确保稳定性）
pip install fastapi uvicorn sqlalchemy aiosqlite redis celery
pip install Pillow piexif
pip install chromadb sentence-transformers
pip install -r requirements.txt

# 4.5 创建生产环境配置
cat > .env << EOF
ENVIRONMENT=production
DEBUG=false
SECRET_KEY=$(openssl rand -hex 32)
DEFAULT_USERNAME=admin
DEFAULT_PASSWORD=your_secure_password
CORS_ORIGINS=http://localhost,http://your-domain.com
DATABASE_URL=sqlite+aiosqlite:///opt/smartalbum/data/smartalbum.db
REDIS_URL=redis://localhost:6379/1
STORAGE_PATH=/opt/smartalbum/storage
AI_API_KEY=your-api-key
EOF

chmod 600 .env
```

### 步骤5：部署前端（预计15分钟）

```bash
cd /opt/smartalbum/frontend

# 5.1 复制代码
sudo cp -r /path/to/your/frontend/* .

# 5.2 配置 npm 镜像
npm config set registry https://registry.npmmirror.com

# 5.3 安装依赖
npm ci --no-audit --no-fund

# 5.4 构建生产版本
npm run build

# 5.5 验证构建
ls -la dist/
```

### 步骤6：配置 Systemd 服务（预计10分钟）

```bash
# 6.1 后端服务
sudo tee /etc/systemd/system/smartalbum-backend.service << 'EOF'
[Unit]
Description=SmartAlbum Backend
After=network.target redis.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/smartalbum/backend
Environment=PATH=/opt/smartalbum/backend/venv/bin
Environment=PYTHONUNBUFFERED=1
Environment=ENVIRONMENT=production
ExecStart=/opt/smartalbum/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 9999 --workers 2
Restart=always
RestartSec=5
MemoryLimit=1G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF

# 6.2 Celery Worker 服务
sudo tee /etc/systemd/system/smartalbum-worker.service << 'EOF'
[Unit]
Description=SmartAlbum Celery Worker
After=network.target redis.service smartalbum-backend.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/smartalbum/backend
Environment=PATH=/opt/smartalbum/backend/venv/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/smartalbum/backend/venv/bin/celery -A tasks.celery_app worker --loglevel=info --concurrency=2
Restart=always
RestartSec=10
MemoryLimit=512M

[Install]
WantedBy=multi-user.target
EOF

# 6.3 重载并启用服务
sudo systemctl daemon-reload
sudo systemctl enable smartalbum-backend
sudo systemctl enable smartalbum-worker
```

### 步骤7：配置 Nginx（预计15分钟）

```bash
# 7.1 创建 Nginx 配置
sudo tee /etc/nginx/sites-available/smartalbum << 'EOF'
upstream backend {
    server 127.0.0.1:9999;
    keepalive 32;
}

# 限制请求频率
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=upload_limit:10m rate=1r/s;

server {
    listen 80;
    server_name _;
    
    access_log /var/log/nginx/smartalbum-access.log;
    error_log /var/log/nginx/smartalbum-error.log;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|webp|ico|css|js)$ {
        root /opt/smartalbum/frontend/dist;
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # 存储文件
    location /storage/ {
        alias /opt/smartalbum/storage/;
        expires 30d;
        add_header Cache-Control "public";
        
        # 大文件优化
        sendfile on;
        tcp_nopush on;
    }
    
    # API 上传限制
    location /api/upload/ {
        limit_req zone=upload_limit burst=5 nodelay;
        client_max_body_size 100M;
        
        proxy_pass http://backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 长连接优化
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # API 限流
    location /api/ {
        limit_req zone=api_limit burst=20 nodelay;
        
        proxy_pass http://backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
    
    # 前端 SPA
    location / {
        root /opt/smartalbum/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
        
        # 不缓存 HTML
        location ~* \.html$ {
            expires -1;
            add_header Cache-Control "no-store, no-cache, must-revalidate";
        }
    }
}
EOF

# 7.2 启用配置
sudo ln -sf /etc/nginx/sites-available/smartalbum /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 7.3 测试并重载
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl enable nginx
```

### 步骤8：启动与验证（预计20分钟）

```bash
# 8.1 启动后端服务
sudo systemctl start smartalbum-backend
sleep 5
sudo systemctl start smartalbum-worker

# 8.2 检查服务状态
sudo systemctl status smartalbum-backend
sudo systemctl status smartalbum-worker

# 8.3 健康检查
curl -f http://localhost:9999/api/health
curl -f http://localhost/api/health

# 8.4 检查日志
sudo journalctl -u smartalbum-backend -n 50 --no-pager

# 8.5 功能测试
# 访问 http://your-server-ip 测试基础功能
# 测试上传、浏览、搜索等核心功能
```

---

## 五、回滚方案

### 5.1 快速回滚脚本

如果裸机部署出现问题，30秒内回滚到容器：

```bash
#!/bin/bash
# quick-rollback-to-docker.sh

echo "正在回滚到 Docker 部署..."

# 停止裸机服务
sudo systemctl stop smartalbum-backend
sudo systemctl stop smartalbum-worker

# 恢复 Nginx 配置（指向 Docker）
sudo tee /etc/nginx/sites-available/smartalbum << 'EOF'
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:8888;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

sudo nginx -s reload

# 启动 Docker
cd /path/to/docker-compose
docker-compose up -d

echo "回滚完成，请验证服务状态"
```

### 5.2 数据恢复

```bash
# 如果数据已损坏，从备份恢复
sqlite3 /opt/smartalbum/data/smartalbum.db ".restore '/opt/smartalbum/backup/smartalbum_migration.db'"
```

---

## 六、迁移后优化

### 6.1 性能调优

```bash
# SQLite 优化
sqlite3 /opt/smartalbum/data/smartalbum.db << EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA temp_store = MEMORY;
EOF

# 系统优化
sudo tee -a /etc/sysctl.conf << EOF
# 文件描述符
fs.file-max = 65536

# TCP 优化
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# 内存优化
vm.swappiness = 10
EOF

sudo sysctl -p
```

### 6.2 监控配置

```bash
# 创建监控脚本
sudo tee /opt/smartalbum/scripts/monitor.sh << 'EOF'
#!/bin/bash
# 监控脚本

LOG_FILE="/var/log/smartalbum/monitor.log"
mkdir -p $(dirname $LOG_FILE)

# 检查服务状态
if ! systemctl is-active --quiet smartalbum-backend; then
    echo "$(date): 后端服务异常，尝试重启" >> $LOG_FILE
    systemctl restart smartalbum-backend
fi

# 检查磁盘空间
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    echo "$(date): 磁盘空间不足: ${DISK_USAGE}%" >> $LOG_FILE
fi

# 检查内存
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
if [ "$MEM_USAGE" -gt 90 ]; then
    echo "$(date): 内存使用过高: ${MEM_USAGE}%" >> $LOG_FILE
fi
EOF

chmod +x /opt/smartalbum/scripts/monitor.sh

# 添加定时任务
crontab -l > /tmp/crontab_backup 2>/dev/null || true
echo "*/5 * * * * /opt/smartalbum/scripts/monitor.sh" >> /tmp/crontab_backup
crontab /tmp/crontab_backup
rm /tmp/crontab_backup
```

---

## 七、常见问题

### Q1: face_recognition 安装失败

```bash
# 解决方案
sudo apt install -y build-essential cmake libdlib-dev
pip install dlib --verbose
pip install face-recognition
```

### Q2: 内存不足

```bash
# 创建 swap 文件
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 永久生效
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Q3: 权限问题

```bash
# 修复权限
sudo chown -R $USER:$USER /opt/smartalbum
sudo chmod -R u+rw /opt/smartalbum/data
sudo chmod -R u+rw /opt/smartalbum/storage
```

---

## 八、验证清单

迁移完成后，请逐项检查：

- [ ] 服务正常启动，无错误日志
- [ ] 数据库连接正常，数据完整
- [ ] 照片浏览功能正常
- [ ] 照片上传功能正常
- [ ] AI 分析功能正常
- [ ] 向量搜索功能正常
- [ ] 用户登录功能正常
- [ ] 静态文件访问正常
- [ ] 备份任务正常运行
- [ ] 监控告警正常

---

## 九、联系支持

遇到问题？
1. 查看日志：`sudo journalctl -u smartalbum-backend -f`
2. 运行健康检查：`./scripts/deploy/health-check.sh`
3. 查看详细指南：`BARE_METAL_DEPLOYMENT_GUIDE.md`

---

**文档版本**: 1.0  
**更新日期**: 2026-04-16  
**适用版本**: SmartAlbum >= 1.0.0
