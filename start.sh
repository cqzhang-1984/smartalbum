#!/bin/bash

# SmartAlbum 服务启动脚本 (Linux/macOS)
# 用法: 
#   ./start.sh          # 启动所有服务
#   ./start.sh backend  # 仅启动后端
#   ./start.sh frontend # 仅启动前端
#   ./start.sh stop     # 停止所有服务
#   ./start.sh status   # 检查端口状态
#   ./start.sh restart  # 重启所有服务
#   ./start.sh logs     # 查看日志

# 配置
BACKEND_PORT=9999
FRONTEND_PORT=8888  # 与 vite.config.ts 保持一致
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
LOGS_DIR="$PROJECT_ROOT/logs"
VENV_PYTHON="$BACKEND_DIR/venv/bin/python"

# 创建日志目录
mkdir -p "$LOGS_DIR"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 获取占用端口的进程ID
get_pid_on_port() {
    local port=$1
    if command -v lsof &> /dev/null; then
        lsof -t -i:$port 2>/dev/null | head -1
    elif command -v ss &> /dev/null; then
        ss -tlnp 2>/dev/null | grep ":$port " | grep -oP 'pid=\K[0-9]+' | head -1
    elif command -v netstat &> /dev/null; then
        netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | head -1
    fi
}

# 获取进程名称
get_process_name() {
    local pid=$1
    if [ -n "$pid" ]; then
        ps -p $pid -o comm= 2>/dev/null || echo "Unknown"
    else
        echo ""
    fi
}

# 显示端口状态
show_port_status() {
    local port=$1
    local service=$2
    
    local pid=$(get_pid_on_port $port)
    if [ -n "$pid" ]; then
        local process_name=$(get_process_name $pid)
        echo -e "  $service (Port $port): ${YELLOW}OCCUPIED${NC} by $process_name (PID:$pid)"
        return 0
    else
        echo -e "  $service (Port $port): ${GREEN}AVAILABLE${NC}"
        return 1
    fi
}

# 显示所有端口状态
show_all_port_status() {
    echo ""
    info "Port Status Check:"
    echo "----------------------------------------"
    local backend_occupied=0
    local frontend_occupied=0
    
    show_port_status $BACKEND_PORT "Backend " && backend_occupied=1
    show_port_status $FRONTEND_PORT "Frontend" && frontend_occupied=1
    
    echo "----------------------------------------"
    
    if [ $backend_occupied -eq 1 ] || [ $frontend_occupied -eq 1 ]; then
        return 1
    fi
    return 0
}

# 停止占用端口的进程
stop_port() {
    local port=$1
    local service=$2
    local graceful=$3
    local pid=$(get_pid_on_port $port)
    
    if [ -n "$pid" ]; then
        local process_name=$(get_process_name $pid)
        warn "端口 $port 被进程 $process_name (PID:$pid) 占用，正在停止..."
        
        # 优雅关闭（第一次尝试）
        if [ "$graceful" = "true" ]; then
            kill -TERM $pid 2>/dev/null
            sleep 1
            local new_pid=$(get_pid_on_port $port)
            if [ -z "$new_pid" ]; then
                success "已优雅停止 $process_name (PID:$pid)"
                return 0
            fi
        fi
        
        # 强制关闭
        kill -9 $pid 2>/dev/null
        sleep 1
        local new_pid=$(get_pid_on_port $port)
        if [ -n "$new_pid" ]; then
            error "无法停止进程 $pid"
            return 1
        fi
        success "已停止 $process_name (PID:$pid)"
    fi
    return 0
}

# 停止所有服务
stop_all() {
    info "停止所有服务..."
    stop_port $BACKEND_PORT "后端"
    stop_port $FRONTEND_PORT "前端"
    success "所有服务已停止"
    echo ""
    show_all_port_status
}

# 等待服务启动
wait_for_service() {
    local url=$1
    local max_wait=$2
    local service=$3
    
    local waited=0
    local interval=1
    
    printf "[INFO] 等待 $service 启动"
    while [ $waited -lt $max_wait ]; do
        sleep $interval
        waited=$((waited + interval))
        printf "."
        
        if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -q "200\|304"; then
            echo ""
            return 0
        fi
    done
    
    echo ""
    return 1
}

# 检查环境
check_environment() {
    info "检查运行环境..."
    
    # 检查 .env 文件
    if [ ! -f "$BACKEND_DIR/.env" ]; then
        warn ".env 文件不存在于 backend 目录"
        info "请创建 backend/.env 文件并配置必要参数"
    else
        success ".env file exists"
    fi
    
    # 检查 Python 虚拟环境
    if [ ! -f "$VENV_PYTHON" ]; then
        error "后端虚拟环境不存在: $VENV_PYTHON"
        info "请先运行: cd backend && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
        return 1
    fi
    success "Python venv found"
    
    # 检查 Node.js
    if ! command -v node &> /dev/null; then
        error "未找到 Node.js，请先安装 Node.js 18+"
        return 1
    fi
    success "Node.js 版本: $(node --version)"
    
    # 检查前端依赖
    if [ ! -d "$FRONTEND_DIR/node_modules" ]; then
        warn "前端依赖未安装，正在安装..."
        cd "$FRONTEND_DIR" && npm install
    else
        success "Frontend dependencies installed"
    fi
    
    return 0
}

# 启动后端
start_backend() {
    info "启动后端服务 (端口: $BACKEND_PORT)..."
    
    # 显示当前端口状态
    show_port_status $BACKEND_PORT "Backend "
    
    # 停止占用端口的进程（优雅关闭）
    stop_port $BACKEND_PORT "后端" "true"
    
    cd "$BACKEND_DIR"
    
    # 生成日志文件名
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local logfile="$LOGS_DIR/backend_$timestamp.log"
    
    info "日志文件: $logfile"
    
    # 后台启动
    nohup "$VENV_PYTHON" -m uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT > "$logfile" 2>&1 &
    echo $! > "$LOGS_DIR/backend.pid"
    
    # 创建符号链接到最新日志
    ln -sf "$logfile" "$LOGS_DIR/backend_latest.log"
    
    # 等待启动
    if wait_for_service "http://localhost:$BACKEND_PORT/" 15 "后端"; then
        success "后端服务启动成功!"
        info "API Docs: http://localhost:$BACKEND_PORT/docs"
    else
        warn "后端服务可能仍在启动中"
    fi
    
    return 0
}

# 启动前端
start_frontend() {
    info "启动前端服务 (端口: $FRONTEND_PORT)..."
    
    # 显示当前端口状态
    show_port_status $FRONTEND_PORT "Frontend"
    
    # 停止占用端口的进程（优雅关闭）
    stop_port $FRONTEND_PORT "前端" "true"
    
    cd "$FRONTEND_DIR"
    
    # 生成日志文件名
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local logfile="$LOGS_DIR/frontend_$timestamp.log"
    
    info "日志文件: $logfile"
    
    # 后台启动
    nohup npm run dev > "$logfile" 2>&1 &
    echo $! > "$LOGS_DIR/frontend.pid"
    
    # 创建符号链接到最新日志
    ln -sf "$logfile" "$LOGS_DIR/frontend_latest.log"
    
    # 等待启动
    if wait_for_service "http://localhost:$FRONTEND_PORT/" 20 "前端"; then
        success "前端服务启动成功!"
    else
        info "前端服务启动中 (Vite 可能需要更多时间)..."
    fi
    
    info "Frontend URL: http://localhost:$FRONTEND_PORT"
    return 0
}

# 显示信息
show_info() {
    echo ""
    echo "========================================"
    echo -e "     ${GREEN}服务启动完成!${NC}"
    echo "========================================"
    echo ""
    echo -e "后端 API:  ${GREEN}http://localhost:$BACKEND_PORT${NC}"
    echo -e "API 文档:  ${GREEN}http://localhost:$BACKEND_PORT/docs${NC}"
    echo -e "前端地址:  ${GREEN}http://localhost:$FRONTEND_PORT${NC}"
    echo ""
    echo -e "命令列表:"
    echo -e "  ${YELLOW}./start.sh status${NC}   # 检查端口状态"
    echo -e "  ${YELLOW}./start.sh stop${NC}     # 停止所有服务"
    echo -e "  ${YELLOW}./start.sh restart${NC}  # 重启所有服务"
    echo -e "  ${YELLOW}./start.sh logs${NC}     # 查看最近日志"
    echo -e "  ${YELLOW}tail -f logs/backend_latest.log${NC}  # 查看后端日志"
    echo -e "  ${YELLOW}tail -f logs/frontend_latest.log${NC} # 查看前端日志"
    echo ""
}

# 查看日志
show_logs() {
    local lines=${1:-50}
    info "最近日志 (最后 $lines 行):"
    echo ""
    
    if [ -f "$LOGS_DIR/backend_latest.log" ]; then
        echo "--- 后端日志 ---"
        tail -n $lines "$LOGS_DIR/backend_latest.log"
        echo ""
    fi
    
    if [ -f "$LOGS_DIR/frontend_latest.log" ]; then
        echo "--- 前端日志 ---"
        tail -n $lines "$LOGS_DIR/frontend_latest.log"
    fi
}

# 重启服务
restart_all() {
    info "重启所有服务..."
    stop_all
    sleep 2
    check_environment || exit 1
    start_backend
    sleep 2
    start_frontend
    show_info
}

# 主函数
main() {
    echo ""
    echo "========================================"
    echo -e "     ${CYAN}SmartAlbum 服务管理脚本${NC}"
    echo "========================================"
    
    case "$1" in
        status)
            show_all_port_status
            exit 0
            ;;
        stop)
            stop_all
            exit 0
            ;;
        restart)
            restart_all
            exit 0
            ;;
        logs)
            show_logs "$2"
            exit 0
            ;;
        backend)
            show_all_port_status
            check_environment || exit 1
            start_backend
            show_info
            ;;
        frontend)
            show_all_port_status
            check_environment || exit 1
            start_frontend
            show_info
            ;;
        *)
            show_all_port_status
            check_environment || exit 1
            start_backend
            sleep 2
            start_frontend
            show_info
            ;;
    esac
}

main "$@"
