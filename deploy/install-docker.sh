#!/bin/bash
# SmartAlbum Docker 安装脚本
# 适用于 Ubuntu Server 24.04 LTS

set -e

echo "=========================================="
echo "  SmartAlbum Docker 环境安装脚本"
echo "=========================================="
echo ""

# 更新系统
echo "[1/6] 更新系统软件包..."
sudo apt-get update && sudo apt-get upgrade -y

# 安装必要的依赖
echo "[2/6] 安装必要的依赖..."
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git

# 添加 Docker 官方 GPG 密钥
echo "[3/6] 添加 Docker 官方 GPG 密钥..."
sudo mkdir -p /etc/apt/keyrings

# 如果已存在则删除旧密钥
if [ -f /etc/apt/keyrings/docker.gpg ]; then
    sudo rm -f /etc/apt/keyrings/docker.gpg
fi

# 使用国内镜像或重试机制
echo "正在下载 GPG 密钥..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || \
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 设置 Docker 软件源
echo "[4/6] 设置 Docker 软件源..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装 Docker Engine
echo "[5/6] 安装 Docker Engine..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 启动 Docker 并设置开机自启
echo "[6/6] 启动 Docker 服务..."
sudo systemctl start docker
sudo systemctl enable docker

# 将当前用户添加到 docker 组（可选）
echo ""
echo "[可选] 将当前用户添加到 docker 组..."
sudo usermod -aG docker $USER

echo ""
echo "=========================================="
echo "  Docker 安装完成！"
echo "=========================================="
echo ""
echo "版本信息："
docker --version
docker compose version
echo ""
echo "提示：如果这是第一次安装，请注销并重新登录以应用 docker 组权限。"
echo ""
