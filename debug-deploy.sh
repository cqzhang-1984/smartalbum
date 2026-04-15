#!/bin/bash
# SmartAlbum 部署问题诊断脚本

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

get_docker_compose() {
    if docker compose version &>/dev/null; then
        echo "docker compose -f docker-compose.low-memory.yml"
    else
        echo "docker-compose -f docker-compose.low-memory.yml"
    fi
}

echo "=========================================="
echo "SmartAlbum 部署问题诊断"
echo "=========================================="
echo ""

# 1. 检查容器状态
print_info "1. 检查容器运行状态..."
echo "----------------------------------------"
docker ps -a
echo ""

# 2. 检查端口占用
print_info "2. 检查端口占用情况..."
echo "----------------------------------------"
print_info "端口 80 (前端):"
netstat -tlnp 2>/dev/null | grep :80 || ss -tlnp | grep :80 || echo "  未检测到监听"
echo ""

print_info "端口 9000 (后端):"
netstat -tlnp 2>/dev/null | grep :9000 || ss -tlnp | grep :9000 || echo "  未检测到监听"
echo ""

# 3. 查看容器日志
print_info "3. 查看后端容器日志（最近50行）..."
echo "----------------------------------------"
docker logs --tail=50 smartalbum-backend 2>&1 || print_error "无法获取后端日志"
echo ""

print_info "4. 查看前端容器日志（最近20行）..."
echo "----------------------------------------"
docker logs --tail=20 smartalbum-frontend 2>&1 || print_error "无法获取前端日志"
echo ""

print_info "5. 查看 Redis 容器日志..."
echo "----------------------------------------"
docker logs --tail=20 smartalbum-redis 2>&1 || print_error "无法获取 Redis 日志"
echo ""

# 4. 检查 Docker 网络
print_info "6. 检查 Docker 网络..."
echo "----------------------------------------"
docker network ls
echo ""
docker inspect smartalbum-network 2>/dev/null | grep -A 20 "Containers" || echo "网络信息获取失败"
echo ""

# 5. 检查资源使用
print_info "7. 系统资源使用情况..."
echo "----------------------------------------"
print_info "内存:"
free -h
echo ""
print_info "磁盘:"
df -h /
echo ""

# 6. 测试连接
print_info "8. 网络连通性测试..."
echo "----------------------------------------"

# 测试后端容器内部
print_info "测试后端容器内部健康检查..."
docker exec smartalbum-backend python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:9000/api/health').read())" 2>&1 || print_error "后端内部测试失败"
echo ""

# 7. 检查环境变量
print_info "9. 检查后端环境变量..."
echo "----------------------------------------"
docker exec smartalbum-backend env | grep -E "(DATABASE|STORAGE|REDIS)" 2>&1 || print_warning "无法获取环境变量"
echo ""

# 8. 检查文件权限
print_info "10. 检查数据目录权限..."
echo "----------------------------------------"
ls -la data/ 2>/dev/null || print_error "data 目录不存在"
ls -la storage/ 2>/dev/null || print_error "storage 目录不存在"
echo ""

echo "=========================================="
echo "诊断完成"
echo "=========================================="
