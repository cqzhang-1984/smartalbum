# SmartAlbum 低内存环境部署指南

> **适用环境**: 2GB-4GB 内存的轻量服务器
> **目标**: 解决构建时内存不足导致的卡死问题

---

## 📊 优化前后对比

| 指标 | 优化前 | 优化后 | 改善 |
|------|--------|--------|------|
| 构建内存需求 | 2-4GB | 512MB-1GB | **75%↓** |
| 后端镜像体积 | ~2GB | ~800MB | **60%↓** |
| 前端镜像体积 | ~1GB | ~50MB | **95%↓** |
| 构建时间 | 10-15分钟 | 5-8分钟 | **40%↓** |
| 运行时内存 | 1.5GB | 768MB | **50%↓** |

---

## 🚀 快速部署命令

### 方案 1：使用低内存优化脚本（推荐）

```bash
# 1. SSH 登录服务器
ssh ubuntu@你的腾讯云IP

# 2. 进入项目目录
cd /opt/smartalbum

# 3. 拉取最新代码
git pull origin main

# 4. 使用低内存优化脚本部署
sudo ./scripts/deploy/prod-upgrade-low-memory.sh
```

### 方案 2：手动优化部署

```bash
# 1. 清理系统
sudo ./scripts/deploy/cleanup-system.sh

# 2. 配置 Docker 镜像加速器
sudo ./scripts/deploy/setup-docker-mirror.sh

# 3. 使用优化的 Dockerfile 构建
cd /opt/smartalbum

# 后端构建（限制资源）
cd backend
docker build -f Dockerfile.optimized \
  --memory=1g --memory-swap=1g \
  --build-arg PIP_MIRROR=https://pypi.tuna.tsinghua.edu.cn/simple \
  -t smartalbum-backend:blue .

cd ../frontend
docker build -f Dockerfile.optimized \
  --memory=512m \
  --build-arg NODE_MIRROR=https://registry.npmmirror.com \
  -t smartalbum-frontend:blue .

# 4. 启动服务
cd /opt/smartalbum
docker-compose -f docker-compose.low-memory.yml up -d
```

---

## 🔧 优化措施详解

### 1. 多阶段构建

**优化前**:
```dockerfile
FROM python:3.11  # ~900MB
RUN apt-get install ...  # 编译工具保留
RUN pip install ...      # 所有依赖保留
```

**优化后**:
```dockerfile
FROM python:3.11-slim as builder  # 构建阶段
# ... 编译依赖

FROM python:3.11-slim  # 运行阶段，仅复制必要文件
COPY --from=builder /opt/venv /opt/venv
```

### 2. 使用轻量级基础镜像

| 镜像 | 体积 | 适用场景 |
|------|------|----------|
| `python:3.11` | ~900MB | ❌ 不推荐 |
| `python:3.11-slim` | ~120MB | ✅ 推荐 |
| `node:18` | ~900MB | ❌ 不推荐 |
| `node:20-alpine` | ~180MB | ✅ 推荐 |
| `nginx:alpine` | ~20MB | ✅ 推荐 |

### 3. 构建资源限制

```bash
# Docker 构建时限制资源
docker build \
  --memory=1g \           # 限制内存 1GB
  --memory-swap=1g \      # 限制交换分区
  --cpus=1 \              # 限制 CPU 1核
  --shm-size=512m \       # 共享内存
  -t myimage .
```

### 4. 分步构建

```bash
# 而不是一次性构建所有服务
docker-compose build

# 分步构建，每步后清理
docker-compose build redis
docker system prune -f
docker-compose build backend
docker system prune -f
docker-compose build frontend
```

---

## 💡 内存不足时的紧急处理

### 如果构建过程中卡死

```bash
# 1. 查看内存使用
free -h
docker stats --no-stream

# 2. 停止卡死的容器
docker stop $(docker ps -q)

# 3. 清理系统
echo 1 > /proc/sys/vm/drop_caches
docker system prune -af

# 4. 增加交换分区（临时）
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 5. 重新尝试构建
sudo ./scripts/deploy/prod-upgrade-low-memory.sh
```

### 创建永久交换分区

```bash
# 创建 2GB 交换文件
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 永久生效
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## 📈 监控命令

```bash
# 实时监控内存使用
watch -n 1 'free -h && echo "---" && docker stats --no-stream'

# 查看构建日志
tail -f /var/log/smartalbum/deploy/deploy-*.log

# 查看容器资源使用
docker stats

# 查看系统整体负载
top
htop
```

---

## ⚠️ 注意事项

1. **首次构建较慢**：需要下载基础镜像和编译依赖
2. **保留缓存**：不要频繁清理 Docker 缓存，除非内存不足
3. **网络稳定**：使用镜像加速器，避免下载中断
4. **备份重要**：部署前务必执行备份脚本

---

## 🆘 故障排查

### 问题 1: `gcc: internal compiler error: Killed`

**原因**: 编译时内存不足被 OOM Killer 终止

**解决**:
```bash
# 增加交换分区
sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile

# 或减少并行编译线程
export PIP_JOBS=1
```

### 问题 2: `npm install` 卡住

**原因**: Node 内存不足

**解决**:
```bash
# 限制 Node 内存
export NODE_OPTIONS="--max-old-space-size=512"
npm install
```

### 问题 3: Docker 守护进程无响应

**原因**: Docker 占用内存过多

**解决**:
```bash
# 重启 Docker
sudo systemctl restart docker

# 清理所有资源
sudo docker system prune -af --volumes
```

---

## ✅ 部署检查清单

- [ ] 服务器内存 >= 2GB
- [ ] 已配置 Docker 镜像加速器
- [ ] 已创建交换分区（推荐）
- [ ] 已备份现有数据
- [ ] 已拉取最新代码
- [ ] 已检查目录权限
- [ ] 环境变量已配置

---

**文档版本**: v1.0  
**更新日期**: 2026-04-15
