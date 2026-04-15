#!/bin/bash
# 配置 Docker 国内镜像加速器

echo "[INFO] 配置 Docker 镜像加速器..."

# 创建 docker 配置目录
sudo mkdir -p /etc/docker

# 配置腾讯云镜像加速器（适合腾讯云服务器）
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
EOF

# 重启 Docker 服务
echo "[INFO] 重启 Docker 服务..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# 验证配置
echo "[INFO] 验证配置..."
sudo docker info | grep -A 10 "Registry Mirrors"

echo "[OK] Docker 镜像加速器配置完成"
echo "[INFO] 现在可以重新执行部署命令"
