#!/bin/bash
# 修复后端构建问题

set -e

echo "=========================================="
echo "修复后端构建问题"
echo "=========================================="

cd /opt/smartalbum

# 1. 清理旧容器和镜像
echo "[1/6] 清理旧容器和镜像..."
docker rm -f smartalbum-backend smartalbum-frontend smartalbum-redis 2>/dev/null || true
docker rmi smartalbum-backend smartalbum-frontend 2>/dev/null || true
docker system prune -f

# 2. 清理系统缓存
echo "[2/6] 清理系统缓存..."
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

# 3. 配置 pip 镜像（在宿主机）
echo "[3/6] 配置 pip 镜像..."
mkdir -p ~/.config/pip
cat > ~/.config/pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
timeout = 120
EOF

# 4. 手动构建后端镜像
echo "[4/6] 构建后端镜像（这可能需要10-20分钟）..."
cd backend

# 禁用 BuildKit，使用传统构建
export DOCKER_BUILDKIT=0

docker build -f Dockerfile.low-memory -t smartalbum-backend:latest . 2>&1 || {
    echo "构建失败，尝试使用更简单的方案..."
    
    # 创建极简 Dockerfile
    cat > Dockerfile.mini <<'DOCKERFILE'
FROM python:3.11-slim

WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ cmake \
    libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# 安装核心依赖（分步进行）
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \
    pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir fastapi uvicorn sqlalchemy aiosqlite && \
    pip install --no-cache-dir Pillow piexif && \
    pip install --no-cache-dir python-dotenv pydantic pydantic-settings && \
    pip install --no-cache-dir httpx aiofiles celery redis && \
    pip install --no-cache-dir cos-python-sdk-v5

# 复制应用代码
COPY . .

# 创建目录
RUN mkdir -p /app/data /app/storage/originals /app/storage/thumbnails \
    /app/storage/ai_generated /app/logs

ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV DATABASE_URL=sqlite+aiosqlite:///./data/smartalbum.db
ENV STORAGE_PATH=/app/storage

EXPOSE 9000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "9000"]
DOCKERFILE

    docker build -f Dockerfile.mini -t smartalbum-backend:latest .
}

cd ..

# 5. 构建前端镜像
echo "[5/6] 构建前端镜像..."
cd frontend
export DOCKER_BUILDKIT=0
docker build -f Dockerfile.low-memory -t smartalbum-frontend:latest . 2>&1 || {
    echo "前端构建失败，尝试备用方案..."
    
    # 备用：使用预构建的 nginx
    cat > Dockerfile.mini <<'DOCKERFILE'
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN mkdir -p /usr/share/nginx/html/storage
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
DOCKERFILE

    docker build -f Dockerfile.mini -t smartalbum-frontend:latest .
}
cd ..

# 6. 启动服务
echo "[6/6] 启动服务..."
docker network create smartalbum-network 2>/dev/null || true

# 启动 Redis
docker run -d --name smartalbum-redis --network smartalbum-network \
    --restart unless-stopped redis:7-alpine 2>/dev/null || docker start smartalbum-redis

# 启动后端
docker run -d --name smartalbum-backend --network smartalbum-network \
    --restart unless-stopped -p 9000:9000 \
    -v /opt/smartalbum/data:/app/data \
    -v /opt/smartalbum/storage:/app/storage \
    --env-file /opt/smartalbum/.env \
    smartalbum-backend:latest 2>/dev/null || docker start smartalbum-backend

# 启动前端
docker run -d --name smartalbum-frontend --network smartalbum-network \
    --restart unless-stopped -p 80:80 \
    smartalbum-frontend:latest 2>/dev/null || docker start smartalbum-frontend

# 等待服务启动
sleep 5

echo ""
echo "=========================================="
echo "服务状态:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

# 测试连接
echo "测试后端连接..."
if curl -s http://localhost:9000/api/health > /dev/null 2>&1; then
    echo "✓ 后端服务正常"
else
    echo "✗ 后端服务未就绪，查看日志:"
    docker logs --tail=30 smartalbum-backend
fi

echo ""
echo "测试前端连接..."
if curl -s http://localhost > /dev/null 2>&1; then
    echo "✓ 前端服务正常"
else
    echo "✗ 前端服务未就绪"
fi

echo ""
echo "=========================================="
echo "修复完成！"
echo "访问地址: http://$(curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"
echo "=========================================="
