#!/bin/bash
# 系统清理脚本 - 用于低内存环境部署前清理

set -e

echo "=== SmartAlbum 系统清理脚本 ==="
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 显示清理前状态
echo "【清理前状态】"
echo "磁盘使用:"
df -h / | tail -1
echo ""
echo "内存使用:"
free -h | grep -E "Mem|Swap"
echo ""
echo "Docker 占用:"
docker system df 2>/dev/null || echo "Docker 未运行"
echo ""

# 1. 清理 Docker 资源
echo "【1/5】清理 Docker 资源..."
if command -v docker &> /dev/null; then
    # 停止所有非运行中的容器
    docker container prune -f 2>/dev/null || true
    
    # 清理未使用的镜像
    docker image prune -af 2>/dev/null || true
    
    # 清理构建缓存
    docker builder prune -f 2>/dev/null || true
    
    # 清理卷
    docker volume prune -f 2>/dev/null || true
    
    # 清理网络
    docker network prune -f 2>/dev/null || true
    
    echo "  ✓ Docker 清理完成"
else
    echo "  ⚠ Docker 未安装"
fi

# 2. 清理系统缓存
echo "【2/5】清理系统缓存..."

# 清理 apt 缓存
if command -v apt-get &> /dev/null; then
    apt-get clean 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    echo "  ✓ apt 缓存清理完成"
fi

# 清理 yum 缓存（CentOS/RHEL）
if command -v yum &> /dev/null; then
    yum clean all 2>/dev/null || true
    echo "  ✓ yum 缓存清理完成"
fi

# 3. 清理日志文件
echo "【3/5】清理日志文件..."

# 清理系统日志
find /var/log -type f -name "*.log.*" -mtime +7 -delete 2>/dev/null || true
find /var/log -type f -name "*.gz" -mtime +30 -delete 2>/dev/null || true

# 清理旧日志（保留最近 5 个）
for logfile in /var/log/syslog /var/log/messages /var/log/auth.log; do
    if [ -f "$logfile" ]; then
        tail -n 1000 "$logfile" > "$logfile.tmp" && mv "$logfile.tmp" "$logfile" 2>/dev/null || true
    fi
done

# 清空 journal 日志
if command -v journalctl &> /dev/null; then
    journalctl --vacuum-time=7d 2>/dev/null || true
    echo "  ✓ journal 日志清理完成"
fi

echo "  ✓ 日志清理完成"

# 4. 清理临时文件
echo "【4/5】清理临时文件..."

# 清理 /tmp
find /tmp -type f -atime +7 -delete 2>/dev/null || true
find /tmp -type d -empty -delete 2>/dev/null || true

# 清理 /var/tmp
find /var/tmp -type f -atime +7 -delete 2>/dev/null || true

# 清理用户缓存
find /home -type f -name "*.cache" -atime +30 -delete 2>/dev/null || true
find /root -type f -name "*.cache" -atime +30 -delete 2>/dev/null || true

echo "  ✓ 临时文件清理完成"

# 5. 清理内存缓存
echo "【5/5】清理内存缓存..."

# 同步文件系统
sync

# 清理页面缓存（需要 root）
if [ "$EUID" -eq 0 ]; then
    echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
    echo "  ✓ 内存缓存清理完成"
else
    echo "  ⚠ 需要 root 权限清理内存缓存"
fi

echo ""
echo "【清理后状态】"
echo "磁盘使用:"
df -h / | tail -1
echo ""
echo "内存使用:"
free -h | grep -E "Mem|Swap"
echo ""

echo "=== 系统清理完成 ==="
echo "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
