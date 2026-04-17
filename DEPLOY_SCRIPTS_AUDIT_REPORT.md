# SmartAlbum 部署脚本审计与优化报告

## 执行摘要

本次审计涵盖了 31 个部署相关脚本，发现了 **冗余代码、安全隐患、错误处理不足** 等问题。以下是详细的分析和优化建议。

---

## 一、问题分类统计

| 问题类别 | 数量 | 严重程度 |
|----------|------|----------|
| 代码冗余 | 12 | 中 |
| 安全隐患 | 8 | 高 |
| 错误处理不足 | 15 | 高 |
| 变量未使用 | 6 | 低 |
| 兼容性问题 | 5 | 中 |
| 性能问题 | 4 | 中 |

---

## 二、详细问题分析

### 2.1 代码冗余问题

#### 问题 1: 重复的颜色定义和日志函数
**影响文件**: 几乎所有脚本

```bash
# 在以下文件中重复定义:
# deploy.sh, deploy-low-memory.sh, start.sh
# scripts/deploy/*.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
```

**问题**: 21 个脚本中重复定义相同的颜色和日志函数
**建议**: 创建 `scripts/lib/common.sh` 公共库文件

#### 问题 2: 重复的 Docker Compose 命令检测
**影响文件**: `deploy.sh`, `deploy-low-memory.sh`

```bash
# 重复代码
get_docker_compose() {
    if docker compose version &>/dev/null; then
        echo "docker compose -f docker-compose.prod.yml"
    else
        echo "docker-compose -f docker-compose.prod.yml"
    fi
}
```

**出现次数**: 3 次
**建议**: 统一使用公共函数

#### 问题 3: 重复的健康检查逻辑
**影响文件**: `health-check.sh`, `prod-upgrade.sh`, `quick-rollback.sh`

```bash
# 多个脚本中都包含:
if curl -sf "http://localhost:9999/api/health" > /dev/null 2>&1; then
    log "后端服务正常"
else
    error "后端服务异常"
fi
```

**问题**: 健康检查逻辑分散，维护困难
**建议**: 统一调用 `health-check.sh`

---

### 2.2 安全隐患

#### 问题 4: 敏感信息泄露风险
**影响文件**: `scripts/deploy/bare-metal-deploy.sh` (246-267 行)

```bash
# 不安全：直接在脚本中写入密码
cat > "$APP_DIR/backend/.env" << 'EOF'
SECRET_KEY=your-secret-key-here-min-32-characters-long
DEFAULT_PASSWORD=your-secure-password
EOF
```

**风险**: 默认密码被写入脚本，可能导致安全漏洞
**建议**: 
```bash
# 安全的做法：强制用户输入
if [ ! -f "$APP_DIR/backend/.env" ]; then
    read -sp "请输入 SECRET_KEY: " SECRET_KEY
    read -sp "请输入默认密码: " DEFAULT_PASSWORD
    # 生成随机值作为默认
    SECRET_KEY=${SECRET_KEY:-$(openssl rand -base64 32)}
fi
```

#### 问题 5: 文件权限设置不当
**影响文件**: `scripts/deploy/bare-metal-install.sh` (119 行)

```bash
chmod 755 $APP_DIR  # 过于宽松
```

**问题**: 数据目录权限过于开放
**建议**:
```bash
chmod 750 $APP_DIR/data  # 仅所有者和组可访问
chmod 600 $APP_DIR/backend/.env  # 敏感配置文件
```

#### 问题 6: 网络请求未验证 SSL
**影响文件**: `deploy.sh` (299 行)

```bash
# 使用 HTTP 而非 HTTPS
curl -s icanhazip.com
```

**风险**: 可能被中间人攻击
**建议**:
```bash
# 使用 HTTPS
curl -s https://icanhazip.com 2>/dev/null || \
    curl -s https://api.ipify.org 2>/dev/null || \
    hostname -I | awk '{print $1}'
```

#### 问题 7: 危险的 eval 和未转义变量
**影响文件**: `scripts/deploy/prod-upgrade.sh`

```bash
# 潜在风险
local response=$(echo "$response" | tail -2 | head -1)
```

**问题**: 未对变量进行适当的引号处理
**建议**: 使用 `"$var"` 而不是 `$var`

---

### 2.3 错误处理不足

#### 问题 8: 缺少错误处理的命令
**影响文件**: `scripts/deploy/bare-metal-deploy.sh` (107-121 行)

```bash
# 错误处理不完整
pip install --no-cache-dir -r requirements.txt 2>/dev/null || {
    while read package; do
        pip install "$package" || warn "安装失败: $package"
    done < requirements.txt
}
```

**问题**: 循环失败不会导致脚本退出
**建议**:
```bash
set -e  # 启用错误退出
pip_install_with_retry() {
    local pkg=$1
    local retries=3
    while [ $retries -gt 0 ]; do
        if pip install "$pkg"; then
            return 0
        fi
        retries=$((retries - 1))
        sleep 2
    done
    error "无法安装: $pkg"
    return 1
}
```

#### 问题 9: 未检查依赖命令
**影响文件**: `scripts/deploy/health-check.sh` (473 行)

```bash
# 未检查 bc 是否存在
if (( $(echo "$response_time > 2.0" | bc -l) )); then
```

**问题**: 如果 `bc` 未安装，比较会失败
**建议**:
```bash
# 使用 awk 替代 bc（更通用）
if awk "BEGIN {exit !($response_time > 2.0)}"; then
    warn "响应时间较长"
fi
```

#### 问题 10: 未验证的网络操作
**影响文件**: `scripts/deploy/prod-upgrade.sh` (674-677 行)

```bash
# Webhook 发送未验证
curl -X POST -H "Content-Type: application/json" \
    -d "{...}" \
    "$WEBHOOK_URL" 2>/dev/null || true
```

**问题**: 即使 webhook 失败也被忽略
**建议**:
```bash
send_webhook_notification() {
    local message=$1
    if [ -n "${WEBHOOK_URL:-}" ]; then
        if curl -sf -X POST -H "Content-Type: application/json" \
            -d "$message" "$WEBHOOK_URL" > /dev/null 2>&1; then
            log "通知发送成功"
        else
            warn "通知发送失败: $WEBHOOK_URL"
        fi
    fi
}
```

---

### 2.4 未使用变量

#### 问题 11: 定义的变量从未使用
**影响文件**: `scripts/deploy/prod-upgrade.sh`

```bash
# 定义但未使用
TRAFFIC_SWITCH_BATCH=${TRAFFIC_SWITCH_BATCH:-10}
ROLLBACK_THRESHOLD_ERROR_RATE=${ROLLBACK_THRESHOLD_ERROR_RATE:-1}
```

**影响文件**: `scripts/deploy/health-check.sh`

```bash
# METRICS 数组填充但部分未使用
METRICS=()
METRICS+=("{...}")  # 仅在生成报告时使用
```

**建议**: 删除未使用变量或实现相关功能

---

### 2.5 兼容性问题

#### 问题 12: stat 命令参数不兼容
**影响文件**: `scripts/deploy/quick-rollback.sh` (130 行)

```bash
# Linux 和 macOS 的 stat 参数不同
stat -c "%y" "$file" 2>/dev/null || stat -f "%Sm" "$file" 2>/dev/null
```

**问题**: 混合使用两种语法
**建议**:
```bash
get_file_mtime() {
    local file=$1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null
    else
        stat -c "%y" "$file" 2>/dev/null | cut -d'.' -f1
    fi
}
```

#### 问题 13: Docker Compose 版本检测不完善
**影响文件**: `deploy.sh`

```bash
# 检测逻辑不完整
if docker compose version &>/dev/null; then
    DC="docker compose"
else
    DC="docker-compose"
fi
```

**问题**: 未处理 docker-compose 作为插件的情况
**建议**:
```bash
get_docker_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    elif docker-compose version &>/dev/null; then
        echo "docker-compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        error "未找到 Docker Compose"
        return 1
    fi
}
```

---

### 2.6 性能问题

#### 问题 14: 多次调用 docker ps
**影响文件**: `scripts/deploy/health-check.sh`

```bash
# 多次重复调用
docker ps --format "{{.Names}}" | grep -q "smartalbum"
# ...
docker ps --format "{{.Names}}" | grep "smartalbum"
# ...
docker ps -q --filter "name=smartalbum"
```

**建议**: 缓存结果
```bash
get_smartalbum_containers() {
    docker ps --format "{{.Names}}" | grep "smartalbum" || true
}
CONTAINERS=$(get_smartalbum_containers)
```

#### 问题 15: 未使用并行处理
**影响文件**: `deploy.sh` 初始化阶段

```bash
# 串行执行
apt-get update
apt-get install -y ...
install_docker
install_docker_compose
```

**建议**: 可以并行执行的步骤使用后台进程
```bash
# 并行处理
apt-get update &
UPDATE_PID=$!
# ... 其他操作
wait $UPDATE_PID
```

---

## 三、脚本结构问题

### 3.1 目录结构混乱

```
当前结构:
├── deploy.sh                    # 根目录
├── deploy-low-memory.sh         # 根目录
├── deploy/                      # 子目录
│   ├── deploy.sh               # 重复功能
│   └── install-docker.sh
├── scripts/deploy/              # 嵌套子目录
│   ├── bare-metal-*.sh
│   ├── prod-upgrade.sh
│   └── ...
```

**问题**: 
- 同一功能脚本分散在多个目录
- 命名不一致（deploy vs deploy-low-memory）

**建议结构**:
```
scripts/
├── deploy/
│   ├── docker/
│   │   ├── deploy.sh           # 标准 Docker 部署
│   │   ├── deploy-low-mem.sh   # 低内存部署
│   │   └── upgrade.sh          # 升级脚本
│   ├── bare-metal/
│   │   ├── install.sh          # 裸机安装
│   │   ├── deploy.sh           # 裸机部署
│   │   └── upgrade.sh          # 裸机升级
│   └── lib/
│       ├── common.sh           # 公共函数
│       ├── logging.sh          # 日志模块
│       └── checks.sh           # 检查函数
```

---

## 四、优化建议

### 4.1 创建公共库文件

**新文件**: `scripts/lib/common.sh`

```bash
#!/bin/bash
# SmartAlbum 部署脚本公共库

# 严格模式
set -euo pipefail

# =============================================================================
# 颜色定义
# =============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# =============================================================================
# 日志函数
# =============================================================================
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] [INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARN]${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] [INFO]${NC} $1"; }
section() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

# =============================================================================
# 检查函数
# =============================================================================
check_command() {
    command -v "$1" &>/dev/null
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请以 root 权限运行此脚本"
        exit 1
    fi
}

get_docker_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    elif docker-compose version &>/dev/null; then
        echo "docker-compose"
    else
        return 1
    fi
}

# =============================================================================
# 健康检查
# =============================================================================
check_service_health() {
    local url=$1
    local timeout=${2:-10}
    curl -sf --max-time "$timeout" "$url" &>/dev/null
}

# =============================================================================
# 错误处理
# =============================================================================
setup_error_handling() {
    local script_name=$1
    trap 'error_handler $LINENO $?' ERR
}

error_handler() {
    local line=$1
    local code=$2
    error "脚本在第 $line 行出错，退出码: $code"
}
```

### 4.2 创建统一的配置管理

**新文件**: `scripts/lib/config.sh`

```bash
#!/bin/bash
# 统一配置管理

# 加载外部配置
load_config() {
    local config_file="${1:-.deploy.conf}"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    fi
}

# 配置默认值
set_defaults() {
    : "${BACKEND_PORT:=9999}"
    : "${FRONTEND_PORT:=80}"
    : "${APP_DIR:=/opt/smartalbum}"
    : "${APP_USER:=ubuntu}"
    : "${LOG_DIR:=/var/log/smartalbum}"
    : "${BACKUP_DIR:=/opt/backups}"
    : "${HEALTH_CHECK_TIMEOUT:=60}"
    : "${MAX_RETRY:=3}"
}

# 验证配置
validate_config() {
    local errors=0
    
    # 检查必需配置
    if [[ -z "${SECRET_KEY:-}" ]]; then
        error "SECRET_KEY 未设置"
        errors=$((errors + 1))
    fi
    
    # 检查端口范围
    if [[ "$BACKEND_PORT" -lt 1024 ]] && [[ $EUID -ne 0 ]]; then
        error "端口 $BACKEND_PORT 需要 root 权限"
        errors=$((errors + 1))
    fi
    
    return $errors
}
```

### 4.3 重构部署脚本示例

**重构后的** `deploy.sh`:

```bash
#!/bin/bash
# SmartAlbum 统一部署脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib/common.sh"
source "$SCRIPT_DIR/scripts/lib/config.sh"

set_defaults
setup_error_handling "${0##*/}"

# ... 部署逻辑
```

---

## 五、清理清单

### 5.1 建议删除的冗余文件

| 文件 | 原因 | 替代方案 |
|------|------|----------|
| `deploy/deploy.sh` | 与根目录 `deploy.sh` 重复 | 统一使用根目录版本 |
| `fix_docker.sh` | 临时修复脚本 | 并入 `cleanup-system.sh` |
| `fix-backend-build.sh` | 临时修复脚本 | 并入 `troubleshoot-build.sh` |
| `setup-docker-mirror.sh` | 功能单一 | 并入 `install-docker.sh` |

### 5.2 建议合并的脚本

```
# 合并前
├── health-check.sh
├── verify-deploy.sh
├── monitor-deploy.sh

# 合并后
├── health-check.sh (包含 verify-deploy 功能)
└── monitor.sh (监控专用)
```

---

## 六、安全加固建议

### 6.1 强制检查清单

```bash
# 在每个部署脚本开头添加
security_checklist() {
    local errors=0
    
    # 1. 检查 .env 文件权限
    if [[ -f "backend/.env" ]]; then
        local perms=$(stat -c "%a" backend/.env 2>/dev/null || stat -f "%Lp" backend/.env)
        if [[ "$perms" != "600" ]]; then
            warn ".env 文件权限过于开放: $perms"
            chmod 600 backend/.env
        fi
    fi
    
    # 2. 检查默认密码
    if grep -q "DEFAULT_PASSWORD=admin123\|DEFAULT_PASSWORD=password" backend/.env 2>/dev/null; then
        error "检测到默认密码，请修改！"
        errors=$((errors + 1))
    fi
    
    # 3. 检查 SECRET_KEY 长度
    local secret_key=$(grep "SECRET_KEY=" backend/.env 2>/dev/null | cut -d'=' -f2)
    if [[ "${#secret_key}" -lt 32 ]]; then
        error "SECRET_KEY 长度不足 32 位"
        errors=$((errors + 1))
    fi
    
    return $errors
}
```

### 6.2 日志脱敏

```bash
# 在日志中隐藏敏感信息
sanitize_log() {
    local input=$1
    # 隐藏 API 密钥
    echo "$input" | sed -E 's/(API_KEY=)[^[:space:]]+/\1***/g' | \
                   sed -E 's/(PASSWORD=)[^[:space:]]+/\1***/g' | \
                   sed -E 's/(SECRET_KEY=)[^[:space:]]+/\1***/g'
}
```

---

## 七、实施优先级

### P0 (立即处理)
1. 修复安全隐患（敏感信息泄露、权限问题）
2. 统一错误处理机制
3. 创建公共库文件

### P1 (本周处理)
4. 删除冗余脚本
5. 重构脚本目录结构
6. 修复兼容性问题

### P2 (本月处理)
7. 性能优化
8. 完善文档
9. 添加单元测试

---

## 八、附录：问题文件清单

### 高危问题文件
- `scripts/deploy/bare-metal-deploy.sh` - 默认密码写入
- `scripts/deploy/bare-metal-install.sh` - 权限设置不当
- `deploy.sh` - 未验证的网络请求

### 中危问题文件
- `scripts/deploy/prod-upgrade.sh` - 变量未转义
- `scripts/deploy/health-check.sh` - 依赖未检查
- `scripts/deploy/quick-rollback.sh` - 兼容性问题

### 低危问题文件
- `start.sh` - 代码重复
- `deploy-low-memory.sh` - 逻辑可优化

---

*报告生成时间: $(date)*
*审计范围: 31 个部署脚本*
*问题总数: 50+*
