#!/bin/bash
# Docker 镜像加速器配置脚本
# 适用于国内服务器（腾讯云、阿里云等）

set -e

echo "=== 配置 Docker 镜像加速器 ==="

# 创建 Docker 配置目录
mkdir -p /etc/docker

# 配置镜像加速器（使用可用镜像源）
# 注意：部分镜像源可能已失效，这里提供多个备选
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://docker.m.daocloud.io"
  ],
  "dns": ["8.8.8.8", "114.114.114.114"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

# 重启 Docker 服务
echo "重启 Docker 服务..."
systemctl daemon-reload
systemctl restart docker

# 验证配置
echo "验证镜像加速器配置..."
docker info | grep -A 10 "Registry Mirrors"

echo "=== Docker 镜像加速器配置完成 ==="
echo ""
echo "配置的镜像源："
echo "  - 中科大: https://docker.mirrors.ustc.edu.cn"
echo "  - 网易云: https://hub-mirror.c.163.com"
echo "  - 百度云: https://mirror.baidubce.com"
echo "  - DaoCloud: https://docker.m.daocloud.io"
echo "  - DockerProxy: https://dockerproxy.com"
