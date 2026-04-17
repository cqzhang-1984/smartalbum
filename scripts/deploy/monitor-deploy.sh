#!/bin/bash
# SmartAlbum 部署监控脚本
# 功能: 实时监控部署过程，收集指标，触发告警
# 作者: SmartAlbum DevOps Team
# 版本: 1.0.0

set -euo pipefail

# =============================================================================
# 配置
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="/var/log/smartalbum/monitor"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/monitor-$TIMESTAMP.log"
METRICS_FILE="$LOG_DIR/metrics-$TIMESTAMP.json"

# 监控配置
MONITOR_DURATION="${MONITOR_DURATION:-300}"      # 默认监控5分钟
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"           # 检查间隔10秒
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

# 告警阈值
THRESHOLD_ERROR_RATE="${THRESHOLD_ERROR_RATE:-5}"        # %
THRESHOLD_RESPONSE_TIME="${THRESHOLD_RESPONSE_TIME:-2000}" # ms
THRESHOLD_CPU="${THRESHOLD_CPU:-80}"                      # %
THRESHOLD_MEMORY="${THRESHOLD_MEMORY:-85}"                # %

# 端点
ENDPOINTS=(
    "http://localhost/api/health"
    "http://localhost"
)

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 状态
MONITOR_STATUS="RUNNING"
ALERT_COUNT=0
MAX_ALERTS=5

# 指标数据
declare -A METRICS
declare -a RESPONSE_TIMES
declare -a ERROR_COUNTS

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
}

error() {
    log "${RED}✗ $1${NC}"
}

info() {
    log "${BLUE}ℹ $1${NC}"
}

# =============================================================================
# 指标收集
# =============================================================================
collect_metrics() {
    local timestamp=$(date +%s)
    
    # 系统指标
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    local mem_info=$(free | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_usage=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}" 2>/dev/null || echo "0")
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    
    # Docker指标
    local container_count=$(docker ps --filter "name=smartalbum" --format "{{.Names}}" 2>/dev/null | wc -l)
    local unhealthy_containers=$(docker ps --filter "name=smartalbum" --filter "health=unhealthy" --format "{{.Names}}" 2>/dev/null | wc -l)
    
    # 端点指标
    local total_response_time=0
    local error_count=0
    local endpoint_count=0
    
    for endpoint in "${ENDPOINTS[@]}"; do
        local start_time=$(date +%s%N)
        local http_code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "$endpoint" 2>/dev/null || echo "000")
        local end_time=$(date +%s%N)
        local response_time=$(( (end_time - start_time) / 1000000 ))  # 转换为ms
        
        if [ "$http_code" != "200" ] && [ "$http_code" != "304" ]; then
            error_count=$((error_count + 1))
        fi
        
        total_response_time=$((total_response_time + response_time))
        endpoint_count=$((endpoint_count + 1))
    done
    
    local avg_response_time=0
    if [ $endpoint_count -gt 0 ]; then
        avg_response_time=$((total_response_time / endpoint_count))
    fi
    
    local error_rate=0
    if [ $endpoint_count -gt 0 ]; then
        error_rate=$((error_count * 100 / endpoint_count))
    fi
    
    # 保存指标
    METRICS["timestamp"]=$timestamp
    METRICS["cpu_usage"]=$cpu_usage
    METRICS["memory_usage"]=$mem_usage
    METRICS["disk_usage"]=$disk_usage
    METRICS["container_count"]=$container_count
    METRICS["unhealthy_containers"]=$unhealthy_containers
    METRICS["avg_response_time"]=$avg_response_time
    METRICS["error_count"]=$error_count
    METRICS["error_rate"]=$error_rate
    
    # 添加到数组
    RESPONSE_TIMES+=("$avg_response_time")
    ERROR_COUNTS+=("$error_count")
    
    return 0
}

# =============================================================================
# 检查告警
# =============================================================================
check_alerts() {
    local alerts=()
    
    # 检查错误率
    if [ "${METRICS[error_rate]}" -gt "$THRESHOLD_ERROR_RATE" ]; then
        alerts+=("错误率过高: ${METRICS[error_rate]}% (阈值: ${THRESHOLD_ERROR_RATE}%)")
    fi
    
    # 检查响应时间
    if [ "${METRICS[avg_response_time]}" -gt "$THRESHOLD_RESPONSE_TIME" ]; then
        alerts+=("响应时间过长: ${METRICS[avg_response_time]}ms (阈值: ${THRESHOLD_RESPONSE_TIME}ms)")
    fi
    
    # 检查CPU
    local cpu_int=${METRICS[cpu_usage]%.*}
    if [ "$cpu_int" -gt "$THRESHOLD_CPU" ]; then
        alerts+=("CPU使用率过高: ${METRICS[cpu_usage]}% (阈值: ${THRESHOLD_CPU}%)")
    fi
    
    # 检查内存
    if awk "BEGIN {exit !(${METRICS[memory_usage]} > $THRESHOLD_MEMORY)}" 2>/dev/null; then
        alerts+=("内存使用率过高: ${METRICS[memory_usage]}% (阈值: ${THRESHOLD_MEMORY}%)")
    fi
    
    # 检查不健康的容器
    if [ "${METRICS[unhealthy_containers]}" -gt 0 ]; then
        alerts+=("发现 ${METRICS[unhealthy_containers]} 个不健康容器")
    fi
    
    # 发送告警
    if [ ${#alerts[@]} -gt 0 ] && [ $ALERT_COUNT -lt $MAX_ALERTS ]; then
        for alert in "${alerts[@]}"; do
            warn "告警: $alert"
            send_alert "$alert"
        done
        ALERT_COUNT=$((ALERT_COUNT + 1))
    fi
    
    return ${#alerts[@]}
}

# =============================================================================
# 发送告警
# =============================================================================
send_alert() {
    local message="$1"
    
    # Webhook告警
    if [ -n "$ALERT_WEBHOOK" ]; then
        curl -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"SmartAlert: $message\",\"severity\":\"warning\",\"timestamp\":$(date +%s)}" \
            "$ALERT_WEBHOOK" 2>/dev/null || true
    fi
    
    # 邮件告警
    if [ -n "$ALERT_EMAIL" ] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "SmartAlbum Alert" "$ALERT_EMAIL" 2>/dev/null || true
    fi
}

# =============================================================================
# 显示状态
# =============================================================================
show_status() {
    local elapsed=$1
    local remaining=$((MONITOR_DURATION - elapsed))
    
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  SmartAlbum 部署监控${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "监控时长: ${elapsed}s / ${MONITOR_DURATION}s"
    echo -e "告警次数: $ALERT_COUNT / $MAX_ALERTS"
    echo ""
    echo -e "${BLUE}--- 系统指标 ---${NC}"
    printf "CPU使用率:    %6s%%\n" "${METRICS[cpu_usage]:-N/A}"
    printf "内存使用率:   %6s%%\n" "${METRICS[memory_usage]:-N/A}"
    printf "磁盘使用率:   %6s%%\n" "${METRICS[disk_usage]:-N/A}"
    echo ""
    echo -e "${BLUE}--- 服务指标 ---${NC}"
    printf "运行容器数:   %6s\n" "${METRICS[container_count]:-N/A}"
    printf "不健康容器:   %6s\n" "${METRICS[unhealthy_containers]:-N/A}"
    echo ""
    echo -e "${BLUE}--- 性能指标 ---${NC}"
    printf "平均响应时间: %6s ms\n" "${METRICS[avg_response_time]:-N/A}"
    printf "错误数量:     %6s\n" "${METRICS[error_count]:-N/A}"
    printf "错误率:       %6s%%\n" "${METRICS[error_rate]:-N/A}"
    echo ""
    
    # 状态指示
    if [ "${METRICS[error_rate]:-0}" -gt "$THRESHOLD_ERROR_RATE" ] || \
       [ "${METRICS[avg_response_time]:-0}" -gt "$THRESHOLD_RESPONSE_TIME" ]; then
        echo -e "${RED}状态: 异常${NC}"
    else
        echo -e "${GREEN}状态: 正常${NC}"
    fi
    
    echo ""
    echo "按 Ctrl+C 停止监控"
}

# =============================================================================
# 保存指标
# =============================================================================
save_metrics() {
    local json="{"
    json="$json\"timestamp\":\"$TIMESTAMP\","
    json="$json\"duration\":$MONITOR_DURATION,"
    json="$json\"final_metrics\":{"
    json="$json\"cpu\":\"${METRICS[cpu_usage]}\","
    json="$json\"memory\":\"${METRICS[memory_usage]}\","
    json="$json\"response_time\":${METRICS[avg_response_time]},"
    json="$json\"error_rate\":${METRICS[error_rate]}"
    json="$json},"
    json="$json\"alert_count\":$ALERT_COUNT,"
    json="$json\"status\":\"$MONITOR_STATUS\""
    json="$json}"
    
    echo "$json" > "$METRICS_FILE"
    log "指标已保存: $METRICS_FILE"
}

# =============================================================================
# 生成报告
# =============================================================================
generate_report() {
    local duration=$1
    
    log ""
    log "========================================"
    log "监控报告"
    log "========================================"
    log "监控时长: ${duration}秒"
    log "告警次数: $ALERT_COUNT"
    log "最终状态: $MONITOR_STATUS"
    log ""
    log "平均指标:"
    log "  CPU: ${METRICS[cpu_usage]}%"
    log "  内存: ${METRICS[memory_usage]}%"
    log "  响应时间: ${METRICS[avg_response_time]}ms"
    log "  错误率: ${METRICS[error_rate]}%"
    log ""
    log "日志文件: $LOG_FILE"
    log "指标文件: $METRICS_FILE"
    log "========================================"
}

# =============================================================================
# 主监控循环
# =============================================================================
monitor_loop() {
    local elapsed=0
    
    log "开始监控 (持续 ${MONITOR_DURATION}秒)..."
    
    while [ $elapsed -lt $MONITOR_DURATION ]; do
        collect_metrics
        
        # 交互模式显示状态
        if [ "${INTERACTIVE:-false}" = "true" ]; then
            show_status $elapsed
        else
            # 日志模式
            info "[$elapsed s] CPU:${METRICS[cpu_usage]}% MEM:${METRICS[memory_usage]}% RT:${METRICS[avg_response_time]}ms ERR:${METRICS[error_count]}"
        fi
        
        # 检查告警
        check_alerts
        
        # 检查是否需要停止
        if [ "$ALERT_COUNT" -ge "$MAX_ALERTS" ]; then
            error "告警次数达到上限，停止监控"
            MONITOR_STATUS="ALERT_LIMIT"
            break
        fi
        
        sleep $CHECK_INTERVAL
        elapsed=$((elapsed + CHECK_INTERVAL))
    done
    
    if [ "$MONITOR_STATUS" = "RUNNING" ]; then
        MONITOR_STATUS="COMPLETED"
    fi
    
    save_metrics
    generate_report $elapsed
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    init_logging
    
    log "========================================"
    log "SmartAlbum 部署监控"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "========================================"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                echo "SmartAlbum 部署监控脚本"
                echo ""
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  --help, -h           显示帮助"
                echo "  --duration SECONDS   监控时长 (默认: 300)"
                echo "  --interval SECONDS   检查间隔 (默认: 10)"
                echo "  --webhook URL        告警Webhook"
                echo "  --interactive        交互模式 (显示实时状态)"
                echo "  --threshold-error N  错误率阈值 % (默认: 5)"
                echo "  --threshold-rt MS    响应时间阈值 ms (默认: 2000)"
                echo ""
                echo "示例:"
                echo "  # 后台监控10分钟"
                echo "  $0 --duration 600"
                echo ""
                echo "  # 交互式监控"
                echo "  $0 --interactive"
                exit 0
                ;;
            --duration)
                MONITOR_DURATION="$2"
                shift 2
                ;;
            --interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            --webhook)
                ALERT_WEBHOOK="$2"
                shift 2
                ;;
            --interactive)
                INTERACTIVE=true
                shift
                ;;
            --threshold-error)
                THRESHOLD_ERROR_RATE="$2"
                shift 2
                ;;
            --threshold-rt)
                THRESHOLD_RESPONSE_TIME="$2"
                shift 2
                ;;
            *)
                echo "未知选项: $1"
                exit 1
                ;;
        esac
    done
    
    # 检查依赖
    if ! command -v curl &> /dev/null; then
        error "需要安装 curl"
        exit 1
    fi
    
    # 启动监控
    monitor_loop
    
    # 返回状态
    if [ "$MONITOR_STATUS" = "COMPLETED" ]; then
        exit 0
    else
        exit 1
    fi
}

# 信号处理
trap 'log "监控被中断"; save_metrics; exit 130' INT TERM

# 运行主函数
main "$@"
