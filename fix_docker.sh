#!/bin/bash
# Docker 权限修复脚本

echo "[INFO] 修复 Docker 权限..."

# 1. 修复 docker-compose 权限
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# 2. 添加当前用户到 docker 组
sudo usermod -aG docker $USER

# 3. 验证安装
echo "[INFO] 验证 Docker 安装..."
docker --version
docker-compose --version

echo "[OK] 权限修复完成"
echo "[INFO] 请重新登录或执行: newgrp docker"
