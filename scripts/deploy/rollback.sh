#!/bin/bash
# SmartAlbum 紧急回滚脚本
# 执行时间：部署失败时
# 执行时长：预计 15-30分钟

set -e

BACKUP_PATH=$1

if [ -z "$BACKUP_PATH" ]; then
    echo "用法: $0 <备份文件路径或目录>"
    echo "示例: $0 /opt/backups/smartalbum_20260115_120000.tar.gz"
    exit 1
fi

echo "╔════════════════════════════════════════════════╗"
echo "║      ⚠️  SmartAlbum 紧急回滚程序               ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "回滚来源: $BACKUP_PATH"
echo ""

# 确认
read -p "⚠️  确定要回滚吗？这将丢失部署后的所有数据！ [y/N] " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "已取消回滚"
    exit 0
fi

echo "[$(date '+%H:%M:%S')] 开始回滚..."

# 解压备份（如果是压缩包）
if [[ $BACKUP_PATH == *.tar.gz ]]; then
    echo "解压备份文件..."
    cd /opt/backups
    tar xzf $BACKUP_PATH
    BACKUP_DIR="/opt/backups/$(basename $BACKUP_PATH .tar.gz)"
else
    BACKUP_DIR=$BACKUP_PATH
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "✗ 备份目录不存在: $BACKUP_DIR"
    exit 1
fi

APP_DIR="/opt/smartalbum"
cd $APP_DIR

# 1. 停止服务
echo "[1/7] 停止当前服务..."
docker-compose down 2>/dev/null || true
pkill -f uvicorn 2>/dev/null || true
pkill -f celery 2>/dev/null || true
sleep 3

# 2. 恢复数据库
echo "[2/7] 恢复数据库..."
if [ -f "$BACKUP_DIR/database/smartalbum.db" ]; then
    cp $BACKUP_DIR/database/smartalbum.db data/
    sqlite3 data/smartalbum.db "PRAGMA integrity_check;" && echo "  ✓ 数据库恢复成功"
fi

# 3. 恢复向量数据
echo "[3/7] 恢复向量数据..."
rm -rf data/chroma 2>/dev/null || true
for file in $BACKUP_DIR/vectors/*.tar.gz; do
    if [ -f "$file" ]; then
        tar xzf $file -C .
        echo "  ✓ 向量数据恢复: $(basename $file)"
    fi
done
if [ -f "$BACKUP_DIR/vectors/vectors.json" ]; then
    cp $BACKUP_DIR/vectors/vectors.json data/
fi

# 4. 恢复配置
echo "[4/7] 恢复配置文件..."
if [ -f "$BACKUP_DIR/config/.env" ]; then
    cp $BACKUP_DIR/config/.env backend/
    echo "  ✓ 环境配置已恢复"
fi

# 5. 恢复代码
echo "[5/7] 恢复代码版本..."
if [ -f "$BACKUP_DIR/code/source_*.tar.gz" ]; then
    # 保留当前.env
    cp backend/.env /tmp/.env.backup
    
    # 解压旧代码
    tar xzf $BACKUP_DIR/code/source_*.tar.gz --exclude='.env'
    
    # 恢复.env
    mv /tmp/.env.backup backend/.env
    
    echo "  ✓ 代码已恢复"
fi

# 6. 启动服务
echo "[6/7] 启动服务..."
docker-compose up -d

# 7. 验证
echo "[7/7] 验证服务..."
sleep 5
if curl -s http://localhost:9999/api/health > /dev/null 2>&1; then
    echo "  ✓ 服务启动成功"
else
    echo "  ✗ 服务可能未正常启动，请检查日志"
    docker-compose logs
fi

# 清理
if [[ $1 == *.tar.gz ]]; then
    rm -rf $BACKUP_DIR
fi

echo ""
echo "✅ 回滚完成！"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "请验证："
echo "  1. 网站可正常访问"
echo "  2. 登录功能正常"
echo "  3. 照片数据完整"
echo ""
