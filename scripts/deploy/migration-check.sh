#!/bin/bash
# SmartAlbum 数据迁移检查脚本
# 功能: 验证数据迁移前后的完整性和一致性
# 支持: 数据库迁移、向量数据迁移、存储数据检查

set -euo pipefail

# =============================================================================
# 配置
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="/var/log/smartalbum/migration"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/migration-check-$TIMESTAMP.log"

# 数据库路径
DB_FILE="${DB_FILE:-$PROJECT_ROOT/data/smartalbum.db}"
BACKUP_DB_FILE="${BACKUP_DB_FILE:-}"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查状态
CHECK_STATUS="PASS"
ISSUES=()
WARNINGS=()

# 统计信息
declare -A BEFORE_STATS
declare -A AFTER_STATS

# =============================================================================
# 日志函数
# =============================================================================
init_logging() {
    mkdir -p "$LOG_DIR"
}

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

success() {
    log "${GREEN}✓ $1${NC}"
}

warn() {
    log "${YELLOW}⚠ $1${NC}"
    WARNINGS+=("$1")
}

fail() {
    log "${RED}✗ $1${NC}"
    ISSUES+=("$1")
    CHECK_STATUS="FAIL"
}

info() {
    log "${BLUE}ℹ $1${NC}"
}

section() {
    log ""
    log "${CYAN}========================================${NC}"
    log "${CYAN}  $1${NC}"
    log "${CYAN}========================================${NC}"
    log ""
}

# =============================================================================
# 数据库检查
# =============================================================================
check_database_integrity() {
    local db_path="$1"
    local label="$2"
    
    info "检查 $label 数据库完整性..."
    
    if [ ! -f "$db_path" ]; then
        fail "$label 数据库文件不存在: $db_path"
        return 1
    fi
    
    # 检查文件权限
    if [ ! -r "$db_path" ]; then
        fail "$label 数据库文件不可读"
        return 1
    fi
    
    # 运行PRAGMA integrity_check
    local result=$(sqlite3 "$db_path" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    
    if [ "$result" = "ok" ]; then
        success "$label 数据库完整性检查通过"
    else
        fail "$label 数据库完整性检查失败: $result"
        return 1
    fi
    
    # 获取数据库统计
    local tables=$(sqlite3 "$db_path" ".tables" 2>/dev/null || echo "")
    local table_count=$(echo "$tables" | wc -w)
    local file_size=$(du -h "$db_path" | cut -f1)
    
    info "$label 数据库: $table_count 个表, 大小: $file_size"
    
    return 0
}

gather_db_stats() {
    local db_path="$1"
    local prefix="$2"
    
    if [ ! -f "$db_path" ]; then
        return 1
    fi
    
    # 表记录数统计
    local tables=("photos" "albums" "users" "tags")
    for table in "${tables[@]}"; do
        local count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
        eval "${prefix}_STATS[$table]=$count"
    done
    
    # 数据库大小
    local size=$(stat -c%s "$db_path" 2>/dev/null || stat -f%z "$db_path" 2>/dev/null || echo "0")
    eval "${prefix}_STATS[db_size]=$size"
    
    # 其他统计
    local photo_with_album=$(sqlite3 "$db_path" "SELECT COUNT(DISTINCT album_id) FROM photos WHERE album_id IS NOT NULL;" 2>/dev/null || echo "0")
    eval "${prefix}_STATS[photo_with_album]=$photo_with_album"
}

compare_db_stats() {
    section "数据库统计对比"
    
    local tables=("photos" "albums" "users" "tags")
    local has_diff=false
    
    info "迁移前后数据对比:"
    printf "%-15s %10s %10s %10s\n" "表名" "迁移前" "迁移后" "差异"
    echo "--------------------------------------------------------"
    
    for table in "${tables[@]}"; do
        local before=${BEFORE_STATS[$table]:-0}
        local after=${AFTER_STATS[$table]:-0}
        local diff=$((after - before))
        
        if [ $diff -ne 0 ]; then
            has_diff=true
            printf "${YELLOW}%-15s %10d %10d %+10d${NC}\n" "$table" "$before" "$after" "$diff"
        else
            printf "%-15s %10d %10d %10s\n" "$table" "$before" "$after" "无变化"
        fi
    done
    
    # 检查数据一致性
    if [ "$has_diff" = true ]; then
        warn "检测到数据变化，请确认是否为预期变更"
    else
        success "数据库记录数无变化"
    fi
}

# =============================================================================
# 向量数据检查
# =============================================================================
check_vector_data() {
    section "向量数据检查"
    
    local chroma_dir="$PROJECT_ROOT/data/chroma"
    local vector_json="$PROJECT_ROOT/data/vectors.json"
    
    # 检查ChromaDB
    if [ -d "$chroma_dir" ]; then
        info "检测到 ChromaDB 向量存储"
        local chroma_size=$(du -sh "$chroma_dir" 2>/dev/null | cut -f1)
        local chroma_files=$(find "$chroma_dir" -type f 2>/dev/null | wc -l)
        
        success "ChromaDB 存在: $chroma_size, $chroma_files 个文件"
        
        # 检查关键文件
        local required_files=("chroma.sqlite3")
        for req_file in "${required_files[@]}"; do
            if [ -f "$chroma_dir/$req_file" ]; then
                success "  ✓ $req_file 存在"
            else
                warn "  ⚠ $req_file 不存在"
            fi
        done
    else
        warn "ChromaDB 目录不存在"
    fi
    
    # 检查JSON向量备份
    if [ -f "$vector_json" ]; then
        info "检测到 JSON 向量备份"
        local json_size=$(du -h "$vector_json" | cut -f1)
        local vector_count=$(grep -o '"id"' "$vector_json" 2>/dev/null | wc -l)
        
        success "JSON 向量备份: $json_size, 约 $vector_count 个向量"
    else
        info "未找到 JSON 向量备份"
    fi
}

# =============================================================================
# 存储数据检查
# =============================================================================
check_storage_data() {
    section "存储数据检查"
    
    local storage_dir="$PROJECT_ROOT/storage"
    
    if [ ! -d "$storage_dir" ]; then
        fail "存储目录不存在: $storage_dir"
        return 1
    fi
    
    # 统计文件
    local total_files=$(find "$storage_dir" -type f 2>/dev/null | wc -l)
    local total_size=$(du -sh "$storage_dir" 2>/dev/null | cut -f1)
    
    # 按类型统计
    local image_count=$(find "$storage_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) 2>/dev/null | wc -l)
    local thumb_count=$(find "$storage_dir" -type f -name "*thumb*" 2>/dev/null | wc -l)
    
    info "存储统计:"
    info "  总文件数: $total_files"
    info "  总大小: $total_size"
    info "  图片文件: $image_count"
    info "  缩略图: $thumb_count"
    
    # 检查目录结构
    local expected_dirs=("originals" "thumbnails" "temp")
    for dir in "${expected_dirs[@]}"; do
        if [ -d "$storage_dir/$dir" ]; then
            success "  ✓ 目录 $dir 存在"
        else
            warn "  ⚠ 目录 $dir 不存在"
        fi
    done
    
    # 检查孤立文件
    info "检查孤立文件..."
    check_orphaned_files
    
    return 0
}

check_orphaned_files() {
    local db_path="$DB_FILE"
    local storage_dir="$PROJECT_ROOT/storage"
    
    if [ ! -f "$db_path" ]; then
        return
    fi
    
    # 获取数据库中的文件列表
    local db_files=$(sqlite3 "$db_path" "SELECT file_path FROM photos;" 2>/dev/null || echo "")
    
    # 检查存储中的文件是否都在数据库中
    local orphaned_count=0
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            local filename=$(basename "$file")
            if ! echo "$db_files" | grep -q "$filename"; then
                orphaned_count=$((orphaned_count + 1))
            fi
        fi
    done < <(find "$storage_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null)
    
    if [ $orphaned_count -gt 0 ]; then
        warn "发现 $orphaned_count 个可能的孤立文件"
    else
        success "未发现孤立文件"
    fi
}

# =============================================================================
# 数据一致性验证
# =============================================================================
validate_data_consistency() {
    section "数据一致性验证"
    
    if [ ! -f "$DB_FILE" ]; then
        fail "数据库文件不存在"
        return 1
    fi
    
    info "执行数据一致性检查..."
    
    # 1. 检查照片与相册关联
    local orphan_photos=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM photos WHERE album_id NOT IN (SELECT id FROM albums) AND album_id IS NOT NULL;" 2>/dev/null || echo "0")
    if [ "$orphan_photos" -gt 0 ]; then
        warn "发现 $orphan_photos 张照片关联到不存在的相册"
    else
        success "照片-相册关联一致"
    fi
    
    # 2. 检查文件路径有效性
    local missing_files=0
    while IFS='|' read -r photo_id file_path; do
        if [ -n "$file_path" ]; then
            local full_path="$PROJECT_ROOT/$file_path"
            if [ ! -f "$full_path" ]; then
                missing_files=$((missing_files + 1))
            fi
        fi
    done < <(sqlite3 "$DB_FILE" "SELECT id, file_path FROM photos;" 2>/dev/null || true)
    
    if [ $missing_files -gt 0 ]; then
        warn "发现 $missing_files 张照片文件缺失"
    else
        success "所有照片文件存在"
    fi
    
    # 3. 检查元数据完整性
    local no_metadata=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM photos WHERE ai_description IS NULL AND ai_tags IS NULL;" 2>/dev/null || echo "0")
    local total_photos=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM photos;" 2>/dev/null || echo "0")
    
    if [ "$total_photos" -gt 0 ]; then
        local no_meta_percent=$((no_metadata * 100 / total_photos))
        info "无AI元数据照片: $no_metadata/$total_photos (${no_meta_percent}%)"
    fi
    
    return 0
}

# =============================================================================
# 生成报告
# =============================================================================
generate_report() {
    section "生成检查报告"
    
    local report_file="$LOG_DIR/migration-report-$TIMESTAMP.json"
    
    # 构建JSON报告
    cat > "$report_file" << EOF
{
    "timestamp": "$TIMESTAMP",
    "status": "$CHECK_STATUS",
    "database": {
        "path": "$DB_FILE",
        "stats_before": {
            "photos": ${BEFORE_STATS[photos]:-null},
            "albums": ${BEFORE_STATS[albums]:-null},
            "users": ${BEFORE_STATS[users]:-null}
        },
        "stats_after": {
            "photos": ${AFTER_STATS[photos]:-null},
            "albums": ${AFTER_STATS[albums]:-null},
            "users": ${AFTER_STATS[users]:-null}
        }
    },
    "issues": [$(printf '\"%s\",' "${ISSUES[@]}" | sed 's/,$//')],
    "warnings": [$(printf '\"%s\",' "${WARNINGS[@]}" | sed 's/,$//')]
}
EOF
    
    log "报告已保存: $report_file"
    
    # 生成摘要
    log ""
    log "========================================"
    if [ "$CHECK_STATUS" = "PASS" ]; then
        log "${GREEN}迁移检查通过 ✓${NC}"
    else
        log "${RED}迁移检查发现问题 ✗${NC}"
    fi
    log ""
    log "问题数: ${#ISSUES[@]}"
    log "警告数: ${#WARNINGS[@]}"
    log ""
    if [ ${#ISSUES[@]} -gt 0 ]; then
        log "问题列表:"
        for issue in "${ISSUES[@]}"; do
            log "  - $issue"
        done
    fi
    log "========================================"
    log "详细日志: $LOG_FILE"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    local mode="check"
    local before_db=""
    local after_db="$DB_FILE"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                echo "SmartAlbum 数据迁移检查脚本"
                echo ""
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  --help, -h           显示帮助"
                echo "  --before-db PATH     迁移前的数据库路径"
                echo "  --after-db PATH      迁移后的数据库路径 (默认: data/smartalbum.db)"
                echo "  --compare            对比模式 (需要 --before-db)"
                echo ""
                echo "示例:"
                echo "  # 检查当前数据库"
                echo "  $0"
                echo ""
                echo "  # 对比迁移前后"
                echo "  $0 --compare --before-db /backup/smartalbum.db"
                exit 0
                ;;
            --before-db)
                before_db="$2"
                shift 2
                ;;
            --after-db)
                after_db="$2"
                DB_FILE="$2"
                shift 2
                ;;
            --compare)
                mode="compare"
                shift
                ;;
            *)
                echo "未知选项: $1"
                exit 1
                ;;
        esac
    done
    
    init_logging
    
    section "SmartAlbum 数据迁移检查"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "日志文件: $LOG_FILE"
    log ""
    
    if [ "$mode" = "compare" ]; then
        if [ -z "$before_db" ]; then
            error "对比模式需要指定 --before-db"
            exit 1
        fi
        
        info "对比模式: 迁移前 vs 迁移后"
        info "迁移前数据库: $before_db"
        info "迁移后数据库: $after_db"
        
        check_database_integrity "$before_db" "迁移前" || true
        check_database_integrity "$after_db" "迁移后" || true
        
        gather_db_stats "$before_db" "BEFORE"
        gather_db_stats "$after_db" "AFTER"
        
        compare_db_stats
    else
        # 常规检查模式
        check_database_integrity "$DB_FILE" "当前" || true
        check_vector_data
        check_storage_data
        validate_data_consistency
    fi
    
    generate_report
    
    # 返回状态码
    if [ "$CHECK_STATUS" = "PASS" ]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@"
