#!/bin/bash
# SmartAlbum 直接部署脚本（不使用 Docker）
# 适用于网络受限的腾讯云 Lighthouse 服务器

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  SmartAlbum 直接部署脚本"
echo "=========================================="
echo ""

# 获取服务器 IP
SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}服务器 IP: ${SERVER_IP}${NC}"
echo ""

# 检查 Python
echo "[1/6] 检查 Python 环境..."
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}安装 Python3...${NC}"
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-venv
fi
python3 --version

# 检查 Node.js
echo "[2/6] 检查 Node.js 环境..."
if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}安装 Node.js...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
node --version
npm --version

# 创建必要的目录
echo "[3/6] 创建数据目录..."
mkdir -p data storage/originals storage/thumbnails

# 安装后端依赖
echo "[4/6] 安装后端依赖..."
cd backend
python3 -m venv venv
source venv/bin/activate

# 安装系统依赖（用于人脸识别）
echo "安装系统依赖..."
sudo apt-get install -y build-essential cmake libopenblas-dev liblapack-dev \
    libx11-dev libgtk-3-dev libboost-python-dev libdlib-dev

# 安装 Python 包
echo "安装 Python 包..."
pip install -r requirements.txt
cd ..

# 安装前端依赖
echo "[5/6] 安装前端依赖..."
cd frontend
npm install
cd ..

# 配置 systemd 服务
echo "[6/6] 配置系统服务..."

# 后端服务
sudo tee /etc/systemd/system/smartalbum-backend.service > /dev/null <<EOF
[Unit]
Description=SmartAlbum Backend
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/smartalbum/backend
Environment=PATH=/opt/smartalbum/backend/venv/bin
Environment=DATABASE_URL=sqlite+aiosqlite:///./data/smartalbum.db
Environment=DEBUG=False
ExecStart=/opt/smartalbum/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 9000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 前端服务
sudo tee /etc/systemd/system/smartalbum-frontend.service > /dev/null <<EOF
[Unit]
Description=SmartAlbum Frontend
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/smartalbum/frontend
Environment=VITE_API_BASE_URL=http://localhost:9000
ExecStart=/usr/bin/npm run dev -- --host 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd
sudo systemctl daemon-reload

# 启动服务
sudo systemctl enable smartalbum-backend
sudo systemctl enable smartalbum-frontend
sudo systemctl start smartalbum-backend
sudo systemctl start smartalbum-frontend

echo ""
echo "=========================================="
echo -e "${GREEN}  部署完成！${NC}"
echo "=========================================="
echo ""
echo "访问地址："
echo "  前端页面: http://${SERVER_IP}:5173"
echo "  后端 API: http://${SERVER_IP}:9000"
echo ""
echo "常用命令："
echo "  查看后端日志: sudo journalctl -f -u smartalbum-backend"
echo "  查看前端日志: sudo journalctl -f -u smartalbum-frontend"
echo "  重启后端: sudo systemctl restart smartalbum-backend"
echo "  重启前端: sudo systemctl restart smartalbum-frontend"
echo ""
