# SmartAlbum 裸机部署脚本审查与优化报告

**审查日期:** 2026年4月17日  
**审查范围:** 所有部署相关脚本 (29个Shell脚本)  
**部署模式:** 裸机部署 (非Docker)  

---

## 执行摘要

针对裸机部署模式，现有29个脚本中：

| 分类 | 数量 | 处理方式 |
|------|------|----------|
| **裸机核心脚本** | 5 | 保留并优化 |
| **可废弃脚本** | 10 | 建议删除 |
| **需要适配修改** | 8 | 修改以支持裸机 |
| **通用工具脚本** | 4 | 保留 (已适配) |
| **公共库** | 2 | 保留并增强 |

---

## 一、脚本分类详细分析

### 1.1 裸机部署核心脚本 ✅ (保留并优化)

这些脚本是裸机部署的核心，应当保留并持续优化：

| 脚本路径 | 功能 | 状态 | 优化建议 |
|----------|------|------|----------|
| `scripts/deploy/bare-metal-deploy.sh` | 完整裸机部署 | ✅ 可用 | 已是最新版本 |
| `scripts/deploy/bare-metal-install.sh` | 首次安装 | ✅ 可用 | 合并到deploy中 |
| `scripts/deploy/bare-metal-upgrade.sh` | 裸机升级 | ✅ 可用 | 保留 |
| `start.sh` | 本地开发启动 | ✅ 可用 | 区分开发/生产模式 |
| `scripts/lib/common.sh` | 公共函数库 | ✅ 可用 | 增强日志功能 |
| `scripts/lib/config.sh` | 配置管理库 | ✅ 可用 | 保留 |

### 1.2 Docker专属脚本 ❌ (建议废弃)

这些脚本专用于Docker部署，在纯裸机模式下不再需要：

| 脚本路径 | 功能 | 废弃原因 | 风险等级 |
|----------|------|----------|----------|
| `deploy.sh` | Docker主部署脚本 | 完全依赖Docker | 🔴 高 |
| `deploy-low-memory.sh` | Docker低内存部署 | 完全依赖Docker | 🔴 高 |
| `debug-deploy.sh` | Docker调试脚本 | 完全依赖Docker | 🔴 高 |
| `deploy-manual.sh` | Docker手动部署 | 完全依赖Docker | 🔴 高 |
| `deploy/deploy-direct.sh` | Docker直接部署 | 完全依赖Docker | 🔴 高 |
| `deploy/install-docker.sh` | Docker安装 | 裸机不需要Docker | 🔴 高 |
| `scripts/deploy/setup-docker-mirror.sh` | Docker镜像加速 | 裸机不需要 | 🔴 高 |
| `scripts/deploy/troubleshoot-build.sh` | Docker构建排障 | 完全依赖Docker | 🔴 高 |
| `scripts/deploy/rollback-to-docker.sh` | 回滚到Docker | 与裸机模式冲突 | 🔴 高 |
| `scripts/deploy/prod-upgrade.sh` | Docker蓝绿部署 | 完全依赖Docker | 🔴 高 |
| `scripts/deploy/prod-upgrade-low-memory.sh` | Docker低内存升级 | 完全依赖Docker | 🔴 高 |

**废弃操作:**
```bash
# 建议删除以下文件
rm deploy.sh
rm deploy-low-memory.sh
rm debug-deploy.sh
rm deploy-manual.sh
rm -rf deploy/
rm scripts/deploy/setup-docker-mirror.sh
rm scripts/deploy/troubleshoot-build.sh
rm scripts/deploy/rollback-to-docker.sh
rm scripts/deploy/prod-upgrade.sh
rm scripts/deploy/prod-upgrade-low-memory.sh
```

### 1.3 需要适配修改的脚本 🟡 (修改以支持裸机)

这些脚本有Docker相关逻辑，需要修改以适配裸机部署：

#### A. health-check.sh (健康检查脚本)

**当前问题:**
- 大量使用 `docker` 命令检查服务状态
- 容器健康检查逻辑不适用于systemd服务

**需要的修改:**
```bash
# 修改前 (Docker方式)
check_docker_services() {
    local containers=$(docker ps --format '{{.Names}}')
    for container in $containers; do
        # 检查容器状态
    done
}

# 修改后 (裸机方式)
check_systemd_services() {
    local services=("smartalbum-backend" "smartalbum-frontend" "nginx")
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log_error "服务 $service 未运行"
        fi
    done
}
```

**修改点清单:**
1. 替换 `docker ps` 为 `systemctl status`
2. 替换容器日志检查为 `journalctl`
3. 替换容器资源监控为系统资源监控

#### B. deploy-manager.sh (部署管理器)

**当前问题:**
- 菜单选项针对Docker部署设计
- 调用 `prod-upgrade.sh` (Docker脚本)

**需要的修改:**
```bash
# 修改菜单选项
show_menu() {
    echo "部署操作:"
    echo "  1) 执行完整裸机部署"
    echo "  2) 执行快速裸机部署"
    echo "  3) 仅更新后端代码"
    echo "  4) 仅更新前端代码"
    # 移除Docker相关选项
}

# 修改调用路径
deploy_full() {
    # 修改前
    # ./scripts/deploy/prod-upgrade.sh
    
    # 修改后
    ./scripts/deploy/bare-metal-upgrade.sh
}
```

#### C. migrate-data.sh (数据迁移脚本)

**当前问题:**
- 包含Docker和裸机之间的双向迁移逻辑
- 主要用于迁移过渡阶段

**建议:**
- 如果已完成迁移，可以废弃
- 如果保留，需要清理Docker相关代码

#### D. migration-check.sh (迁移检查脚本)

**当前问题:**
- 对比Docker和裸机的数据状态
- 迁移完成后不再需要

**建议:**
```bash
# 如果迁移已完成，删除此脚本
rm scripts/deploy/migration-check.sh
```

#### E. monitor-deploy.sh (部署监控脚本)

**当前问题:**
- 监控Docker容器指标
- 使用 `docker stats` 获取资源使用

**需要的修改:**
```bash
# 修改资源获取方式
get_container_metrics() {
    # 修改前
    docker stats --no-stream --format ...
    
    # 修改后 - 获取systemd服务资源
    ps -p $(pgrep -f "smartalbum") -o %cpu,%mem
}
```

#### F. full-backup.sh (全量备份脚本)

**当前状态:** 需要轻微修改

**检查点:**
- ✅ 数据库备份逻辑通用
- ⚠️ 需要确认是否备份Docker卷 (如果已废弃Docker)
- ✅ 文件备份逻辑可用

**建议修改:**
```bash
# 添加备份前置检查
check_backup_prerequisites() {
    # 确认是裸机部署
    if [ -f "/etc/systemd/system/smartalbum-backend.service" ]; then
        log "检测到裸机部署，继续备份"
    else
        error "未检测到裸机部署，请检查部署方式"
        exit 1
    fi
}
```

#### G. quick-rollback.sh (快速回滚脚本)

**当前状态:** 大部分可用，需要适配

**需要的修改:**
```bash
# 修改服务停止逻辑
stop_services() {
    # 修改前 (Docker)
    docker-compose down
    
    # 修改后 (裸机)
    systemctl stop smartalbum-backend
    systemctl stop smartalbum-frontend
    # nginx保持运行
}

# 修改服务启动逻辑
start_services() {
    # 修改前 (Docker)
    docker-compose up -d
    
    # 修改后 (裸机)
    systemctl start smartalbum-backend
    systemctl start smartalbum-frontend
}
```

#### H. verify-deploy.sh (部署验证脚本)

**当前状态:** 需要轻微修改

**需要的修改:**
- 替换Docker容器检查为systemd服务检查
- 验证文件路径而不是容器挂载

### 1.4 通用工具脚本 ✅ (保留)

这些脚本已适配或原本就通用：

| 脚本 | 功能 | 状态 | 说明 |
|------|------|------|------|
| `scripts/deploy/cleanup-system.sh` | 系统清理 | ✅ 已适配 | 支持裸机清理 |
| `scripts/deploy/rollback.sh` | 通用回滚 | ✅ 可用 | 需要确认逻辑 |

### 1.5 公共库脚本 ✅ (保留并增强)

| 脚本 | 功能 | 状态 | 优化建议 |
|------|------|------|----------|
| `scripts/lib/common.sh` | 公共函数 | ✅ 已适配 | 已支持裸机和Docker |
| `scripts/lib/config.sh` | 配置管理 | ✅ 已适配 | 已支持多种部署方式 |

---

## 二、废弃脚本清单及操作步骤

### 2.1 立即废弃的脚本 (10个)

```bash
#!/bin/bash
# 废弃Docker专属脚本的执行清单

cd /opt/smartalbum  # 或项目根目录

# 1. 备份要删除的脚本到归档目录
mkdir -p scripts/archive/docker-scripts
cp deploy.sh scripts/archive/docker-scripts/
cp deploy-low-memory.sh scripts/archive/docker-scripts/
cp debug-deploy.sh scripts/archive/docker-scripts/
cp deploy-manual.sh scripts/archive/docker-scripts/
cp -r deploy/ scripts/archive/docker-scripts/
cp scripts/deploy/setup-docker-mirror.sh scripts/archive/docker-scripts/
cp scripts/deploy/troubleshoot-build.sh scripts/archive/docker-scripts/
cp scripts/deploy/rollback-to-docker.sh scripts/archive/docker-scripts/
cp scripts/deploy/prod-upgrade.sh scripts/archive/docker-scripts/
cp scripts/deploy/prod-upgrade-low-memory.sh scripts/archive/docker-scripts/

echo "✓ 已备份到 scripts/archive/docker-scripts/"

# 2. 删除Docker专属脚本
rm -f deploy.sh
rm -f deploy-low-memory.sh
rm -f debug-deploy.sh
rm -f deploy-manual.sh
rm -rf deploy/
rm -f scripts/deploy/setup-docker-mirror.sh
rm -f scripts/deploy/troubleshoot-build.sh
rm -f scripts/deploy/rollback-to-docker.sh
rm -f scripts/deploy/prod-upgrade.sh
rm -f scripts/deploy/prod-upgrade-low-memory.sh

echo "✓ 已删除10个Docker专属脚本"

# 3. 清理空的docker-compose文件 (可选)
# rm -f docker-compose.yml
# rm -f docker-compose.prod.yml
# rm -f docker-compose.low-memory.yml

echo "✓ 废弃完成"
```

### 2.2 废弃脚本的存档建议

创建归档目录结构：
```
scripts/archive/
├── docker-scripts/          # 废弃的Docker脚本
│   ├── deploy.sh
│   ├── deploy-low-memory.sh
│   └── ...
├── README.md               # 存档说明
└── migration-guide.md      # 迁移指南
```

**README.md 内容建议：**
```markdown
# 存档脚本说明

这些脚本已废弃，仅用于历史参考。

## 废弃原因
项目已全面转向裸机部署模式，不再使用Docker部署。

## 当前推荐脚本
- 部署: scripts/deploy/bare-metal-deploy.sh
- 升级: scripts/deploy/bare-metal-upgrade.sh
- 备份: scripts/deploy/full-backup.sh
```

---

## 三、需要修改的脚本详细方案

### 3.1 health-check.sh 修改方案

**修改范围:** 约30%的代码需要调整

**关键修改点:**

```bash
# =============================================================================
# 服务检查函数 (修改后)
# =============================================================================

check_services() {
    section "检查系统服务状态"
    
    local services=("smartalbum-backend" "smartalbum-frontend" "nginx" "redis")
    local all_ok=true
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            success "服务 $service 运行正常"
            
            # 获取服务PID和资源使用
            local pid=$(systemctl show --property=MainPID --value "$service")
            if [ "$pid" != "0" ]; then
                local cpu_mem=$(ps -p "$pid" -o %cpu=,%mem= 2>/dev/null || echo "N/A")
                info "  PID: $pid, CPU/MEM: $cpu_mem"
            fi
        else
            error "服务 $service 未运行"
            FAILED_CHECKS+=("service:$service")
            all_ok=false
        fi
    done
    
    $all_ok && success "所有服务运行正常"
}

# =============================================================================
# 日志检查函数 (修改后)
# =============================================================================

check_logs() {
    section "检查应用日志"
    
    # 检查最近24小时的错误日志
    local error_count=$(journalctl -u smartalbum-backend --since "24 hours ago" --grep="ERROR" --no-pager 2>/dev/null | wc -l)
    
    if [ "$error_count" -gt 50 ]; then
        warn "过去24小时有 $error_count 条错误日志"
        FAILED_CHECKS+=("logs:errors=$error_count")
    else
        success "错误日志数量正常: $error_count"
    fi
    
    # 检查磁盘空间
    local log_size=$(du -sm /var/log/smartalbum 2>/dev/null | cut -f1)
    if [ "$log_size" -gt 1024 ]; then
        warn "日志目录占用 ${log_size}MB，建议清理"
    fi
}
```

### 3.2 deploy-manager.sh 修改方案

**新的菜单结构:**

```bash
show_menu() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  SmartAlbum 裸机部署管理系统${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}部署操作:${NC}"
    echo "  1) 执行完整裸机部署"
    echo "  2) 执行快速裸机部署 (跳过测试)"
    echo "  3) 仅更新后端代码"
    echo "  4) 仅更新前端代码"
    echo "  5) 执行数据库迁移"
    echo ""
    echo -e "${YELLOW}检查与监控:${NC}"
    echo "  6) 运行健康检查"
    echo "  7) 查看系统状态"
    echo "  8) 查看实时日志"
    echo ""
    echo -e "${CYAN}维护操作:${NC}"
    echo "  9) 创建全量备份"
    echo " 10) 执行快速回滚"
    echo " 11) 清理系统日志"
    echo " 12) 重启所有服务"
    echo ""
    echo -e "${RED}危险操作:${NC}"
    echo " 99) 卸载 SmartAlbum"
    echo ""
    echo "  0) 退出"
    echo ""
}
```

### 3.3 创建新的裸机专属脚本

建议创建以下新脚本来完善裸机部署体系：

#### A. service-manager.sh (服务管理器)

```bash
#!/bin/bash
# SmartAlbum 服务管理脚本
# 统一管理 systemd 服务

SERVICE_BACKEND="smartalbum-backend"
SERVICE_FRONTEND="smartalbum-frontend"

start_services() {
    sudo systemctl start $SERVICE_BACKEND
    sudo systemctl start $SERVICE_FRONTEND
    sudo systemctl start nginx
}

stop_services() {
    sudo systemctl stop $SERVICE_BACKEND
    sudo systemctl stop $SERVICE_FRONTEND
    # nginx 保持运行
}

restart_services() {
    sudo systemctl restart $SERVICE_BACKEND
    sudo systemctl restart $SERVICE_FRONTEND
}

status_services() {
    systemctl status $SERVICE_BACKEND --no-pager
    systemctl status $SERVICE_FRONTEND --no-pager
}
```

#### B. log-viewer.sh (日志查看器)

```bash
#!/bin/bash
# SmartAlbum 日志查看脚本

view_backend_logs() {
    sudo journalctl -u smartalbum-backend -f
}

view_frontend_logs() {
    sudo journalctl -u smartalbum-frontend -f
}

view_access_logs() {
    sudo tail -f /var/log/nginx/access.log
}
```

---

## 四、脚本目录结构优化建议

### 4.1 当前结构问题

当前脚本分散在多个目录，缺乏统一管理：
```
当前结构 (混乱):
├── deploy.sh
├── deploy-low-memory.sh
├── deploy/
│   ├── deploy-direct.sh
│   └── install-docker.sh
├── scripts/
│   ├── deploy/
│   │   ├── bare-metal-deploy.sh
│   │   ├── prod-upgrade.sh
│   │   └── ...
│   └── lib/
└── start.sh
```

### 4.2 优化后的结构

建议重组为清晰的裸机部署结构：

```
建议结构 (清晰):
├── scripts/
│   ├── deploy/
│   │   ├── install.sh          # 首次安装 (原 bare-metal-install.sh)
│   │   ├── deploy.sh           # 完整部署 (原 bare-metal-deploy.sh)
│   │   ├── upgrade.sh          # 升级脚本 (原 bare-metal-upgrade.sh)
│   │   ├── rollback.sh         # 回滚脚本
│   │   └── verify.sh           # 部署验证
│   ├── manage/
│   │   ├── manager.sh          # 管理菜单 (原 deploy-manager.sh)
│   │   ├── service.sh          # 服务管理
│   │   ├── logs.sh             # 日志查看
│   │   └── health.sh           # 健康检查
│   ├── maintenance/
│   │   ├── backup.sh           # 备份
│   │   ├── cleanup.sh          # 清理
│   │   └── monitor.sh          # 监控
│   └── lib/
│       ├── common.sh
│       └── config.sh
├── bin/                        # 快捷方式
│   ├── smartalbum-deploy -> ../scripts/deploy/deploy.sh
│   ├── smartalbum-upgrade -> ../scripts/deploy/upgrade.sh
│   └── smartalbum-status -> ../scripts/manage/service.sh status
└── docs/
    └── deployment/
        ├── bare-metal-guide.md
        └── troubleshooting.md
```

### 4.3 重构执行步骤

```bash
#!/bin/bash
# 脚本目录重构执行脚本

cd /opt/smartalbum

# 1. 创建新目录结构
mkdir -p scripts/{deploy,manage,maintenance,lib}
mkdir -p bin
mkdir -p docs/deployment

# 2. 移动并重命名脚本
mv scripts/deploy/bare-metal-deploy.sh scripts/deploy/deploy.sh
mv scripts/deploy/bare-metal-install.sh scripts/deploy/install.sh
mv scripts/deploy/bare-metal-upgrade.sh scripts/deploy/upgrade.sh
mv scripts/deploy/deploy-manager.sh scripts/manage/manager.sh
mv scripts/deploy/health-check.sh scripts/manage/health.sh
mv scripts/deploy/full-backup.sh scripts/maintenance/backup.sh
mv scripts/deploy/cleanup-system.sh scripts/maintenance/cleanup.sh
mv scripts/deploy/quick-rollback.sh scripts/deploy/rollback.sh
mv scripts/deploy/verify-deploy.sh scripts/deploy/verify.sh

# 3. 创建快捷方式
ln -sf ../scripts/deploy/deploy.sh bin/smartalbum-deploy
ln -sf ../scripts/deploy/upgrade.sh bin/smartalbum-upgrade
ln -sf ../scripts/manage/manager.sh bin/smartalbum-manager

# 4. 移动文档
mv BARE_METAL_DEPLOYMENT_GUIDE.md docs/deployment/bare-metal-guide.md
mv DEPLOY.md docs/deployment/

# 5. 清理旧目录
rm -rf deploy/  # 删除旧的deploy目录

# 6. 更新环境变量
echo 'export PATH="/opt/smartalbum/bin:$PATH"' >> ~/.bashrc

echo "✓ 目录结构重构完成"
```

---

## 五、优化建议汇总

### 5.1 立即执行 (本周)

1. **废弃10个Docker专属脚本**
   - 备份后删除
   - 更新文档说明

2. **修改4个核心脚本**
   - health-check.sh: 替换Docker检查为systemd检查
   - deploy-manager.sh: 更新菜单选项
   - quick-rollback.sh: 适配systemd服务
   - verify-deploy.sh: 验证裸机部署

3. **创建2个新脚本**
   - service-manager.sh: 统一管理服务
   - log-viewer.sh: 便捷查看日志

### 5.2 短期优化 (本月)

1. **重构目录结构**
   - 按照4.2节的建议结构重组
   - 创建bin快捷方式
   - 更新所有文档引用

2. **统一脚本风格**
   - 所有脚本使用common.sh
   - 统一日志格式
   - 统一错误处理

3. **增强功能**
   - 添加更多健康检查项
   - 完善备份策略
   - 添加监控告警

### 5.3 长期规划

1. **自动化测试**
   - 为关键脚本添加单元测试
   - CI/CD流水线集成

2. **文档完善**
   - 编写详细的裸机部署指南
   - 添加故障排查手册
   - 创建视频教程

---

## 六、废弃脚本的影响评估

### 6.1 无影响的操作

以下操作在裸机模式下不受影响：

| 操作 | 替代脚本 | 说明 |
|------|----------|------|
| 部署 | bare-metal-deploy.sh | 功能更完善 |
| 升级 | bare-metal-upgrade.sh | 功能更完善 |
| 备份 | full-backup.sh | 已适配 |
| 回滚 | quick-rollback.sh | 修改后可用 |

### 6.2 需要注意的操作

如果团队中有成员习惯使用以下命令，需要提前通知：

```bash
# 旧命令 (将失效)
./deploy.sh
./deploy-low-memory.sh
./debug-deploy.sh
docker-compose up -d

# 新命令 (推荐使用)
./scripts/deploy/bare-metal-deploy.sh
sudo systemctl restart smartalbum-backend
./scripts/manage/manager.sh
```

### 6.3 回滚方案

如果废弃后需要恢复Docker部署：

```bash
# 1. 从存档恢复脚本
cp scripts/archive/docker-scripts/deploy.sh ./

# 2. 安装Docker
sudo apt-get install docker.io docker-compose

# 3. 切换部署方式
./scripts/deploy/rollback-to-docker.sh  # 如果保留了此脚本
```

---

## 七、总结

### 7.1 废弃清单

**共10个脚本建议废弃：**

1. deploy.sh (根目录)
2. deploy-low-memory.sh
3. debug-deploy.sh
4. deploy-manual.sh
5. deploy/ 目录 (2个脚本)
6. scripts/deploy/setup-docker-mirror.sh
7. scripts/deploy/troubleshoot-build.sh
8. scripts/deploy/rollback-to-docker.sh
9. scripts/deploy/prod-upgrade.sh
10. scripts/deploy/prod-upgrade-low-memory.sh

### 7.2 保留清单

**核心脚本 (5个)：**
- scripts/deploy/bare-metal-deploy.sh
- scripts/deploy/bare-metal-install.sh
- scripts/deploy/bare-metal-upgrade.sh
- start.sh
- scripts/lib/*.sh

**需要修改的脚本 (6个)：**
- scripts/deploy/health-check.sh
- scripts/deploy/deploy-manager.sh
- scripts/deploy/quick-rollback.sh
- scripts/deploy/full-backup.sh
- scripts/deploy/verify-deploy.sh
- scripts/deploy/monitor-deploy.sh

**可废弃的辅助脚本 (2个)：**
- scripts/deploy/migrate-data.sh
- scripts/deploy/migration-check.sh

### 7.3 预期效果

执行本次优化后：

1. **脚本数量减少:** 从29个减少到约19个 (减少35%)
2. **维护成本降低:** 无需维护Docker相关逻辑
3. **部署更清晰:** 所有脚本专注于裸机部署
4. **学习成本降低:** 新成员只需理解裸机部署流程

---

**报告结束**
