# SmartAlbum 部署脚本使用指南

## 概述

本文档介绍 SmartAlbum 生产环境部署脚本的使用方法，包括零停机部署、健康检查、数据迁移验证和快速回滚等功能。

## 脚本清单

| 脚本 | 功能 | 使用场景 |
|------|------|----------|
| `deploy-manager.sh` | 交互式部署管理 | 推荐入口脚本 |
| `prod-upgrade.sh` | 零停机蓝绿部署 | 正式版本升级 |
| `health-check.sh` | 全面健康检查 | 部署前后验证 |
| `migration-check.sh` | 数据迁移检查 | 数据库变更后验证 |
| `quick-rollback.sh` | 快速回滚 | 故障恢复 |
| `monitor-deploy.sh` | 部署监控 | 实时监控部署过程 |
| `full-backup.sh` | 全量备份 | 部署前备份 |

---

## 快速开始

### 1. 使用交互式管理器 (推荐)

```bash
cd /path/to/smartalbum
./scripts/deploy/deploy-manager.sh
```

这将启动交互式菜单，引导您完成各种操作。

### 2. 命令行直接执行

#### 完整部署流程
```bash
./scripts/deploy/prod-upgrade.sh
```

#### 快速部署 (跳过备份，用于紧急修复)
```bash
./scripts/deploy/prod-upgrade.sh --skip-backup
```

#### 健康检查
```bash
./scripts/deploy/health-check.sh --verbose
```

#### 快速回滚
```bash
# 使用最新备份回滚
./scripts/deploy/quick-rollback.sh

# 使用指定备份回滚
./scripts/deploy/quick-rollback.sh /opt/backups/smartalbum_20260115_020000.tar.gz

# 紧急回滚 (跳过确认)
./scripts/deploy/quick-rollback.sh --emergency
```

---

## 详细使用说明

### prod-upgrade.sh - 零停机部署

**功能**: 执行完整的蓝绿部署流程，包括备份、构建、健康检查、流量切换和监控。

**环境变量**:
```bash
export BLUE_FRONTEND_PORT=8081      # 蓝环境前端端口
export BLUE_BACKEND_PORT=9999       # 蓝环境后端端口
export GREEN_FRONTEND_PORT=8082     # 绿环境前端端口
export GREEN_BACKEND_PORT=9998      # 绿环境后端端口
export HEALTH_CHECK_TIMEOUT=60      # 健康检查超时
export WEBHOOK_URL="https://..."    # 部署通知Webhook
```

**执行步骤**:
1. 预部署检查 (系统资源、Docker状态)
2. 执行全量备份
3. 确定目标环境 (蓝/绿)
4. 构建并启动新版本
5. 健康检查
6. 数据迁移检查
7. 流量切换
8. 监控验证 (5分钟)

**示例**:
```bash
# 标准部署
./scripts/deploy/prod-upgrade.sh

# 跳过备份 (不推荐用于生产)
./scripts/deploy/prod-upgrade.sh --skip-backup

# 查看帮助
./scripts/deploy/prod-upgrade.sh --help
```

---

### health-check.sh - 健康检查

**功能**: 全面检查系统健康状态，包括服务、数据库、存储和系统资源。

**检查项**:
- Docker 容器状态和健康状况
- API 响应时间和可用性
- 前端服务状态
- 数据库完整性
- 存储数据完整性
- 系统资源 (CPU/内存/磁盘)
- 网络连接
- 错误日志

**参数**:
```bash
./scripts/deploy/health-check.sh [选项]

选项:
  --help, -h           显示帮助
  --verbose, -v        详细输出
  --backend URL        指定后端地址
  --frontend URL       指定前端地址
  --webhook URL        告警Webhook地址
```

**示例**:
```bash
# 标准检查
./scripts/deploy/health-check.sh

# 详细检查
./scripts/deploy/health-check.sh --verbose

# 指定端点检查
./scripts/deploy/health-check.sh --backend http://192.168.1.100:9999
```

---

### migration-check.sh - 数据迁移检查

**功能**: 验证数据迁移前后的完整性和一致性。

**检查项**:
- 数据库完整性 (PRAGMA integrity_check)
- 表记录数对比
- 向量数据存在性
- 存储数据完整性
- 数据一致性验证
  - 照片-相册关联
  - 文件路径有效性
  - 孤立文件检测

**参数**:
```bash
./scripts/deploy/migration-check.sh [选项]

选项:
  --help, -h           显示帮助
  --before-db PATH     迁移前的数据库路径
  --after-db PATH      迁移后的数据库路径
  --compare            对比模式
```

**示例**:
```bash
# 检查当前数据库
./scripts/deploy/migration-check.sh

# 对比迁移前后
./scripts/deploy/migration-check.sh --compare --before-db /backup/smartalbum.db
```

---

### quick-rollback.sh - 快速回滚

**功能**: 一键回滚到上一版本，支持紧急模式和计划回滚。

**参数**:
```bash
./scripts/deploy/quick-rollback.sh [选项] [备份文件]

选项:
  -h, --help          显示帮助
  -e, --emergency     紧急模式 (跳过确认，最快回滚)
  -l, --list          列出可用的备份文件
  -y, --yes           自动确认
  --stop-only         仅停止当前环境
```

**回滚流程**:
1. 停止当前环境
2. 从备份恢复数据
3. 启动服务
4. 验证回滚

**示例**:
```bash
# 列出可用备份
./scripts/deploy/quick-rollback.sh --list

# 使用最新备份回滚
./scripts/deploy/quick-rollback.sh

# 使用指定备份回滚
./scripts/deploy/quick-rollback.sh /opt/backups/smartalbum_20260115_020000.tar.gz

# 紧急回滚 (跳过所有确认)
./scripts/deploy/quick-rollback.sh --emergency
```

---

### monitor-deploy.sh - 部署监控

**功能**: 实时监控部署过程，收集指标，触发告警。

**监控指标**:
- 系统资源 (CPU、内存、磁盘)
- 服务可用性
- 响应时间
- 错误率
- 容器健康状况

**参数**:
```bash
./scripts/deploy/monitor-deploy.sh [选项]

选项:
  --help, -h           显示帮助
  --duration SECONDS   监控时长 (默认: 300)
  --interval SECONDS   检查间隔 (默认: 10)
  --webhook URL        告警Webhook
  --interactive        交互模式
  --threshold-error N  错误率阈值 %
  --threshold-rt MS    响应时间阈值 ms
```

**示例**:
```bash
# 后台监控5分钟
./scripts/deploy/monitor-deploy.sh

# 交互式监控
./scripts/deploy/monitor-deploy.sh --interactive

# 监控10分钟，指定告警阈值
./scripts/deploy/monitor-deploy.sh --duration 600 --threshold-error 2 --threshold-rt 1500
```

---

### full-backup.sh - 全量备份

**功能**: 执行全量备份，包括数据库、向量数据、配置和代码。

**备份内容**:
- SQLite 数据库
- ChromaDB 向量数据
- 向量 JSON 备份
- 配置文件 (.env, docker-compose.yml)
- 存储文件索引
- Git 版本信息

**输出**:
- 备份位置: `/opt/backups/smartalbum_YYYYMMDD_HHMMSS.tar.gz`
- 保留策略: 30天自动清理

**示例**:
```bash
./scripts/deploy/full-backup.sh
```

---

## 环境要求

### 必需组件
- Bash 4.0+
- Docker 24.0+
- Docker Compose 2.0+
- curl
- sqlite3 (可选，用于数据库检查)
- bc (可选，用于数值计算)

### 目录权限
```bash
# 创建日志目录
sudo mkdir -p /var/log/smartalbum/{deploy,health,migration,monitor}
sudo chown -R $USER:$USER /var/log/smartalbum

# 创建备份目录
sudo mkdir -p /opt/backups
sudo chown -R $USER:$USER /opt/backups
```

---

## 典型部署流程

### 标准版本升级

```bash
# 1. 登录服务器
ssh user@production-server

# 2. 进入项目目录
cd /opt/smartalbum

# 3. 执行部署
./scripts/deploy/prod-upgrade.sh

# 4. 部署后监控
./scripts/deploy/monitor-deploy.sh --duration 600
```

### 紧急修复

```bash
# 1. 快速部署 (跳过备份)
./scripts/deploy/prod-upgrade.sh --skip-backup

# 2. 立即验证
./scripts/deploy/health-check.sh --verbose
```

### 故障回滚

```bash
# 1. 紧急回滚
./scripts/deploy/quick-rollback.sh --emergency

# 2. 验证回滚
./scripts/deploy/health-check.sh

# 3. 问题诊断
./scripts/deploy/quick-rollback.sh --stop-only
# ... 诊断问题 ...
```

---

## 故障排查

### 常见问题

#### 1. 部署脚本无执行权限
```bash
chmod +x scripts/deploy/*.sh
```

#### 2. Docker 权限不足
```bash
# 将用户加入 docker 组
sudo usermod -aG docker $USER
# 重新登录或执行
newgrp docker
```

#### 3. 日志目录权限
```bash
sudo mkdir -p /var/log/smartalbum
sudo chown -R $USER:$USER /var/log/smartalbum
```

#### 4. 备份目录权限
```bash
sudo mkdir -p /opt/backups
sudo chown -R $USER:$USER /opt/backups
```

### 日志位置

```
/var/log/smartalbum/
├── deploy/
│   ├── deploy-YYYYMMDD_HHMMSS.log
│   └── rollback-YYYYMMDD_HHMMSS.log
├── health/
│   ├── health-check-YYYYMMDD_HHMMSS.log
│   └── health-report-YYYYMMDD_HHMMSS.json
├── migration/
│   ├── migration-check-YYYYMMDD_HHMMSS.log
│   └── migration-report-YYYYMMDD_HHMMSS.json
└── monitor/
    ├── monitor-YYYYMMDD_HHMMSS.log
    └── metrics-YYYYMMDD_HHMMSS.json
```

---

## 安全建议

1. **始终先备份**: 即使是紧急修复，也建议手动执行备份
2. **测试环境验证**: 在生产部署前，先在测试环境验证
3. **监控告警**: 配置 Webhook 接收部署通知
4. **限制权限**: 部署脚本应在受控环境下执行
5. **审计日志**: 保留所有部署和回滚日志

---

## 更新日志

### v1.0.0 (2026-04-15)
- 初始版本发布
- 支持蓝绿部署
- 支持零停机升级
- 支持自动健康检查
- 支持一键回滚

---

## 支持与反馈

如有问题或建议，请联系:
- 技术支持: devops@smartalbum.com
- 紧急联系: on-call@smartalbum.com
