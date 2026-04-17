#!/bin/bash
# SmartAlbum 健康检查脚本
# 功能: 全面检查系统健康状态，包括服务、性能、数据库等
# 支持: 主动检查、定时监控、告警通知

set -euo pipefail

# =============================================================================
# 配置
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 加载公共库（如果存在）
if [ -f "$SCRIPT_DIR/../lib/common.sh" ]; then
    source "$SCRIPT_DIR/../lib/common.sh"
fi

LOG_DIR="/var/log/smartalbum/health"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/health-check-$TIMESTAMP.log"

# 默认配置
BACKEND_URL="${BACKEND_URL:-http://localhost:9999}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost}"
TIMEOUT="${TIMEOUT:-10}"
VERBOSE="${VERBOSE:-false}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
METRICS_FILE="${METRICS_FILE:-/var/log/smartalbum/metrics.json}"

# 阈值配置
THRESHOLD_RESPONSE_TIME="${THRESHOLD_RESPONSE_TIME:-2.0}"  # 秒
THRESHOLD_ERROR_RATE="${THRESHOLD_ERROR_RATE:-1}"          # %
THRESHOLD_CPU="${THRESHOLD_CPU:-80}"                       # %
THRESHOLD_MEMORY="${THRESHOLD_MEMORY:-85}"                 # %
THRESHOLD_DISK="${THRESHOLD_DISK:-85}"                     # %

# =============================================================================
# 工具函数（保持独立，确保无依赖也能运行）
# =============================================================================

# 浮点数比较（使用awk替代bc，避免额外依赖）
float_compare() {
    local num1="$1"
    local op="$2"
    local num2="$3"
    awk "BEGIN {exit !($num1 $op $num2)}"
}

# 检查命令是否存在
check_command() {
    command -v "$1" &>/dev/null
}

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查结果
CHECK_STATUS="PASS"
FAILED_CHECKS=()
WARNINGS=()
METRICS=()

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
    FAILED_CHECKS+=("$1")
    CHECK_STATUS="FAIL"
}

info() {
    log "${BLUE}ℹ $1${NC}"
}

# =============================================================================
# 检查项
# =============================================================================

# 1. 系统服务检查 (裸机部署)
check_systemd_services() {
    info "检查系统服务状态..."
    
    local services=("smartalbum-backend" "smartalbum-frontend" "nginx")
    local all_healthy=true
    
    for service in "${services[@]}"; do
        # 检查服务是否已安装
        if ! systemctl list-unit-files | grep -q "^${service}"; then
            warn "服务 $service 未安装，跳过检查"
            continue
        fi
        
        # 检查服务状态
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            local status=$(systemctl show --property=ActiveState --value "$service")
            local uptime=$(systemctl show --property=ActiveEnterTimestamp --value "$service" | cut -d' ' -f2-)
            
            success "服务 $service 运行正常 (状态: $status, 启动: $uptime)"
            
            # 获取进程资源使用
            local pid=$(systemctl show --property=MainPID --value "$service")
            if [ "$pid" != "0" ] && [ -n "$pid" ]; then
                local cpu_mem=$(ps -p "$pid" -o %cpu=,%mem= 2>/dev/null || echo "N/A")
                local cpu=$(echo "$cpu_mem" | awk '{print $1}')
                local mem=$(echo "$cpu_mem" | awk '{print $2}')
                
                if [ "$cpu" != "N/A" ] && float_compare "$cpu" ">" "$THRESHOLD_CPU"; then
                    warn "服务 $service CPU 使用率过高: ${cpu}%"
                    high_resource=true
                fi
                
                if [ "$mem" != "N/A" ] && float_compare "$mem" ">" "$THRESHOLD_MEMORY"; then
                    warn "服务 $service 内存使用率过高: ${mem}%"
                    high_resource=true
                fi
            fi
        else
            local status=$(systemctl show --property=ActiveState --value "$service" 2>/dev/null || echo "unknown")
            fail "服务 $service 未运行 (状态: $status)"
            all_healthy=false
        fi
    done
    
    # 检查服务是否开机自启
    info "检查服务开机自启配置..."
    for service in "${services[@]}"; do
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            success "服务 $service 已配置开机自启"
        else
            warn "服务 $service 未配置开机自启"
        fi
    done
            
            METRICS+=("{\"service\":\"$name\",\"cpu\":\"$cpu\",\"memory\":\"$mem\"}")
        fi
    done
    
    if [ "$high_resource" = false ]; then
        success "服务资源使用正常"
    fi
    
    $all_healthy
}

# 2. API 健康检查
check_api_health() {
    info "检查 API 健康状态..."
    
    local response
    local http_code
    local response_time
    
    # 尝试不同的后端地址
    local backend_urls=("$BACKEND_URL" "http://localhost:9999" "http://localhost:9998")
    local api_ok=false
    
    for url in "${backend_urls[@]}"; do
        response=$(curl -s -w "\n%{http_code}\n%{time_total}" \
            --max-time "$TIMEOUT" \
            "${url}/api/health" 2>/dev/null) && true
        
        if [ -n "$response" ]; then
            http_code=$(echo "$response" | tail -2 | head -1)
            response_time=$(echo "$response" | tail -1)
            
            if [ "$http_code" = "200" ]; then
                api_ok=true
                BACKEND_URL="$url"
                success "API 健康检查通过 (URL: $url, 响应时间: ${response_time}s)"
                
                if float_compare "$response_time" ">" "$THRESHOLD_RESPONSE_TIME"; then
                    warn "API 响应时间较慢: ${response_time}s (阈值: ${THRESHOLD_RESPONSE_TIME}s)"
                fi
                
                METRICS+=("{\"api_response_time\":$response_time,\"api_status\":\"ok\"}")
                break
            fi
        fi
    done
    
    if [ "$api_ok" = false ]; then
        fail "API 健康检查失败 (HTTP: ${http_code:-无响应})"
        return 1
    fi
    
    # 检查 API 详情
    info "检查 API 详情..."
    local api_details=$(curl -s --max-time "$TIMEOUT" "${BACKEND_URL}/api/health" 2>/dev/null || echo "")
    if [ -n "$api_details" ]; then
        success "API 详情获取成功"
        if [ "$VERBOSE" = true ]; then
            echo "$api_details" | python3 -m json.tool 2>/dev/null || echo "$api_details"
        fi
    fi
    
    return 0
}

# 3. 前端健康检查
check_frontend() {
    info "检查前端服务..."
    
    local response
    local http_code
    local response_time
    
    # 尝试不同的前端地址
    local frontend_urls=("$FRONTEND_URL" "http://localhost:80" "http://localhost:8081" "http://localhost:8082")
    local frontend_ok=false
    
    for url in "${frontend_urls[@]}"; do
        response=$(curl -s -w "\n%{http_code}\n%{time_total}" \
            --max-time "$TIMEOUT" \
            "$url" 2>/dev/null) && true
        
        if [ -n "$response" ]; then
            http_code=$(echo "$response" | tail -2 | head -1)
            response_time=$(echo "$response" | tail -1)
            
            if [ "$http_code" = "200" ] || [ "$http_code" = "304" ]; then
                frontend_ok=true
                FRONTEND_URL="$url"
                success "前端健康检查通过 (URL: $url, 响应时间: ${response_time}s)"
                METRICS+=("{\"frontend_response_time\":$response_time,\"frontend_status\":\"ok\"}")
                break
            fi
        fi
    done
    
    if [ "$frontend_ok" = false ]; then
        fail "前端健康检查失败 (HTTP: ${http_code:-无响应})"
        return 1
    fi
    
    return 0
}

# 4. 数据库检查
check_database() {
    info "检查数据库状态..."
    
    local db_file="$PROJECT_ROOT/data/smartalbum.db"
    
    if [ ! -f "$db_file" ]; then
        warn "数据库文件不存在: $db_file"
        return 1
    fi
    
    # 检查数据库完整性
    if command -v sqlite3 &> /dev/null; then
        local integrity=$(sqlite3 "$db_file" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
        
        if [ "$integrity" = "ok" ]; then
            success "数据库完整性检查通过"
        else
            fail "数据库完整性检查失败: $integrity"
            return 1
        fi
        
        # 获取统计信息
        local photo_count=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM photos;" 2>/dev/null || echo "0")
        local album_count=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM albums;" 2>/dev/null || echo "0")
        local user_count=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
        
        info "数据库统计: 照片=$photo_count, 相册=$album_count, 用户=$user_count"
        METRICS+=("{\"db_photos\":$photo_count,\"db_albums\":$album_count,\"db_users\":$user_count}")
    else
        warn "sqlite3 未安装，跳过数据库完整性检查"
    fi
    
    # 检查数据库文件权限
    if [ -r "$db_file" ] && [ -w "$db_file" ]; then
        success "数据库文件权限正常"
    else
        warn "数据库文件权限可能有问题"
    fi
    
    return 0
}

# 5. 存储检查
check_storage() {
    info "检查存储状态..."
    
    local storage_dir="$PROJECT_ROOT/storage"
    
    if [ ! -d "$storage_dir" ]; then
        warn "存储目录不存在: $storage_dir"
        return 1
    fi
    
    # 统计文件
    local file_count=$(find "$storage_dir" -type f 2>/dev/null | wc -l)
    local dir_size=$(du -sh "$storage_dir" 2>/dev/null | cut -f1)
    
    success "存储目录正常: $file_count 个文件, 大小: $dir_size"
    METRICS+=("{\"storage_files\":$file_count,\"storage_size\":\"$dir_size\"}")
    
    # 检查存储权限
    if [ -r "$storage_dir" ] && [ -w "$storage_dir" ]; then
        success "存储目录权限正常"
    else
        warn "存储目录权限可能有问题"
    fi
    
    return 0
}

# 6. 系统资源检查
check_system_resources() {
    info "检查系统资源..."
    
    # CPU 使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if [ -n "$cpu_usage" ]; then
        local cpu_int=${cpu_usage%.*}
        if [ "$cpu_int" -gt "$THRESHOLD_CPU" ]; then
            warn "CPU 使用率过高: ${cpu_usage}%"
        else
            success "CPU 使用率正常: ${cpu_usage}%"
        fi
        METRICS+=("{\"system_cpu\":$cpu_usage}")
    fi
    
    # 内存使用率
    local mem_info=$(free | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_usage=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")
    
    if float_compare "$mem_usage" ">" "$THRESHOLD_MEMORY"; then
        warn "内存使用率过高: ${mem_usage}%"
    else
        success "内存使用率正常: ${mem_usage}%"
    fi
    METRICS+=("{\"system_memory\":$mem_usage}")
    
    # 磁盘使用率
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt "$THRESHOLD_DISK" ]; then
        warn "磁盘使用率过高: ${disk_usage}%"
    else
        success "磁盘使用率正常: ${disk_usage}%"
    fi
    METRICS+=("{\"system_disk\":$disk_usage}")
    
    return 0
}

# 7. 网络连接检查
check_network() {
    info "检查网络连接..."
    
    # 检查端口监听
    local ports=(80 443 9999)
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port " || \
           ss -tuln 2>/dev/null | grep -q ":$port " || \
           lsof -i :$port 2>/dev/null | grep -q LISTEN; then
            success "端口 $port 正在监听"
        else
            if [ "$port" = "443" ]; then
                info "端口 $port 未监听 (HTTPS 可能未配置)"
            else
                warn "端口 $port 未监听"
            fi
        fi
    done
    
    return 0
}

# 8. 日志检查
check_logs() {
    info "检查近期错误日志..."
    
    local error_count=0
    
    # 检查系统服务日志中的错误 (使用journalctl)
    local services=("smartalbum-backend" "smartalbum-frontend")
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            local recent_errors=$(journalctl -u "$service" --since "1 hour ago" --no-pager 2>/dev/null | grep -i "error\|exception\|fatal" | wc -l)
            if [ "$recent_errors" -gt 10 ]; then
                warn "服务 $service 最近1小时有 $recent_errors 个错误日志"
                error_count=$((error_count + recent_errors))
            fi
        fi
    done
    
    # 检查Nginx错误日志
    if [ -f "/var/log/nginx/error.log" ]; then
        local nginx_errors=$(tail -n 1000 /var/log/nginx/error.log 2>/dev/null | grep "$(date '+%Y/%m/%d')" | wc -l)
        if [ "$nginx_errors" -gt 50 ]; then
            warn "Nginx 今天有较多错误日志: $nginx_errors 条"
        fi
    fi
    
    if [ $error_count -eq 0 ]; then
        success "近期错误日志正常"
    else
        warn "近期共有 $error_count 个错误日志，建议检查"
    fi
    
    METRICS+=("{\"recent_errors\":$error_count}")
    
    return 0
}

# =============================================================================
# 报告和告警
# =============================================================================
generate_report() {
    info "生成健康检查报告..."
    
    local report_file="$LOG_DIR/health-report-$TIMESTAMP.json"
    
    # 构建JSON报告
    local checks_array=""
    for check in "${FAILED_CHECKS[@]}"; do
        checks_array="$checks_array\"$check\","
    done
    checks_array="[${checks_array%,}]"
    
    local warnings_array=""
    for warning in "${WARNINGS[@]}"; do
        warnings_array="$warnings_array\"$warning\","
    done
    warnings_array="[${warnings_array%,}]"
    
    local metrics_json=""
    for metric in "${METRICS[@]}"; do
        metrics_json="$metrics_json$metric,"
    done
    metrics_json="[${metrics_json%,}]"
    
    cat > "$report_file" << EOF
{
    "timestamp": "$TIMESTAMP",
    "status": "$CHECK_STATUS",
    "checks": {
        "failed": $checks_array,
        "warnings": $warnings_array
    },
    "metrics": $metrics_json,
    "endpoints": {
        "backend": "$BACKEND_URL",
        "frontend": "$FRONTEND_URL"
    }
}
EOF
    
    log "报告已保存: $report_file"
    
    # 更新最新的metrics文件
    if [ -n "$METRICS_FILE" ]; then
        mkdir -p "$(dirname "$METRICS_FILE")"
        cp "$report_file" "$METRICS_FILE"
    fi
}

send_alert() {
    if [ "$CHECK_STATUS" = "FAIL" ] && [ -n "$ALERT_WEBHOOK" ]; then
        info "发送告警通知..."
        
        local message="SmartAlbum 健康检查失败"
        local details="${FAILED_CHECKS[*]}"
        local alert_result=0
        
        # 发送告警，添加超时和错误处理
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 10 \
            -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"$message\",\"details\":\"$details\",\"timestamp\":\"$TIMESTAMP\"}" \
            "$ALERT_WEBHOOK" 2>/dev/null)
        
        if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
            success "告警通知发送成功"
        else
            warn "告警通知发送失败 (HTTP $http_code)"
            alert_result=1
        fi
        
        return $alert_result
    fi
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    init_logging
    
    log "========================================"
    log "SmartAlbum 健康检查"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "========================================"
    
    # 检查必要命令
    local required_commands=("curl" "systemctl" "awk" "journalctl")
    for cmd in "${required_commands[@]}"; do
        if ! check_command "$cmd"; then
            error "缺少必要命令: $cmd"
            exit 1
        fi
    done
    
    # 执行所有检查（收集模式，不立即退出）
    local check_failed=0
    
    check_systemd_services || check_failed=1
    check_api_health || check_failed=1
    check_frontend || check_failed=1
    check_database || check_failed=1
    check_storage || check_failed=1
    check_system_resources || check_failed=1
    check_network || check_failed=1
    check_logs || check_failed=1
    
    # 生成报告
    generate_report
    
    # 发送告警
    send_alert
    
    # 输出总结
    log ""
    log "========================================"
    if [ "$CHECK_STATUS" = "PASS" ]; then
        log "${GREEN}健康检查通过 ✓${NC}"
    else
        log "${RED}健康检查失败 ✗${NC}"
        log "失败项:"
        for check in "${FAILED_CHECKS[@]}"; do
            log "  - $check"
        done
    fi
    
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        log ""
        log "${YELLOW}警告项:${NC}"
        for warning in "${WARNINGS[@]}"; do
            log "  - $warning"
        done
    fi
    
    log "详细日志: $LOG_FILE"
    log "========================================"
    
    # 返回状态码
    if [ "$CHECK_STATUS" = "PASS" ]; then
        exit 0
    else
        exit 1
    fi
}

# 处理命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "SmartAlbum 健康检查脚本"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --help, -h           显示帮助"
            echo "  --verbose, -v        详细输出"
            echo "  --backend URL        指定后端地址"
            echo "  --frontend URL       指定前端地址"
            echo "  --webhook URL        告警Webhook地址"
            echo ""
            echo "环境变量:"
            echo "  BACKEND_URL          后端地址 (默认: http://localhost:9999)"
            echo "  FRONTEND_URL         前端地址 (默认: http://localhost)"
            echo "  ALERT_WEBHOOK        告警Webhook"
            echo "  TIMEOUT              请求超时 (默认: 10)"
            exit 0
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --backend)
            BACKEND_URL="$2"
            shift 2
            ;;
        --frontend)
            FRONTEND_URL="$2"
            shift 2
            ;;
        --webhook)
            ALERT_WEBHOOK="$2"
            shift 2
            ;;
        *)
            echo "未知选项: $1"
            exit 1
            ;;
    esac
done

# 运行主函数
main
