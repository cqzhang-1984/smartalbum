#!/bin/bash
# SmartAlbum 部署管理脚本
# 功能: 统一的部署管理入口，简化操作
# 作者: SmartAlbum DevOps Team
# 版本: 1.0.0

set -euo pipefail

# =============================================================================
# 配置
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# 显示函数
# =============================================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ____                       _       _             _"
    echo " / ___| _ __ ___   __ _ _ __| | __ _| |_ ___  _ __| |"
    echo " \\___ \\| '_  _ \\ / _  | '__| |/ _  | __/ _ \\| '__| |"
    echo "  ___) | | | | | | (_| | |  | | (_| | || (_) | |  |_|"
    echo " |____/|_| |_| |_|\\__,_|_|  |_|\\__,_|\\__\\___/|_|  (_)"
    echo ""
    echo -e "  ${NC}部署管理系统 v1.0.0${NC}"
    echo ""
}

show_menu() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  主菜单${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}部署操作:${NC}"
    echo "  1) 执行完整部署 (零停机蓝绿部署)"
    echo "  2) 执行快速部署 (跳过备份)"
    echo "  3) 仅构建新版本"
    echo ""
    echo -e "${YELLOW}检查与监控:${NC}"
    echo "  4) 运行健康检查"
    echo "  5) 运行数据迁移检查"
    echo "  6) 启动部署监控"
    echo ""
    echo -e "${RED}回滚操作:${NC}"
    echo "  7) 执行快速回滚"
    echo "  8) 查看可用备份"
    echo ""
    echo -e "${BLUE}维护操作:${NC}"
    echo "  9) 查看服务状态"
    echo " 10) 查看日志"
    echo " 11) 执行全量备份"
    echo ""
    echo "  0) 退出"
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

# =============================================================================
# 操作函数
# =============================================================================
do_full_deploy() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  执行完整部署${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "这将执行:"
    echo "  1. 预部署检查"
    echo "  2. 全量备份"
    echo "  3. 蓝绿部署"
    echo "  4. 健康检查"
    echo "  5. 流量切换"
    echo "  6. 监控验证"
    echo ""
    read -p "确认执行? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/prod-upgrade.sh"
        echo ""
        read -p "按回车键继续..."
    fi
}

do_quick_deploy() {
    echo -e "${YELLOW}警告: 快速部署跳过备份步骤!${NC}"
    echo "仅在紧急修复时使用。"
    echo ""
    read -p "确认执行快速部署? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/prod-upgrade.sh" --skip-backup
        echo ""
        read -p "按回车键继续..."
    fi
}

do_build_only() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  仅构建新版本${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    cd "$PROJECT_ROOT"
    
    echo "构建后端..."
    docker-compose -f docker-compose.prod.yml build backend || true
    
    echo ""
    echo "构建前端..."
    docker-compose -f docker-compose.prod.yml build frontend || true
    
    echo ""
    echo -e "${GREEN}构建完成!${NC}"
    read -p "按回车键继续..."
}

do_health_check() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  运行健康检查${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    bash "$SCRIPT_DIR/health-check.sh" --verbose
    echo ""
    read -p "按回车键继续..."
}

do_migration_check() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  运行数据迁移检查${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    bash "$SCRIPT_DIR/migration-check.sh"
    echo ""
    read -p "按回车键继续..."
}

do_monitor() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  启动部署监控${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "监控选项:"
    echo "  1) 后台监控 (5分钟)"
    echo "  2) 交互式监控"
    echo "  3) 自定义时长"
    echo ""
    read -p "选择: " monitor_choice
    
    case $monitor_choice in
        1)
            echo "启动后台监控..."
            bash "$SCRIPT_DIR/monitor-deploy.sh" --duration 300 &
            echo -e "${GREEN}后台监控已启动 (PID: $!)${NC}"
            ;;
        2)
            bash "$SCRIPT_DIR/monitor-deploy.sh" --interactive
            ;;
        3)
            read -p "输入监控时长 (秒): " duration
            bash "$SCRIPT_DIR/monitor-deploy.sh" --duration "$duration"
            ;;
    esac
    
    read -p "按回车键继续..."
}

do_rollback() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  执行回滚${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "选项:"
    echo "  1) 使用最新备份回滚"
    echo "  2) 选择备份文件回滚"
    echo "  3) 紧急回滚 (跳过确认)"
    echo ""
    read -p "选择: " rollback_choice
    
    case $rollback_choice in
        1)
            bash "$SCRIPT_DIR/quick-rollback.sh"
            ;;
        2)
            bash "$SCRIPT_DIR/quick-rollback.sh" --list
            echo ""
            read -p "输入备份文件名 (完整路径): " backup_file
            if [ -n "$backup_file" ]; then
                bash "$SCRIPT_DIR/quick-rollback.sh" "$backup_file"
            fi
            ;;
        3)
            bash "$SCRIPT_DIR/quick-rollback.sh" --emergency
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
}

do_list_backups() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  可用备份列表${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    bash "$SCRIPT_DIR/quick-rollback.sh" --list
    echo ""
    read -p "按回车键继续..."
}

do_show_status() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  服务状态${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    echo -e "${BLUE}--- Docker 容器 ---${NC}"
    docker ps --filter "name=smartalbum" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "无运行中的容器"
    
    echo ""
    echo -e "${BLUE}--- 系统资源 ---${NC}"
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")%"
    echo "内存: $(free -h | awk 'NR==2{printf "%s/%s (%.2f%%)", $3,$2,$3*100/$2}')"
    echo "磁盘: $(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')"
    
    echo ""
    read -p "按回车键继续..."
}

do_show_logs() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  查看日志${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "选择日志类型:"
    echo "  1) 后端应用日志"
    echo "  2) Nginx 访问日志"
    echo "  3) Nginx 错误日志"
    echo "  4) 部署日志"
    echo "  5) 健康检查日志"
    echo "  6) Docker 容器日志"
    echo ""
    read -p "选择: " log_choice
    
    case $log_choice in
        1)
            tail -n 100 "$PROJECT_ROOT/backend/logs/app.log" 2>/dev/null || echo "日志文件不存在"
            ;;
        2)
            sudo tail -n 100 /var/log/nginx/access.log 2>/dev/null || echo "日志文件不存在"
            ;;
        3)
            sudo tail -n 100 /var/log/nginx/error.log 2>/dev/null || echo "日志文件不存在"
            ;;
        4)
            ls -lt /var/log/smartalbum/deploy/*.log 2>/dev/null | head -5
            echo ""
            read -p "输入日志文件名查看: " log_file
            if [ -n "$log_file" ] && [ -f "$log_file" ]; then
                less "$log_file"
            fi
            ;;
        5)
            ls -lt /var/log/smartalbum/health/*.log 2>/dev/null | head -5
            ;;
        6)
            local container=$(docker ps --format "{{.Names}}" | grep "smartalbum" | head -1)
            if [ -n "$container" ]; then
                docker logs --tail 100 "$container"
            else
                echo "无运行中的容器"
            fi
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
}

do_backup() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  执行全量备份${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    read -p "确认执行全量备份? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/full-backup.sh"
        echo ""
        read -p "按回车键继续..."
    fi
}

# =============================================================================
# 主循环
# =============================================================================
main() {
    while true; do
        show_banner
        show_menu
        
        read -p "请输入选项 [0-11]: " choice
        
        case $choice in
            1) do_full_deploy ;;
            2) do_quick_deploy ;;
            3) do_build_only ;;
            4) do_health_check ;;
            5) do_migration_check ;;
            6) do_monitor ;;
            7) do_rollback ;;
            8) do_list_backups ;;
            9) do_show_status ;;
            10) do_show_logs ;;
            11) do_backup ;;
            0)
                echo -e "${GREEN}再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                sleep 1
                ;;
        esac
    done
}

# 检查是否在交互式终端
if [ -t 0 ]; then
    main
else
    echo "请在交互式终端运行此脚本"
    exit 1
fi
