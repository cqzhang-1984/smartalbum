#!/bin/bash
# SmartAlbum 快速回滚脚本
# 功能: 一键回滚到上一版本，支持紧急回滚和计划回滚
# 作者: SmartAlbum DevOps Team
# 版本: 1.0.0

set -euo pipefail

# =============================================================================
# 配置
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="/var/log/smartalbum/deploy"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/rollback-$TIMESTAMP.log"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 状态
ROLLBACK_STATUS="INIT"
BACKUP_PATH=""
EMERGENCY_MODE=false

# =============================================================================
# 日志函数
# =============================================================================
init_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1"
}

section() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

# =============================================================================
# 错误处理
# =============================================================================
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "回滚脚本异常退出 (错误码: $exit_code)"
        error "当前状态: $ROLLBACK_STATUS"
        error "可能需要手动干预!"
        error "日志文件: $LOG_FILE"
    fi
    exit $exit_code
}

trap cleanup_on_error EXIT ERR INT TERM

# =============================================================================
# 显示帮助
# =============================================================================
show_help() {
    cat << 'EOF'
SmartAlbum 快速回滚脚本

用法:
  ./quick-rollback.sh [选项] [备份文件路径]

选项:
  -h, --help              显示此帮助
  -e, --emergency         紧急模式 (跳过确认，最快回滚)
  -l, --list              列出可用的备份文件
  -y, --yes               自动确认 (非紧急模式)
  --stop-only             仅停止当前环境 (用于诊断)

示例:
  # 使用最新备份回滚
  ./quick-rollback.sh

  # 使用指定备份回滚
  ./quick-rollback.sh /opt/backups/smartalbum_20260115_020000.tar.gz

  # 紧急回滚 (跳过确认，最快恢复)
  ./quick-rollback.sh --emergency

  # 列出可用备份
  ./quick-rollback.sh --list

环境变量:
  ROLLBACK_TIMEOUT        服务启动超时时间 (默认: 120秒)
  WEBHOOK_URL            回滚通知Webhook
EOF
}

# =============================================================================
# 列出可用备份
# =============================================================================
list_backups() {
    log "可用的备份文件:"
    
    local backup_dir="/opt/backups"
    if [ ! -d "$backup_dir" ]; then
        error "备份目录不存在: $backup_dir"
        return 1
    fi
    
    echo ""
    printf "%-25s %-12s %-20s\n" "备份时间" "大小" "文件路径"
    echo "--------------------------------------------------------------------------------"
    
    local count=0
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local size=$(du -h "$file" | cut -f1)
            local mtime=$(stat -c "%y" "$file" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$file" 2>/dev/null)
            
            printf "%-25s %-12s %-20s\n" "$mtime" "$size" "$filename"
            count=$((count + 1))
        fi
    done < <(ls -t "$backup_dir"/smartalbum_*.tar.gz 2>/dev/null || true)
    
    if [ $count -eq 0 ]; then
        warn "未找到备份文件"
    else
        echo ""
        log "找到 $count 个备份文件"
    fi
}

# =============================================================================
# 获取最新备份
# =============================================================================
get_latest_backup() {
    local backup_dir="/opt/backups"
    local latest=$(ls -t "$backup_dir"/smartalbum_*.tar.gz 2>/dev/null | head -1)
    
    if [ -z "$latest" ]; then
        error "未找到可用的备份文件"
        return 1
    fi
    
    echo "$latest"
}

# =============================================================================
# 验证备份文件
# =============================================================================
verify_backup() {
    local backup_file="$1"
    
    log "验证备份文件: $backup_file"
    
    if [ ! -f "$backup_file" ]; then
        error "备份文件不存在: $backup_file"
        return 1
    fi
    
    # 检查文件大小
    local size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
    if [ "$size" -lt 1024 ]; then
        error "备份文件太小，可能已损坏"
        return 1
    fi
    
    log "  文件大小: $(du -h "$backup_file" | cut -f1)"
    
    # 验证tar文件完整性
    if tar -tzf "$backup_file" > /dev/null 2>&1; then
        log "  ✓ 备份文件完整性验证通过"
    else
        error "备份文件已损坏，无法解压"
        return 1
    fi
    
    return 0
}

# =============================================================================
# 停止当前环境
# =============================================================================
stop_current_environment() {
    section "停止当前环境"
    ROLLBACK_STATUS="STOPPING"
    
    log "停止所有 SmartAlbum 服务..."
    
    cd "$PROJECT_ROOT"
    
    # 停止所有 docker-compose 文件
    for compose_file in docker-compose*.yml; do
        if [ -f "$compose_file" ]; then
            log "  停止: $compose_file"
            docker-compose -f "$compose_file" down --remove-orphans 2>/dev/null || true
        fi
    done
    
    # 停止特定容器
    local containers=$(docker ps -q --filter "name=smartalbum" 2>/dev/null || true)
    if [ -n "$containers" ]; then
        log "  停止剩余容器..."
        docker stop $containers 2>/dev/null || true
        docker rm $containers 2>/dev/null || true
    fi
    
    # 等待确保完全停止
    sleep 3
    
    local remaining=$(docker ps -q --filter "name=smartalbum" 2>/dev/null | wc -l)
    if [ "$remaining" -eq 0 ]; then
        log "  ✓ 所有服务已停止"
    else
        warn "  仍有 $remaining 个容器在运行"
    fi
    
    return 0
}

# =============================================================================
# 恢复数据
# =============================================================================
restore_data() {
    section "恢复数据"
    ROLLBACK_STATUS="RESTORING"
    
    log "从备份恢复数据..."
    
    local backup_file="$1"
    local temp_dir="/tmp/smartalbum_rollback_$TIMESTAMP"
    
    # 创建临时目录
    mkdir -p "$temp_dir"
    
    # 解压备份
    log "  解压备份文件..."
    if ! tar -xzf "$backup_file" -C "$temp_dir"; then
        error "解压备份失败"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 找到解压后的目录
    local extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d | grep -v "^$temp_dir$" | head -1)
    if [ -z "$extracted_dir" ]; then
        error "无法找到解压后的备份目录"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log "  备份目录: $extracted_dir"
    
    # 恢复数据库
    if [ -f "$extracted_dir/database/smartalbum.db" ]; then
        log "  恢复数据库..."
        mkdir -p "$PROJECT_ROOT/data"
        cp "$extracted_dir/database/smartalbum.db" "$PROJECT_ROOT/data/"
        log "    ✓ 数据库已恢复"
    fi
    
    # 恢复向量数据
    if [ -d "$extracted_dir/vectors" ]; then
        log "  恢复向量数据..."
        
        # 恢复ChromaDB
        for chroma_tar in "$extracted_dir"/vectors/chroma_*.tar.gz; do
            if [ -f "$chroma_tar" ]; then
                tar -xzf "$chroma_tar" -C "$PROJECT_ROOT"
                log "    ✓ ChromaDB 已恢复"
            fi
        done
        
        # 恢复JSON向量
        if [ -f "$extracted_dir/vectors/vectors.json" ]; then
            cp "$extracted_dir/vectors/vectors.json" "$PROJECT_ROOT/data/"
            log "    ✓ 向量JSON已恢复"
        fi
    fi
    
    # 恢复配置
    if [ -d "$extracted_dir/config" ]; then
        log "  恢复配置文件..."
        cp -r "$extracted_dir/config"/* "$PROJECT_ROOT/" 2>/dev/null || true
        log "    ✓ 配置已恢复"
    fi
    
    # 恢复代码
    if [ -f "$extracted_dir/code/source_"*.tar.gz ]; then
        log "  恢复代码版本..."
        # 这里我们只恢复数据，不恢复代码，因为代码应该使用git管理
        log "    ℹ 代码版本记录在 $extracted_dir/code/version.txt"
        if [ -f "$extracted_dir/code/version.txt" ]; then
            local version=$(cat "$extracted_dir/code/version.txt")
            log "    备份版本: $version"
        fi
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    log "  ✓ 数据恢复完成"
    
    return 0
}

# =============================================================================
# 启动服务
# =============================================================================
start_services() {
    section "启动服务"
    ROLLBACK_STATUS="STARTING"
    
    log "启动 SmartAlbum 服务..."
    
    cd "$PROJECT_ROOT"
    
    # 使用生产配置启动
    if [ -f "docker-compose.prod.yml" ]; then
        log "  使用 docker-compose.prod.yml 启动..."
        if docker-compose -f docker-compose.prod.yml up -d; then
            log "    ✓ 服务已启动"
        else
            error "服务启动失败"
            return 1
        fi
    elif [ -f "docker-compose.yml" ]; then
        log "  使用 docker-compose.yml 启动..."
        if docker-compose up -d; then
            log "    ✓ 服务已启动"
        else
            error "服务启动失败"
            return 1
        fi
    else
        error "未找到 docker-compose 文件"
        return 1
    fi
    
    # 等待服务启动
    local timeout=${ROLLBACK_TIMEOUT:-120}
    local elapsed=0
    local interval=5
    
    log "  等待服务就绪 (超时: ${timeout}秒)..."
    
    while [ $elapsed -lt $timeout ]; do
        if curl -sf "http://localhost:9999/api/health" > /dev/null 2>&1; then
            log "    ✓ 服务健康检查通过"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    echo ""
    
    warn "服务启动超时，请手动检查状态"
    return 1
}

# =============================================================================
# 验证回滚
# =============================================================================
verify_rollback() {
    section "验证回滚"
    ROLLBACK_STATUS="VERIFYING"
    
    log "执行回滚验证..."
    
    local all_passed=true
    
    # 1. 检查容器状态
    log "  检查容器状态..."
    local containers=$(docker ps --format "{{.Names}}" | grep "smartalbum" || true)
    if [ -n "$containers" ]; then
        success "容器正在运行"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "smartalbum"
    else
        error "没有运行中的容器"
        all_passed=false
    fi
    
    # 2. 检查API
    log "  检查API响应..."
    if curl -sf "http://localhost:9999/api/health" > /dev/null 2>&1; then
        log "    ✓ API 响应正常"
    else
        error "API 无响应"
        all_passed=false
    fi
    
    # 3. 检查前端
    log "  检查前端服务..."
    if curl -sf "http://localhost" > /dev/null 2>&1; then
        log "    ✓ 前端响应正常"
    else
        error "前端无响应"
        all_passed=false
    fi
    
    # 4. 检查数据库
    log "  检查数据库..."
    if [ -f "$PROJECT_ROOT/data/smartalbum.db" ]; then
        if command -v sqlite3 &> /dev/null; then
            local integrity=$(sqlite3 "$PROJECT_ROOT/data/smartalbum.db" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
            if [ "$integrity" = "ok" ]; then
                log "    ✓ 数据库完整性正常"
            else
                error "数据库完整性检查失败"
                all_passed=false
            fi
        else
            log "    ℹ sqlite3 未安装，跳过完整性检查"
        fi
    else
        error "数据库文件不存在"
        all_passed=false
    fi
    
    if [ "$all_passed" = true ]; then
        log "  ✓ 回滚验证通过"
        return 0
    else
        error "回滚验证失败，请检查系统状态"
        return 1
    fi
}

# =============================================================================
# 完成回滚
# =============================================================================
finish_rollback() {
    section "回滚完成"
    ROLLBACK_STATUS="COMPLETED"
    
    log "=============================================="
    log "  回滚成功完成!"
    log "=============================================="
    log "恢复时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "备份来源: $BACKUP_PATH"
    log "日志文件: $LOG_FILE"
    log ""
    log "当前运行容器:"
    docker ps --filter "name=smartalbum" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    log ""
    log "建议:"
    log "  1. 验证所有功能正常"
    log "  2. 监控系统指标"
    log "  3. 通知相关团队"
    log "=============================================="
    
    # 发送通知
    if [ -n "${WEBHOOK_URL:-}" ]; then
        curl -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"SmartAlbum 已回滚 - 备份: $(basename "$BACKUP_PATH")\"}" \
            "$WEBHOOK_URL" 2>/dev/null || true
    fi
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    # 解析参数
    local auto_confirm=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -e|--emergency)
                EMERGENCY_MODE=true
                log "紧急模式已启用"
                shift
                ;;
            -l|--list)
                list_backups
                exit 0
                ;;
            -y|--yes)
                auto_confirm=true
                shift
                ;;
            --stop-only)
                init_logging
                stop_current_environment
                log "仅停止模式完成"
                exit 0
                ;;
            -*)
                error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                BACKUP_PATH="$1"
                shift
                ;;
        esac
    done
    
    # 初始化日志
    init_logging
    
    section "SmartAlbum 快速回滚"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "项目目录: $PROJECT_ROOT"
    log "日志文件: $LOG_FILE"
    
    # 确定备份文件
    if [ -z "$BACKUP_PATH" ]; then
        log "未指定备份文件，使用最新备份..."
        BACKUP_PATH=$(get_latest_backup)
        if [ $? -ne 0 ]; then
            exit 1
        fi
    fi
    
    log "备份文件: $BACKUP_PATH"
    
    # 验证备份
    verify_backup "$BACKUP_PATH" || exit 1
    
    # 确认 (非紧急模式)
    if [ "$EMERGENCY_MODE" = false ] && [ "$auto_confirm" = false ]; then
        echo ""
        warn "即将执行回滚操作!"
        warn "这将停止当前服务并恢复备份数据。"
        echo ""
        read -p "确认执行回滚? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "用户取消回滚"
            exit 0
        fi
    fi
    
    # 执行回滚流程
    stop_current_environment || exit 1
    restore_data "$BACKUP_PATH" || exit 1
    start_services || exit 1
    verify_rollback || exit 1
    finish_rollback
}

# 运行主函数
main "$@"
