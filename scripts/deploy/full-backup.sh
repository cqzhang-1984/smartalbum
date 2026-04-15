#!/bin/bash
# SmartAlbum 全量备份脚本
# 执行时间：部署前1天
# 执行时长：预计 2-6小时（取决于数据量）

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE="/opt/backups"
BACKUP_DIR="$BACKUP_BASE/smartalbum_$TIMESTAMP"
RETENTION_DAYS=30

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# 创建备份目录
mkdir -p $BACKUP_DIR/{database,vectors,storage,config,code}

log "=== SmartAlbum 全量备份开始 ==="
log "备份目录: $BACKUP_DIR"

# 1. 数据库备份
log "[1/7] 备份数据库..."
if [ -f "data/smartalbum.db" ]; then
    cp data/smartalbum.db $BACKUP_DIR/database/
    sqlite3 data/smartalbum.db ".backup '$BACKUP_DIR/database/smartalbum_backup.db'"
    sqlite3 data/smartalbum.db "PRAGMA integrity_check;" > /dev/null && log "  ✓ 数据库完整性检查通过"
else
    warn "  数据库文件不存在"
fi

# 2. 向量数据备份
log "[2/7] 备份向量数据..."
if [ -d "data/chroma" ]; then
    tar czf $BACKUP_DIR/vectors/chroma_$TIMESTAMP.tar.gz data/chroma/
    log "  ✓ ChromaDB 已备份"
fi
if [ -f "data/vectors.json" ]; then
    cp data/vectors.json $BACKUP_DIR/vectors/
    log "  ✓ 向量 JSON 已备份"
fi

# 3. 存储文件备份（仅索引，完整备份可能太大）
log "[3/7] 备份存储文件索引..."
find storage -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \) > $BACKUP_DIR/storage/file_index.txt 2>/dev/null || true
FILE_COUNT=$(wc -l < $BACKUP_DIR/storage/file_index.txt 2>/dev/null || echo 0)
log "  ✓ 已记录 $FILE_COUNT 个文件"

# 可选：完整备份（如果存储小于10GB）
STORAGE_SIZE=$(du -sb storage/ 2>/dev/null | cut -f1)
if [ "$STORAGE_SIZE" -lt 10737418240 ]; then
    log "  存储较小，执行完整备份..."
    tar czf $BACKUP_DIR/storage/full_storage_$TIMESTAMP.tar.gz storage/
fi

# 4. 配置文件备份
log "[4/7] 备份配置文件..."
cp backend/.env $BACKUP_DIR/config/ 2>/dev/null || warn "  .env 文件不存在"
cp backend/.env.example $BACKUP_DIR/config/ 2>/dev/null || true
cp docker-compose*.yml $BACKUP_DIR/config/
cp -r nginx $BACKUP_DIR/config/ 2>/dev/null || true
log "  ✓ 配置已备份"

# 5. 代码备份
log "[5/7] 备份代码..."
git rev-parse HEAD > $BACKUP_DIR/code/version.txt 2>/dev/null || echo "unknown" > $BACKUP_DIR/code/version.txt
git describe --tags --always 2>/dev/null > $BACKUP_DIR/code/tag.txt || true
tar czf $BACKUP_DIR/code/source_$TIMESTAMP.tar.gz \
    --exclude='venv' --exclude='node_modules' --exclude='__pycache__' \
    --exclude='storage/originals/*' --exclude='data/*.db' \
    .
log "  ✓ 代码已备份"

# 6. 生成校验和
log "[6/7] 生成校验和..."
cd $BACKUP_DIR && find . -type f -exec md5sum {} \; > checksums.md5
md5sum -c checksums.md5 > checksums_verify.log 2>&1 && log "  ✓ 校验和验证通过"

# 7. 生成备份报告
log "[7/7] 生成备份报告..."
cat > $BACKUP_DIR/BACKUP_REPORT.txt <<EOF
SmartAlbum 备份报告
====================

备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份路径: $BACKUP_DIR
服务器: $(hostname)
操作者: $(whoami)

备份内容:
$(du -sh $BACKUP_DIR/* 2>/dev/null)

数据库状态:
$(sqlite3 data/smartalbum.db "SELECT COUNT(*) FROM photos;" 2>/dev/null || echo "N/A") 张照片
$(sqlite3 data/smartalbum.db "SELECT COUNT(*) FROM albums;" 2>/dev/null || echo "N/A") 个相册

Git版本:
$(git log --oneline -1 2>/dev/null || echo "N/A")

恢复命令:
  # 数据库恢复
  cp $BACKUP_DIR/database/smartalbum.db data/
  
  # 向量数据恢复
  tar xzf $BACKUP_DIR/vectors/chroma_$TIMESTAMP.tar.gz
  
  # 完整恢复
  ./scripts/deploy/restore.sh $BACKUP_DIR

EOF

# 压缩备份
log "压缩备份文件..."
cd $BACKUP_BASE
tar czf smartalbum_$TIMESTAMP.tar.gz smartalbum_$TIMESTAMP/
rm -rf smartalbum_$TIMESTAMP/

BACKUP_SIZE=$(du -h smartalbum_$TIMESTAMP.tar.gz | cut -f1)
log "=== 备份完成 ==="
log "备份文件: $BACKUP_BASE/smartalbum_$TIMESTAMP.tar.gz"
log "备份大小: $BACKUP_SIZE"

# 清理旧备份
log "清理 $RETENTION_DAYS 天前的备份..."
find $BACKUP_BASE -name "smartalbum_*.tar.gz" -mtime +$RETENTION_DAYS -delete

log "备份流程结束"
