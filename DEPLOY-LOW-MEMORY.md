# SmartAlbum 低内存服务器部署指南

针对内存不足 4GB 的轻量服务器（如腾讯云 Lighthouse 2GB/4GB 配置）的优化部署方案。

## 问题说明

在内存较小的服务器上部署 Docker 应用时，常遇到以下问题：
- 构建镜像时内存不足（OOM）
- 编译 dlib 等依赖时进程被杀
- 多个服务并行构建导致系统卡死

## 解决方案

本方案通过以下方式解决内存不足问题：

1. **Swap 交换空间** - 自动创建 2-4GB swap 扩展可用内存
2. **分步构建** - 逐个构建服务，避免同时构建多个容器
3. **内存限制** - 为每个容器设置内存上限
4. **构建优化** - 使用 `--no-cache-dir` 等参数减少构建内存使用

## 快速开始

### 1. 上传到服务器并解压

```bash
scp smartalbum.tar.gz ubuntu@<服务器IP>:~/
ssh ubuntu@<服务器IP>

sudo mkdir -p /opt/smartalbum
sudo chown ubuntu:ubuntu /opt/smartalbum
tar -xzvf ~/smartalbum.tar.gz -C /opt/smartalbum
cd /opt/smartalbum
```

### 2. 配置环境变量

```bash
cp .env.example .env
vim .env
```

填入必要的配置（AI_API_KEY 等）。

### 3. 使用低内存部署脚本

```bash
chmod +x deploy-low-memory.sh
./deploy-low-memory.sh deploy
```

脚本会自动：
- 检查并创建 Swap 空间
- 分步构建后端和前端镜像
- 清理缓存释放内存
- 启动服务

### 4. 查看部署状态

```bash
./deploy-low-memory.sh logs    # 查看日志
./deploy-low-memory.sh clean   # 清理缓存
```

## 手动部署（如果脚本失败）

### 步骤 1：创建 Swap

```bash
# 创建 4GB swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 验证
free -h
```

### 步骤 2：清理内存

```bash
# 清理 Docker 缓存
docker system prune -f

# 清理系统缓存
echo 3 | sudo tee /proc/sys/vm/drop_caches
```

### 步骤 3：分步构建

```bash
# 先构建后端
docker compose -f docker-compose.low-memory.yml build backend

# 清理缓存
docker system prune -f

# 再构建前端
docker compose -f docker-compose.low-memory.yml build frontend
```

### 步骤 4：启动服务

```bash
docker compose -f docker-compose.low-memory.yml up -d
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `deploy-low-memory.sh` | 低内存部署脚本，自动配置 swap 和分步构建 |
| `docker-compose.low-memory.yml` | 低内存优化的 compose 配置，限制容器内存 |
| `backend/Dockerfile.low-memory` | 后端低内存 Dockerfile |
| `frontend/Dockerfile.low-memory` | 前端低内存 Dockerfile |

## 内存配置建议

| 服务器内存 | Swap 大小 | 构建策略 |
|------------|-----------|----------|
| 2GB | 4GB | 必须分步构建，一次只构建一个服务 |
| 4GB | 2GB | 建议分步构建 |
| 8GB+ | 1GB | 可使用标准部署脚本 |

## 故障排除

### 构建时仍然 OOM

1. 增加更多 swap：
```bash
sudo swapoff /swapfile
sudo fallocate -l 8G /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

2. 完全手动构建，每次只构建一个服务：
```bash
docker build -t smartalbum-backend ./backend
# 清理后再构建下一个
docker build -t smartalbum-frontend ./frontend
```

### 服务启动后内存不足

检查容器内存限制：
```bash
docker stats
```

如果某个容器内存使用过高，可以调整 `docker-compose.low-memory.yml` 中的 `memory` 限制。

### 构建非常慢

低内存服务器构建确实会慢，这是正常现象。Swap 虽然解决了内存问题，但磁盘 I/O 比内存慢很多。

建议：
- 耐心等待构建完成
- 不要在构建时运行其他程序
- 可以考虑在本地构建镜像后推送到镜像仓库

## 本地构建后推送（高级）

如果服务器内存实在太小，可以在本地构建后上传：

```bash
# 在本地（内存充足的机器）构建
docker build -t smartalbum-backend ./backend
docker build -t smartalbum-frontend ./frontend

# 保存为 tar 文件
docker save smartalbum-backend > backend.tar
docker save smartalbum-frontend > frontend.tar

# 上传到服务器
scp backend.tar frontend.tar ubuntu@<服务器IP>:/opt/smartalbum/

# 在服务器上加载
ssh ubuntu@<服务器IP>
cd /opt/smartalbum
docker load < backend.tar
docker load < frontend.tar

# 启动服务
docker compose -f docker-compose.low-memory.yml up -d
```

## 访问应用

部署完成后访问：
```
http://<服务器IP>
```

## 常用命令

```bash
# 查看内存使用情况
free -h

# 查看容器资源使用
docker stats

# 重启服务
./deploy-low-memory.sh stop
./deploy-low-memory.sh start

# 查看日志
./deploy-low-memory.sh logs

# 更新（重新构建并部署）
./deploy-low-memory.sh deploy
```
