#!/bin/bash
# SmartAlbum 生产环境升级主脚本
# 功能: 零停机蓝绿部署、自动健康检查、一键回滚
# 作者: SmartAlbum DevOps Team
# 版本: 1.0.0

set -euo pipefail

# =============================================================================
# 配置变量
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="/var/log/smartalbum/deploy"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/deploy-$TIMESTAMP.log"

# 部署配置
BLUE_FRONTEND_PORT=${BLUE_FRONTEND_PORT:-8081}
BLUE_BACKEND_PORT=${BLUE_BACKEND_PORT:-9999}
GREEN_FRONTEND_PORT=${GREEN_FRONTEND_PORT:-8082}
GREEN_BACKEND_PORT=${GREEN_BACKEND_PORT:-9998}
HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-60}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-5}
MAX_RETRY_ATTEMPTS=${MAX_RETRY_ATTEMPTS:-12}
TRAFFIC_SWITCH_BATCH=${TRAFFIC_SWITCH_BATCH:-10}
ROLLBACK_THRESHOLD_ERROR_RATE=${ROLLBACK_THRESHOLD_ERROR_RATE:-1}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 状态跟踪
DEPLOYMENT_STATUS="INIT"
TARGET_ENV=""  # BLUE or GREEN
ACTIVE_ENV=""  # 当前运行的环境
BACKUP_PATH=""
ROLLBACK_AVAILABLE=false

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
        error "部署脚本异常退出 (错误码: $exit_code)"
        error "当前状态: $DEPLOYMENT_STATUS"
        
        if [ "$ROLLBACK_AVAILABLE" = true ]; then
            warn "检测到可回滚状态，是否执行自动回滚?"
            warn "执行回滚命令: ./scripts/deploy/quick-rollback.sh $BACKUP_PATH"
        fi
        
        error "日志文件: $LOG_FILE"
    fi
    exit $exit_code
}

trap cleanup_on_error EXIT ERR INT TERM

# =============================================================================
# 预部署检查
# =============================================================================
pre_deployment_check() {
    section "阶段 1/8: 预部署检查"
    DEPLOYMENT_STATUS="PRE_CHECK"
    
    log "检查系统资源..."
    
    # 检查磁盘空间
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 80 ]; then
        error "磁盘空间不足: ${disk_usage}% (需要 < 80%)"
        return 1
    fi
    log "  ✓ 磁盘空间充足: ${disk_usage}%"
    
    # 检查内存
    local mem_available=$(free -m | awk 'NR==2{printf "%.0f", $7*100/$2}')
    if [ "$mem_available" -lt 20 ]; then
        error "可用内存不足: ${mem_available}% (需要 > 20%)"
        return 1
    fi
    log "  ✓ 内存充足: ${mem_available}% 可用"
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装"
        return 1
    fi
    if ! docker info &> /dev/null; then
        error "Docker 服务未运行"
        return 1
    fi
    log "  ✓ Docker 运行正常"
    
    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose 未安装"
        return 1
    fi
    log "  ✓ Docker Compose 可用"
    
    # 检查Nginx
    if ! command -v nginx &> /dev/null; then
        warn "Nginx 未安装，将使用 Docker 内置代理"
    else
        log "  ✓ Nginx 已安装"
    fi
    
    # 检查目录权限
    if [ ! -w "$PROJECT_ROOT/data" ] || [ ! -w "$PROJECT_ROOT/storage" ]; then
        error "数据目录没有写入权限"
        return 1
    fi
    log "  ✓ 目录权限正常"
    
    # 检查必需文件
    local required_files=("docker-compose.prod.yml" "backend/Dockerfile" "frontend/Dockerfile")
    for file in "${required_files[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$file" ]; then
            error "缺少必需文件: $file"
            return 1
        fi
    done
    log "  ✓ 必需文件存在"
    
    log "预部署检查通过 ✓"
    return 0
}

# =============================================================================
# 执行备份
# =============================================================================
execute_backup() {
    section "阶段 2/8: 执行全量备份"
    DEPLOYMENT_STATUS="BACKUP"
    
    log "开始备份..."
    
    if [ -f "$SCRIPT_DIR/full-backup.sh" ]; then
        bash "$SCRIPT_DIR/full-backup.sh"
        if [ $? -ne 0 ]; then
            error "备份失败，终止部署"
            return 1
        fi
    else
        error "备份脚本不存在: $SCRIPT_DIR/full-backup.sh"
        return 1
    fi
    
    # 获取最新的备份路径
    BACKUP_PATH=$(ls -t /opt/backups/smartalbum_*.tar.gz 2>/dev/null | head -1)
    if [ -z "$BACKUP_PATH" ]; then
        error "无法找到备份文件"
        return 1
    fi
    
    ROLLBACK_AVAILABLE=true
    log "备份完成: $BACKUP_PATH"
    log "回滚功能已启用 ✓"
    
    return 0
}

# =============================================================================
# 确定目标环境
# =============================================================================
determine_target_environment() {
    section "阶段 3/8: 确定目标环境"
    DEPLOYMENT_STATUS="DETECT_ENV"
    
    log "检测当前运行环境..."
    
    # 检查蓝环境是否运行
    local blue_running=false
    if docker ps --format "{{.Names}}" | grep -q "smartalbum-blue"; then
        blue_running=true
        ACTIVE_ENV="BLUE"
        TARGET_ENV="GREEN"
    fi
    
    # 检查绿环境是否运行
    local green_running=false
    if docker ps --format "{{.Names}}" | grep -q "smartalbum-green"; then
        green_running=true
        ACTIVE_ENV="GREEN"
        TARGET_ENV="BLUE"
    fi
    
    # 如果都没有运行，默认部署到蓝环境
    if [ "$blue_running" = false ] && [ "$green_running" = false ]; then
        log "未检测到运行中的环境，将部署到蓝环境 (BLUE)"
        ACTIVE_ENV="NONE"
        TARGET_ENV="BLUE"
    elif [ "$blue_running" = true ] && [ "$green_running" = true ]; then
        warn "检测到蓝绿环境同时运行，将使用绿环境作为目标"
        ACTIVE_ENV="BLUE"
        TARGET_ENV="GREEN"
    else
        log "当前活动环境: $ACTIVE_ENV"
        log "目标部署环境: $TARGET_ENV"
    fi
    
    log "环境检测完成 ✓"
    return 0
}

# =============================================================================
# 构建新版本
# =============================================================================
build_new_version() {
    section "阶段 4/8: 构建新版本"
    DEPLOYMENT_STATUS="BUILD"
    
    log "开始构建 $TARGET_ENV 环境..."
    cd "$PROJECT_ROOT"
    
    # 导出目标环境变量
    export TARGET_ENV
    export FRONTEND_PORT=$( [ "$TARGET_ENV" = "BLUE" ] && echo "$BLUE_FRONTEND_PORT" || echo "$GREEN_FRONTEND_PORT" )
    export BACKEND_PORT=$( [ "$TARGET_ENV" = "BLUE" ] && echo "$BLUE_BACKEND_PORT" || echo "$GREEN_BACKEND_PORT" )
    
    log "目标端口: Frontend=$FRONTEND_PORT, Backend=$BACKEND_PORT"
    
    # 创建临时docker-compose文件
    local compose_file="docker-compose.$TARGET_ENV.yml"
    cat > "$compose_file" << EOF
version: '3.8'

services:
  redis-$TARGET_ENV:
    image: redis:7-alpine
    container_name: smartalbum-redis-$TARGET_ENV
    restart: always
    networks:
      - smartalbum-$TARGET_ENV
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  backend-$TARGET_ENV:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: smartalbum-backend-$TARGET_ENV
    restart: always
    environment:
      - DATABASE_URL=sqlite+aiosqlite:///./data/smartalbum.db
      - REDIS_URL=redis://redis-$TARGET_ENV:6379/0
      - STORAGE_PATH=/app/storage
      - DEBUG=false
      - PORT=9999
    env_file:
      - ./backend/.env
    volumes:
      - ./data:/app/data
      - ./storage:/app/storage
      - ./backend/logs:/app/logs
    networks:
      - smartalbum-$TARGET_ENV
    depends_on:
      redis-$TARGET_ENV:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9999/api/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  frontend-$TARGET_ENV:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: smartalbum-frontend-$TARGET_ENV
    restart: always
    ports:
      - "\${FRONTEND_PORT}:80"
    networks:
      - smartalbum-$TARGET_ENV
    depends_on:
      - backend-$TARGET_ENV
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s

networks:
  smartalbum-$TARGET_ENV:
    driver: bridge
EOF
    
    log "停止现有 $TARGET_ENV 环境 (如果存在)..."
    docker-compose -f "$compose_file" down --remove-orphans 2>/dev/null || true
    
    log "拉取最新代码..."
    if [ -d ".git" ]; then
        git fetch origin
        git pull origin main || warn "Git pull 失败，使用本地代码"
    fi
    
    log "构建 Docker 镜像..."
    export COMPOSE_DOCKER_CLI_BUILD=1
    export DOCKER_BUILDKIT=1
    
    if ! docker-compose -f "$compose_file" build --no-cache; then
        error "Docker 镜像构建失败"
        rm -f "$compose_file"
        return 1
    fi
    
    log "启动 $TARGET_ENV 环境..."
    if ! docker-compose -f "$compose_file" up -d; then
        error "启动 $TARGET_ENV 环境失败"
        rm -f "$compose_file"
        return 1
    fi
    
    log "等待服务启动..."
    sleep 10
    
    log "构建完成 ✓"
    return 0
}

# =============================================================================
# 健康检查
# =============================================================================
health_check() {
    section "阶段 5/8: 健康检查"
    DEPLOYMENT_STATUS="HEALTH_CHECK"
    
    log "执行全面健康检查..."
    
    local backend_port=$( [ "$TARGET_ENV" = "BLUE" ] && echo "$BLUE_BACKEND_PORT" || echo "$GREEN_BACKEND_PORT" )
    local frontend_port=$( [ "$TARGET_ENV" = "BLUE" ] && echo "$BLUE_FRONTEND_PORT" || echo "$GREEN_FRONTEND_PORT" )
    
    local retry_count=0
    local health_passed=false
    
    while [ $retry_count -lt $MAX_RETRY_ATTEMPTS ]; do
        log "健康检查尝试 $((retry_count + 1))/$MAX_RETRY_ATTEMPTS..."
        
        # 检查容器状态
        local all_healthy=true
        for container in "smartalbum-backend-$TARGET_ENV" "smartalbum-frontend-$TARGET_ENV"; do
            local status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
            if [ "$status" != "healthy" ]; then
                log "  容器 $container 状态: $status"
                all_healthy=false
            fi
        done
        
        if [ "$all_healthy" = true ]; then
            # 验证API响应
            if curl -sf "http://localhost:$backend_port/api/health" > /dev/null 2>&1; then
                log "  ✓ 后端健康检查通过"
                
                # 验证前端
                if curl -sf "http://localhost:$frontend_port" > /dev/null 2>&1; then
                    log "  ✓ 前端健康检查通过"
                    health_passed=true
                    break
                fi
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $MAX_RETRY_ATTEMPTS ]; then
            log "  等待 ${HEALTH_CHECK_INTERVAL} 秒后重试..."
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    if [ "$health_passed" = false ]; then
        error "健康检查失败，部署终止"
        return 1
    fi
    
    # 详细健康检查
    log "执行详细功能验证..."
    
    # API 响应时间测试
    local response_time=$(curl -o /dev/null -s -w "%{time_total}" "http://localhost:$backend_port/api/health")
    log "  API 响应时间: ${response_time}s"
    
    if (( $(echo "$response_time > 2.0" | bc -l) )); then
        warn "API 响应时间较慢，但仍在可接受范围"
    fi
    
    log "健康检查通过 ✓"
    return 0
}

# =============================================================================
# 数据迁移检查
# =============================================================================
migration_check() {
    section "阶段 6/8: 数据迁移检查"
    DEPLOYMENT_STATUS="MIGRATION"
    
    log "检查数据迁移状态..."
    
    # 执行数据库完整性检查
    if [ -f "data/smartalbum.db" ]; then
        log "检查数据库完整性..."
        if sqlite3 data/smartalbum.db "PRAGMA integrity_check;" | grep -q "ok"; then
            log "  ✓ 数据库完整性正常"
        else
            error "数据库完整性检查失败"
            return 1
        fi
        
        # 统计记录数
        local photo_count=$(sqlite3 data/smartalbum.db "SELECT COUNT(*) FROM photos;" 2>/dev/null || echo "0")
        local album_count=$(sqlite3 data/smartalbum.db "SELECT COUNT(*) FROM albums;" 2>/dev/null || echo "0")
        log "  照片数量: $photo_count"
        log "  相册数量: $album_count"
    fi
    
    # 检查向量数据
    if [ -d "data/chroma" ]; then
        log "检查向量数据..."
        local chroma_size=$(du -sh data/chroma 2>/dev/null | cut -f1)
        log "  ChromaDB 大小: $chroma_size"
        log "  ✓ 向量数据存在"
    fi
    
    # 检查存储目录
    local storage_count=$(find storage -type f 2>/dev/null | wc -l)
    log "  存储文件数量: $storage_count"
    
    log "数据迁移检查完成 ✓"
    return 0
}

# =============================================================================
# 切换流量
# =============================================================================
switch_traffic() {
    section "阶段 7/8: 切换流量"
    DEPLOYMENT_STATUS="TRAFFIC_SWITCH"
    
    log "准备切换流量到 $TARGET_ENV 环境..."
    
    local target_port=$( [ "$TARGET_ENV" = "BLUE" ] && echo "$BLUE_FRONTEND_PORT" || echo "$GREEN_FRONTEND_PORT" )
    
    # 检查Nginx配置
    if [ -f "/etc/nginx/nginx.conf" ] || [ -d "/etc/nginx/conf.d" ]; then
        log "更新 Nginx upstream 配置..."
        
        # 创建新的upstream配置
        sudo tee /etc/nginx/conf.d/smartalbum-upstream.conf > /dev/null << EOF
upstream smartalbum_backend {
    server localhost:$target_port;
}
EOF
        
        # 测试Nginx配置
        if sudo nginx -t; then
            log "  ✓ Nginx 配置测试通过"
            
            # 平滑重载Nginx
            if sudo nginx -s reload; then
                log "  ✓ Nginx 重载成功"
            else
                error "Nginx 重载失败"
                return 1
            fi
        else
            error "Nginx 配置测试失败"
            return 1
        fi
    else
        # 如果没有Nginx，直接修改docker端口映射
        warn "未检测到 Nginx，使用 Docker 端口切换"
        
        # 停止旧环境
        if [ "$ACTIVE_ENV" != "NONE" ]; then
            log "停止旧环境 ($ACTIVE_ENV)..."
            local old_compose="docker-compose.$ACTIVE_ENV.yml"
            if [ -f "$old_compose" ]; then
                docker-compose -f "$old_compose" down 2>/dev/null || true
            fi
        fi
        
        # 修改目标环境端口映射到80
        log "将 $TARGET_ENV 环境绑定到端口 80..."
        local compose_file="docker-compose.$TARGET_ENV.yml"
        docker-compose -f "$compose_file" stop frontend-$TARGET_ENV
        
        # 使用sed修改端口映射
        sed -i "s/- \"${target_port}:80\"/- \"80:80\"/" "$compose_file"
        docker-compose -f "$compose_file" up -d frontend-$TARGET_ENV
    fi
    
    log "流量已切换到 $TARGET_ENV 环境 ✓"
    
    # 等待流量稳定
    log "等待流量稳定 (10秒)..."
    sleep 10
    
    return 0
}

# =============================================================================
# 监控验证
# =============================================================================
monitor_verification() {
    section "阶段 8/8: 监控验证"
    DEPLOYMENT_STATUS="MONITORING"
    
    log "开始部署后监控 (持续5分钟)..."
    
    local monitor_duration=300  # 5分钟
    local check_interval=30
    local elapsed=0
    local error_count=0
    local max_errors=3
    
    while [ $elapsed -lt $monitor_duration ]; do
        local current_time=$(date '+%H:%M:%S')
        log "[$current_time] 监控检查..."
        
        # 检查HTTP状态
        local http_code=$(curl -o /dev/null -s -w "%{http_code}" "http://localhost/api/health" 2>/dev/null || echo "000")
        
        if [ "$http_code" != "200" ]; then
            error_count=$((error_count + 1))
            warn "  HTTP 状态异常: $http_code (错误次数: $error_count/$max_errors)"
            
            if [ $error_count -ge $max_errors ]; then
                error "连续错误次数过多，触发回滚"
                return 1
            fi
        else
            error_count=0
            log "  ✓ 服务响应正常 (HTTP $http_code)"
        fi
        
        # 检查响应时间
        local response_time=$(curl -o /dev/null -s -w "%{time_total}" "http://localhost/api/health" 2>/dev/null || echo "999")
        if (( $(echo "$response_time > 5.0" | bc -l 2>/dev/null || echo "1") )); then
            warn "  响应时间较长: ${response_time}s"
        fi
        
        elapsed=$((elapsed + check_interval))
        
        if [ $elapsed -lt $monitor_duration ]; then
            sleep $check_interval
        fi
    done
    
    log "监控验证通过 ✓"
    DEPLOYMENT_STATUS="COMPLETED"
    
    return 0
}

# =============================================================================
# 完成部署
# =============================================================================
finish_deployment() {
    section "部署完成"
    
    log "=============================================="
    log "  部署成功完成!"
    log "=============================================="
    log "目标环境: $TARGET_ENV"
    log "备份文件: $BACKUP_PATH"
    log "日志文件: $LOG_FILE"
    log ""
    log "当前运行容器:"
    docker ps --filter "name=smartalbum" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    log ""
    log "如果需要回滚，执行:"
    log "  $SCRIPT_DIR/quick-rollback.sh $BACKUP_PATH"
    log ""
    log "建议继续监控系统24小时"
    log "=============================================="
    
    # 发送成功通知（如果配置了）
    if [ -n "${WEBHOOK_URL:-}" ]; then
        curl -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"SmartAlbum 部署成功 - 环境: $TARGET_ENV, 版本: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')\"}" \
            "$WEBHOOK_URL" 2>/dev/null || true
    fi
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    init_logging
    
    section "SmartAlbum 生产环境升级"
    log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "项目目录: $PROJECT_ROOT"
    log "日志文件: $LOG_FILE"
    log ""
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        warn "建议以 root 权限运行此脚本以确保Nginx配置更新"
    fi
    
    # 切换到项目目录
    cd "$PROJECT_ROOT"
    
    # 执行部署流程
    pre_deployment_check || exit 1
    execute_backup || exit 1
    determine_target_environment || exit 1
    build_new_version || exit 1
    health_check || exit 1
    migration_check || exit 1
    switch_traffic || exit 1
    monitor_verification || {
        error "监控验证失败，准备回滚..."
        "$SCRIPT_DIR/quick-rollback.sh" "$BACKUP_PATH"
        exit 1
    }
    
    finish_deployment
}

# 处理命令行参数
case "${1:-}" in
    --help|-h)
        echo "SmartAlbum 生产环境升级脚本"
        echo ""
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h     显示此帮助信息"
        echo "  --skip-backup  跳过备份步骤（不推荐）"
        echo ""
        echo "环境变量:"
        echo "  BLUE_FRONTEND_PORT     蓝环境前端端口 (默认: 8081)"
        echo "  BLUE_BACKEND_PORT      蓝环境后端端口 (默认: 9999)"
        echo "  GREEN_FRONTEND_PORT    绿环境前端端口 (默认: 8082)"
        echo "  GREEN_BACKEND_PORT     绿环境后端端口 (默认: 9998)"
        echo "  HEALTH_CHECK_TIMEOUT   健康检查超时 (默认: 60)"
        echo "  WEBHOOK_URL            部署通知Webhook"
        exit 0
        ;;
    --skip-backup)
        SKIP_BACKUP=true
        warn "跳过备份步骤，生产环境不推荐!"
        ;;
esac

# 运行主函数
main
