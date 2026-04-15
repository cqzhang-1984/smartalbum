#!/bin/bash
# SmartAlbum 部署脚本
# 用于在腾讯云 Lighthouse 上部署 SmartAlbum

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取服务器 IP
SERVER_IP=$(curl -s http://metadata.tencentyun.com/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}')

echo "=========================================="
echo "  SmartAlbum 部署脚本"
echo "=========================================="
echo ""

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[错误] Docker 未安装${NC}"
    echo "请先运行 install-docker.sh 安装 Docker"
    exit 1
fi

# 检查是否在项目目录
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}[错误] 未找到 docker-compose.yml${NC}"
    echo "请在 SmartAlbum 项目根目录运行此脚本"
    exit 1
fi

echo -e "${GREEN}服务器 IP: ${SERVER_IP}${NC}"
echo ""

# 创建必要的目录
echo "[1/5] 创建数据目录..."
mkdir -p data storage/originals storage/thumbnails

# 检查 .env 文件
if [ ! -f "backend/.env" ]; then
    echo -e "${YELLOW}[警告] 未找到 backend/.env 文件${NC}"
    echo "请复制 backend/.env.example 到 backend/.env 并配置 API 密钥"
    echo ""
    echo "示例命令："
    echo "  cp backend/.env.example backend/.env"
    echo "  nano backend/.env"
    echo ""
    exit 1
fi

# 停止旧容器
echo "[2/5] 停止旧容器..."
docker compose down 2>/dev/null || true

# 构建镜像
echo "[3/5] 构建 Docker 镜像..."
docker compose build --no-cache

# 启动服务
echo "[4/5] 启动服务..."
docker compose up -d

# 等待服务启动
echo "[5/5] 等待服务启动..."
sleep 5

# 检查服务状态
echo ""
echo "检查服务状态..."
docker compose ps

echo ""
echo "=========================================="
echo -e "${GREEN}  部署完成！${NC}"
echo "=========================================="
echo ""
echo "访问地址："
echo "  前端页面: http://${SERVER_IP}:5173"
echo "  后端 API: http://${SERVER_IP}:9000"
echo "  API 文档: http://${SERVER_IP}:9000/docs"
echo ""
echo "常用命令："
echo "  查看日志: docker compose logs -f"
echo "  停止服务: docker compose down"
echo "  重启服务: docker compose restart"
echo ""
echo "数据存储位置："
echo "  数据库: ./data/"
echo "  照片文件: ./storage/"
echo ""
