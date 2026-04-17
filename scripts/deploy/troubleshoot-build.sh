#!/bin/bash
# SmartAlbum 构建故障排查脚本

set -e

echo "=== SmartAlbum 构建故障排查 ==="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "【1/8】检查系统资源..."
echo "内存状态:"
free -h
echo ""
echo "磁盘状态:"
df -h /
echo ""

echo "【2/8】检查 Docker 状态..."
if docker info &>/dev/null; then
    log "Docker 运行正常"
    docker version --format 'Server Version: {{.Server.Version}}'
else
    error "Docker 未运行"
    exit 1
fi
echo ""

echo "【3/8】检查 Docker 镜像加速器..."
if [ -f /etc/docker/daemon.json ]; then
    log "Docker 配置文件:"
    cat /etc/docker/daemon.json
else
    warn "未配置 Docker 镜像加速器"
fi
echo ""

echo "【4/8】测试镜像拉取..."
log "测试拉取 python:3.11-slim..."
if timeout 60 docker pull python:3.11-slim 2>&1 | tail -5; then
    log "✓ 镜像拉取成功"
else
    error "✗ 镜像拉取失败，检查网络或镜像加速器配置"
fi
echo ""

echo "【5/8】检查构建日志..."
LATEST_LOG=$(ls -t /var/log/smartalbum/deploy/deploy-*.log 2>/dev/null | head -1)
if [ -n "$LATEST_LOG" ]; then
    log "最新日志: $LATEST_LOG"
    echo "最近 50 行日志:"
    tail -50 "$LATEST_LOG" | grep -E "(ERROR|error|fail|FAIL|killed|Killed|OOM|timeout)" || echo "未发现明显错误"
else
    warn "未找到部署日志"
fi
echo ""

echo "【6/8】检查系统日志（OOM Killer）..."
if dmesg 2>/dev/null | grep -i "killed process" | tail -5; then
    error "检测到 OOM Killer 杀死了进程！内存不足"
    echo ""
    echo "解决方案:"
    echo "1. 增加交换分区: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
    echo "2. 减少并行构建数: export BUILD_PARALLELISM=1"
    echo "3. 使用更小的基础镜像"
else
    log "未检测到 OOM Killer"
fi
echo ""

echo "【7/8】检查 Docker 构建缓存..."
log "Docker 磁盘使用:"
docker system df
echo ""

echo "【8/8】手动测试构建..."
cd /opt/smartalbum/backend 2>/dev/null || cd backend

log "尝试手动构建（查看详细错误）..."
docker build -f Dockerfile.optimized --no-cache --progress=plain . 2>&1 | tail -100 || true
echo ""

echo "=== 故障排查完成 ==="
echo ""
echo "常见问题及解决方案:"
echo ""
echo "1. 内存不足 (OOM)"
echo "   症状: 构建过程中进程被杀死，日志中有 'killed' 或 'OOM'"
echo "   解决: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
echo ""
echo "2. 网络超时"
echo "   症状: 'timeout', 'i/o timeout', 'Temporary failure in name resolution'"
echo "   解决: 配置 Docker 镜像加速器"
echo ""
echo "3. pip 安装失败"
echo "   症状: 'Could not find a version', 'Connection reset by peer'"
echo "   解决: 更换 pip 镜像源"
echo ""
echo "4. 磁盘空间不足"
echo "   症状: 'no space left on device'"
echo "   解决: docker system prune -af"
echo ""
