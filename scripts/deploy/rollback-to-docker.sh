#!/bin/bash
# SmartAlbum 回滚到 Docker 脚本
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="/var/log/smartalbum/rollback-$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$(dirname $LOG_FILE)"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "========================================"
echo "  SmartAlbum 回滚到 Docker"
echo "========================================"
echo ""

# 停止裸机服务
echo "[1/4] 停止裸机服务..."
systemctl stop smartalbum-backend 2>/dev/null || true
systemctl stop smartalbum-worker 2>/dev/null || true
systemctl disable smartalbum-backend 2>/dev/null || true
systemctl disable smartalbum-worker 2>/dev/null || true
fuser -k 9999/tcp 2>/dev/null || true
echo "  ✓ 裸机服务已停止"

# 恢复 Docker
echo "[2/4] 恢复 Docker 部署..."
cd "$PROJECT_ROOT"
docker-compose down 2>/dev/null || true
docker-compose up -d
echo "  ✓ Docker 容器已启动"

# 恢复 Nginx
echo "[3/4] 恢复 Nginx 配置..."
cat > /etc/nginx/sites-available/smartalbum << 'EOF'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:8888;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        client_max_body_size 100M;
    }
}
EOF
nginx -t && systemctl reload nginx
echo "  ✓ Nginx 已恢复"

# 健康检查
echo "[4/4] 健康检查..."
sleep 10
if curl -sf http://localhost:8888/api/health > /dev/null 2>&1; then
    echo "  ✓ 服务正常"
else
    echo "  ⚠ 服务可能还在启动中"
fi

echo ""
echo "========================================"
echo "  回滚完成！"
echo "========================================"
echo "日志: $LOG_FILE"
