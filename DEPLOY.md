# SmartAlbum Docker 部署指南

## 概述

本项目支持 Docker 容器化部署，可一键部署到腾讯云 Lighthouse 服务器。

## 快速开始

### 1. 服务器准备

- **服务器**: 腾讯云 Lighthouse
- **系统**: Ubuntu Server 24.04 LTS 64bit
- **配置**: 2核4G+

### 2. 部署步骤

```bash
# 连接到服务器
ssh ubuntu@<你的服务器IP>

# 克隆代码
cd ~
git clone <仓库地址> SmartAlbum
cd SmartAlbum

# 安装 Docker
chmod +x deploy/install-docker.sh
./deploy/install-docker.sh

# 重新登录以应用权限
exit
ssh ubuntu@<你的服务器IP>

# 配置环境变量
cp backend/.env.example backend/.env
nano backend/.env
# 填入你的豆包 API 密钥

# 执行部署
chmod +x deploy/deploy.sh
./deploy/deploy.sh
```

### 3. 访问应用

部署完成后，通过浏览器访问：
```
http://<服务器IP>:5173
```

## 端口说明

| 端口 | 用途 | 访问地址 |
|------|------|----------|
| 5173 | 前端页面 | http://IP:5173 |
| 9000 | 后端 API | http://IP:9000 |

## 文件说明

| 文件 | 说明 |
|------|------|
| `docker-compose.yml` | Docker 服务编排配置 |
| `backend/Dockerfile` | 后端 Python 环境镜像 |
| `frontend/Dockerfile` | 前端 Node 环境镜像 |
| `deploy/install-docker.sh` | Docker 安装脚本 |
| `deploy/deploy.sh` | 一键部署脚本 |
| `deploy/README.md` | 详细部署文档 |

## 常用命令

```bash
# 查看日志
docker compose logs -f

# 停止服务
docker compose down

# 重启服务
docker compose restart

# 查看状态
docker compose ps
```

## 详细文档

查看 `deploy/README.md` 获取完整的部署指南和故障排查。
