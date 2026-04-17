#!/bin/bash
# SmartAlbum 数据迁移脚本
# 功能: 从 Docker 容器导出数据，导入到裸机部署
# 支持: SQLite数据库、ChromaDB向量、照片存储文件

set -euo pipefail

# =============================================================================
# 配置
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/smartalbum/migrate-data-$TIMESTAMP.log"

# 源配置（Docker环境）
DOCKER_DATA_DIR="${DOCKER_DATA_DIR:-./data}"
DOCKER_STORAGE_DIR="${DOCKER_STORAGE_DIR:-./storage}"

# 目标配置（裸机环境）
BARE_METAL_DIR="${BARE_METAL_DIR:-/opt/smartalbum}"
BARE_METAL_DATA="$BARE_METAL_DIR/data"
BARE_METAL_STORAGE="$BARE_METAL_DIR/storage"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# 日志函数
# =============================================================================
init_logging() {
    mkdir -p "$(dirname $LOG_FILE)"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }

# =============================================================================
# 数据库迁移
# =============================================================================
migrate_database() {
    info "=== 数据库迁移 ==="
    
    local source_db=""
    local target_db="$BARE_METAL_DATA/smartalbum.db"
    
    # 检测数据源
    if docker ps --format "{{.Names}}" | grep -q "smartalbum.*backend"; then
        log "从 Docker 容器导出数据库..."
        local container=$(docker ps --format "{{.Names}}" | grep "smartalbum.*backend" | head -1)
        
        # 创建临时目录
        local tmp_dir="/tmp/smartalbum_db_export_$TIMESTAMP"
        mkdir -p "$tmp_dir"
        
        # 从容器复制数据库
        docker cp "$container:/app/data/smartalbum.db" "$tmp_dir/smartalbum.db" 2>/dev/null || {
            # 尝试从卷复制
            local data_volume=$(docker volume ls --format "{{.Name}}" | grep -E "smartalbum.*data" | head -1)
            if [ -n "$data_volume" ]; then
                docker run --rm -v "$data_volume":/data -v "$tmp_dir":/export alpine cp /data/smartalbum.db /export/ 2>/dev/null || true
            fi
        }
        
        if [ -f "$tmp_dir/smartalbum.db" ]; then
            source_db="$tmp_dir/smartalbum.db"
        fi
    elif [ -f "$DOCKER_DATA_DIR/smartalbum.db" ]; then
        log "从本地目录复制数据库..."
        source_db="$DOCKER_DATA_DIR/smartalbum.db"
    fi
    
    if [ -z "$source_db" ] || [ ! -f "$source_db" ]; then
        error "找不到源数据库文件"
        return 1
    fi
    
    log "源数据库: $source_db"
    log "目标数据库: $target_db"
    
    # 确保目标目录存在
    mkdir -p "$(dirname $target_db)"
    
    # 验证源数据库完整性
    log "验证源数据库完整性..."
    if sqlite3 "$source_db" "PRAGMA integrity_check;" | grep -q "ok"; then
        log "  ✓ 源数据库完整性正常"
    else
        error "源数据库完整性检查失败"
        return 1
    fi
    
    # 备份目标数据库（如果存在）
    if [ -f "$target_db" ]; then
        local backup_db="${target_db}.backup.$TIMESTAMP"
        cp "$target_db" "$backup_db"
        log "  ✓ 目标数据库已备份: $backup_db"
    fi
    
    # 复制数据库
    log "复制数据库..."
    cp "$source_db" "$target_db"
    
    # 验证目标数据库
    log "验证目标数据库..."
    if sqlite3 "$target_db" "PRAGMA integrity_check;" | grep -q "ok"; then
        log "  ✓ 目标数据库完整性正常"
    else
        error "目标数据库复制失败"
        return 1
    fi
    
    # 统计信息
    local photo_count=$(sqlite3 "$target_db" "SELECT COUNT(*) FROM photos;" 2>/dev/null || echo "0")
    local album_count=$(sqlite3 "$target_db" "SELECT COUNT(*) FROM albums;" 2>/dev/null || echo "0")
    log "  照片数量: $photo_count"
    log "  相册数量: $album_count"
    
    # 清理临时文件
    if [ -d "${source_db%/*}" ] && [[ "${source_db%/*}" == /tmp/* ]]; then
        rm -rf "${source_db%/*}"
    fi
    
    log "数据库迁移完成 ✓"
    return 0
}

# =============================================================================
# 向量数据迁移
# =============================================================================
migrate_vectors() {
    info "=== 向量数据迁移 ==="
    
    local source_chroma=""
    local target_chroma="$BARE_METAL_DATA/chroma"
    
    # 检测数据源
    if docker ps --format "{{.Names}}" | grep -q "smartalbum"; then
        local data_volume=$(docker volume ls --format "{{.Name}}" | grep -E "smartalbum.*data" | head -1)
        if [ -n "$data_volume" ]; then
            log "从 Docker 卷导出向量数据..."
            local tmp_dir="/tmp/smartalbum_chroma_export_$TIMESTAMP"
            mkdir -p "$tmp_dir"
            docker run --rm -v "$data_volume":/data -v "$tmp_dir":/export alpine tar czf /export/chroma.tar.gz -C /data chroma 2>/dev/null || true
            
            if [ -f "$tmp_dir/chroma.tar.gz" ]; then
                source_chroma="$tmp_dir/chroma.tar.gz"
            fi
        fi
    elif [ -d "$DOCKER_DATA_DIR/chroma" ]; then
        log "从本地目录打包向量数据..."
        local tmp_dir="/tmp/smartalbum_chroma_export_$TIMESTAMP"
        mkdir -p "$tmp_dir"
        tar czf "$tmp_dir/chroma.tar.gz" -C "$DOCKER_DATA_DIR" chroma
        source_chroma="$tmp_dir/chroma.tar.gz"
    fi
    
    if [ -z "$source_chroma" ] || [ ! -f "$source_chroma" ]; then
        warn "找不到向量数据，将重新生成"
        return 0
    fi
    
    # 确保目标目录存在
    mkdir -p "$(dirname $target_chroma)"
    
    # 备份现有向量数据
    if [ -d "$target_chroma" ]; then
        local backup_chroma="${target_chroma}.backup.$TIMESTAMP"
        mv "$target_chroma" "$backup_chroma"
        log "  ✓ 现有向量数据已备份"
    fi
    
    # 解压向量数据
    log "解压向量数据..."
    tar xzf "$source_chroma" -C "$(dirname $target_chroma)"
    
    # 验证
    if [ -d "$target_chroma" ]; then
        local chroma_size=$(du -sh "$target_chroma" | cut -f1)
        log "  ✓ 向量数据迁移完成，大小: $chroma_size"
    else
        error "向量数据解压失败"
        return 1
    fi
    
    # 清理临时文件
    rm -rf "${source_chroma%/*}"
    
    return 0
}

# =============================================================================
# 存储文件迁移
# =============================================================================
migrate_storage() {
    info "=== 存储文件迁移 ==="
    
    local source_storage=""
    local migration_method=""
    
    # 检测数据源
    if docker ps --format "{{.Names}}" | grep -q "smartalbum"; then
        local storage_volume=$(docker volume ls --format "{{.Name}}" | grep -E "smartalbum.*storage" | head -1)
        if [ -n "$storage_volume" ]; then
            log "检测到 Docker 存储卷: $storage_volume"
            source_storage="docker:$storage_volume"
            migration_method="volume"
        fi
    elif [ -d "$DOCKER_STORAGE_DIR" ]; then
        log "检测到本地存储目录: $DOCKER_STORAGE_DIR"
        source_storage="$DOCKER_STORAGE_DIR"
        migration_method="local"
    fi
    
    if [ -z "$source_storage" ]; then
        warn "找不到源存储目录"
        return 0
    fi
    
    # 确保目标目录存在
    mkdir -p "$BARE_METAL_STORAGE"
    
    # 统计源文件
    log "统计源文件..."
    local source_count=0
    if [ "$migration_method" = "local" ]; then
        source_count=$(find "$source_storage" -type f 2>/dev/null | wc -l)
    else
        source_count=$(docker run --rm -v "${source_storage#docker:}":/storage alpine find /storage -type f 2>/dev/null | wc -l)
    fi
    log "  源文件数量: $source_count"
    
    if [ "$source_count" -eq 0 ]; then
        warn "源存储目录为空"
        return 0
    fi
    
    # 询问迁移方式
    log "选择迁移方式:"
    log "  1) 直接复制（推荐，小数据量）"
    log "  2) rsync增量同步（推荐，大数据量）"
    log "  3) 后台异步同步（超大文件，不阻塞）"
    
    local choice="${MIGRATE_METHOD:-1}"
    
    case $choice in
        1|copy)
            log "使用直接复制..."
            if [ "$migration_method" = "local" ]; then
                cp -r "$source_storage"/* "$BARE_METAL_STORAGE/"
            else
                local volume="${source_storage#docker:}"
                docker run --rm -v "$volume":/source -v "$BARE_METAL_STORAGE":/target alpine sh -c 'cp -r /source/* /target/' 2>/dev/null || {
                    # 使用 tar 方式
                    docker run --rm -v "$volume":/source alpine tar czf - -C /source . | tar xzf - -C "$BARE_METAL_STORAGE"
                }
            fi
            ;;
        2|rsync)
            log "使用 rsync 增量同步..."
            if ! command -v rsync &> /dev/null; then
                apt-get install -y rsync
            fi
            
            if [ "$migration_method" = "local" ]; then
                rsync -av --progress "$source_storage/" "$BARE_METAL_STORAGE/"
            else
                # 先导出到临时目录
                local tmp_storage="/tmp/smartalbum_storage_export_$TIMESTAMP"
                mkdir -p "$tmp_storage"
                local volume="${source_storage#docker:}"
                docker run --rm -v "$volume":/source -v "$tmp_storage":/target alpine sh -c 'cp -r /source/* /target/' 2>/dev/null || true
                rsync -av --progress "$tmp_storage/" "$BARE_METAL_STORAGE/"
                rm -rf "$tmp_storage"
            fi
            ;;
        3|async)
            log "启动后台异步同步..."
            local sync_log="/var/log/smartalbum/async-sync-$TIMESTAMP.log"
            
            if [ "$migration_method" = "local" ]; then
                nohup rsync -av "$source_storage/" "$BARE_METAL_STORAGE/" > "$sync_log" 2>&1 &
            else
                local volume="${source_storage#docker:}"
                nohup bash -c "docker run --rm -v $volume:/source -v $BARE_METAL_STORAGE:/target alpine sh -c 'cp -r /source/* /target/'" > "$sync_log" 2>&1 &
            fi
            
            local pid=$!
            log "  后台同步进程 PID: $pid"
            log "  日志文件: $sync_log"
            log "  可使用以下命令监控进度:"
            log "    tail -f $sync_log"
            log "    ps aux | grep $pid"
            
            # 不等待完成，直接返回
            return 0
            ;;
        *)
            error "未知的迁移方式: $choice"
            return 1
            ;;
    esac
    
    # 验证迁移结果
    log "验证迁移结果..."
    local target_count=$(find "$BARE_METAL_STORAGE" -type f 2>/dev/null | wc -l)
    log "  目标文件数量: $target_count"
    
    if [ "$target_count" -eq "$source_count" ]; then
        log "  ✓ 文件数量匹配"
    elif [ "$target_count" -lt "$source_count" ]; then
        warn "  文件数量不匹配: 源=$source_count, 目标=$target_count"
    else
        log "  ✓ 目标文件数量 >= 源文件数量"
    fi
    
    # 抽样验证
    log "抽样验证文件完整性..."
    local sample_files=$(find "$BARE_METAL_STORAGE" -type f 2>/dev/null | head -5)
    for file in $sample_files; do
        if [ -f "$file" ] && [ -s "$file" ]; then
            log "  ✓ $(basename $file): $(du -h $file | cut -f1)"
        else
            error "  ✗ $(basename $file): 文件异常"
        fi
    done
    
    log "存储文件迁移完成 ✓"
    return 0
}

# =============================================================================
# 配置迁移
# =============================================================================
migrate_config() {
    info "=== 配置迁移 ==="
    
    local source_env=""
    local target_env="$BARE_METAL_DIR/backend/.env"
    
    # 检测源配置
    if docker ps --format "{{.Names}}" | grep -q "smartalbum.*backend"; then
        local container=$(docker ps --format "{{.Names}}" | grep "smartalbum.*backend" | head -1)
        local tmp_env="/tmp/smartalbum_env_$TIMESTAMP"
        docker cp "$container:/app/.env" "$tmp_env" 2>/dev/null && source_env="$tmp_env"
    elif [ -f "$DOCKER_DATA_DIR/../backend/.env" ]; then
        source_env="$DOCKER_DATA_DIR/../backend/.env"
    elif [ -f "./backend/.env" ]; then
        source_env="./backend/.env"
    fi
    
    if [ -z "$source_env" ] || [ ! -f "$source_env" ]; then
        warn "找不到源配置文件，将创建默认配置"
        return 0
    fi
    
    log "源配置: $source_env"
    log "目标配置: $target_env"
    
    # 确保目标目录存在
    mkdir -p "$(dirname $target_env)"
    
    # 读取源配置并更新路径
    log "迁移配置..."
    
    # 创建新的配置文件，更新路径
    cat "$source_env" | sed \
        -e "s|/app/data|$BARE_METAL_DATA|g" \
        -e "s|/app/storage|$BARE_METAL_STORAGE|g" \
        -e "s|DATABASE_URL=.*|DATABASE_URL=sqlite+aiosqlite:///$BARE_METAL_DATA/smartalbum.db|g" \
        -e "s|STORAGE_PATH=.*|STORAGE_PATH=$BARE_METAL_STORAGE|g" \
        -e "s|REDIS_URL=.*|REDIS_URL=redis://localhost:6379/1|g" \
        > "$target_env"
    
    # 确保生产环境配置
    sed -i 's/ENVIRONMENT=.*/ENVIRONMENT=production/' "$target_env"
    sed -i 's/DEBUG=.*/DEBUG=false/' "$target_env"
    
    # 设置权限
    chmod 600 "$target_env"
    chown "$APP_USER:$APP_USER" "$target_env" 2>/dev/null || true
    
    log "  ✓ 配置迁移完成"
    log "  请检查并更新以下配置项:"
    grep -E "^(SECRET_KEY|DEFAULT_PASSWORD|AI_API_KEY|CORS_ORIGINS)=" "$target_env" | sed 's/^/    /'
    
    # 清理临时文件
    if [ -f "${source_env%/*}/.env" ] && [[ "${source_env%/*}" == /tmp/* ]]; then
        rm -f "$source_env"
    fi
    
    return 0
}

# =============================================================================
# 权限修复
# =============================================================================
fix_permissions() {
    info "=== 修复权限 ==="
    
    log "设置目录权限..."
    chown -R "$APP_USER:$APP_USER" "$BARE_METAL_DIR" 2>/dev/null || {
        warn "无法更改所有者，请确保当前用户有权访问"
    }
    
    chmod 755 "$BARE_METAL_DIR"
    chmod 750 "$BARE_METAL_DATA"
    chmod 750 "$BARE_METAL_STORAGE"
    chmod 600 "$BARE_METAL_DIR/backend/.env" 2>/dev/null || true
    
    log "  ✓ 权限设置完成"
    
    # 显示最终权限
    log "目录权限:"
    ls -ld "$BARE_METAL_DIR"
    ls -ld "$BARE_METAL_DATA"
    ls -ld "$BARE_METAL_STORAGE"
}

# =============================================================================
# 验证迁移
# =============================================================================
verify_migration() {
    info "=== 验证迁移 ==="
    
    local errors=0
    
    # 验证数据库
    log "验证数据库..."
    if [ -f "$BARE_METAL_DATA/smartalbum.db" ]; then
        if sqlite3 "$BARE_METAL_DATA/smartalbum.db" "PRAGMA integrity_check;" | grep -q "ok"; then
            log "  ✓ 数据库完整性正常"
        else
            error "  ✗ 数据库完整性检查失败"
            errors=$((errors + 1))
        fi
    else
        error "  ✗ 数据库文件不存在"
        errors=$((errors + 1))
    fi
    
    # 验证向量数据
    log "验证向量数据..."
    if [ -d "$BARE_METAL_DATA/chroma" ]; then
        local chroma_files=$(find "$BARE_METAL_DATA/chroma" -type f | wc -l)
        log "  ✓ ChromaDB 数据存在 ($chroma_files 个文件)"
    else
        warn "  ⚠ ChromaDB 数据不存在"
    fi
    
    # 验证存储
    log "验证存储目录..."
    if [ -d "$BARE_METAL_STORAGE/originals" ]; then
        local photo_count=$(find "$BARE_METAL_STORAGE/originals" -type f | wc -l)
        log "  ✓ 照片存储存在 ($photo_count 张照片)"
    else
        warn "  ⚠ 照片存储目录不存在"
    fi
    
    # 验证配置
    log "验证配置文件..."
    if [ -f "$BARE_METAL_DIR/backend/.env" ]; then
        log "  ✓ 配置文件存在"
    else
        error "  ✗ 配置文件不存在"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log "验证通过 ✓"
        return 0
    else
        error "验证失败，发现 $errors 个错误"
        return 1
    fi
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    init_logging
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  SmartAlbum 数据迁移工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 检查权限
    if [ "$EUID" -ne 0 ]; then
        warn "建议以 root 运行以确保权限正确"
    fi
    
    # 检测源环境
    info "检测源环境..."
    if docker ps --format "{{.Names}}" | grep -q "smartalbum"; then
        log "  ✓ 检测到 Docker 容器环境"
    elif [ -d "$DOCKER_DATA_DIR" ] || [ -d "$DOCKER_STORAGE_DIR" ]; then
        log "  ✓ 检测到本地数据目录"
    else
        error "找不到源数据"
        exit 1
    fi
    
    # 执行迁移
    migrate_database || exit 1
    migrate_vectors
    migrate_storage
    migrate_config
    fix_permissions
    verify_migration
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  数据迁移完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "日志文件: $LOG_FILE"
    echo ""
    echo "下一步:"
    echo "  1. 检查配置文件: $BARE_METAL_DIR/backend/.env"
    echo "  2. 运行部署脚本: ./scripts/deploy/bare-metal-upgrade.sh"
    echo ""
}

# 处理命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "SmartAlbum 数据迁移脚本"
            echo ""
            echo "用法: sudo $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --help, -h              显示帮助"
            echo "  --method METHOD         迁移方式 (copy/rsync/async)"
            echo "  --source-dir DIR        源数据目录"
            echo "  --target-dir DIR        目标目录"
            echo ""
            echo "环境变量:"
            echo "  DOCKER_DATA_DIR         Docker 数据目录 (默认: ./data)"
            echo "  DOCKER_STORAGE_DIR      Docker 存储目录 (默认: ./storage)"
            echo "  BARE_METAL_DIR          裸机部署目录 (默认: /opt/smartalbum)"
            echo "  APP_USER                应用用户 (默认: ubuntu)"
            exit 0
            ;;
        --method)
            MIGRATE_METHOD="$2"
            shift 2
            ;;
        --source-dir)
            DOCKER_DATA_DIR="$2"
            DOCKER_STORAGE_DIR="$2"
            shift 2
            ;;
        --target-dir)
            BARE_METAL_DIR="$2"
            BARE_METAL_DATA="$2/data"
            BARE_METAL_STORAGE="$2/storage"
            shift 2
            ;;
        *)
            error "未知选项: $1"
            exit 1
            ;;
    esac
done

# 设置默认值
APP_USER="${APP_USER:-ubuntu}"

# 运行主函数
main
