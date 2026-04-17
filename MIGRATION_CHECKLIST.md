# SmartAlbum 裸机部署迁移检查清单

> 本文档用于指导从 Docker 容器部署迁移到裸机部署的完整流程

---

## 一、迁移前准备

### 1.1 服务器准备

- [ ] 确认腾讯云主机规格满足要求（推荐 4核8G）
- [ ] 确认磁盘空间充足（至少 50GB 可用）
- [ ] 确认 Ubuntu 版本（20.04/22.04 LTS）
- [ ] 已配置安全组，开放 80/443 端口
- [ ] 已配置 SSH 密钥登录

### 1.2 数据备份

- [ ] 执行全量数据备份
- [ ] 验证备份文件完整性
- [ ] 将备份文件下载到本地或异地存储
- [ ] 记录备份文件路径和 MD5 校验值

```bash
# 执行备份
./scripts/deploy/full-backup.sh

# 验证备份
md5sum /opt/backups/smartalbum_*.tar.gz
```

### 1.3 配置收集

- [ ] 导出 Docker 环境变量
- [ ] 记录当前端口映射
- [ ] 记录数据卷信息
- [ ] 保存 Nginx 配置

```bash
# 收集配置
docker exec smartalbum-backend cat /app/.env > backup/docker_env.txt
docker ps --format "table {{.Names}}\t{{.Ports}}" > backup/docker_ports.txt
docker volume ls | grep smartalbum > backup/docker_volumes.txt
```

### 1.4 代码准备

- [ ] 确认开发环境代码已提交
- [ ] 确认生产分支为最新代码
- [ ] 已测试生产环境配置
- [ ] 已准备好部署脚本

---

## 二、迁移执行

### 2.1 预检查

- [ ] 系统版本检查通过
- [ ] 内存检查通过（> 2GB）
- [ ] 磁盘空间检查通过（> 10GB）
- [ ] Docker 环境检测正常
- [ ] 项目代码完整性检查通过

### 2.2 系统初始化

- [ ] 系统软件源更新完成
- [ ] Python 3.11 安装完成
- [ ] Node.js 20 安装完成
- [ ] Redis 安装并配置完成
- [ ] Nginx 安装完成
- [ ] 编译依赖安装完成

```bash
# 验证安装
python3.11 --version
node --version
redis-cli ping
nginx -v
```

### 2.3 数据迁移

- [ ] 数据库导出完成
- [ ] 数据库导入完成
- [ ] 数据库完整性验证通过
- [ ] 向量数据迁移完成
- [ ] 照片文件迁移完成
- [ ] 配置文件迁移完成

```bash
# 执行数据迁移
sudo ./scripts/deploy/migrate-data.sh
```

### 2.4 后端部署

- [ ] 代码复制完成
- [ ] Python 虚拟环境创建完成
- [ ] 依赖安装完成
- [ ] 配置文件创建完成
- [ ] 数据库初始化完成

### 2.5 前端部署

- [ ] 代码复制完成
- [ ] npm 依赖安装完成
- [ ] 生产构建完成
- [ ] 构建输出验证通过

### 2.6 服务配置

- [ ] Systemd 后端服务配置完成
- [ ] Systemd Worker 服务配置完成
- [ ] Nginx 配置完成
- [ ] 服务启动测试通过

---

## 三、迁移后验证

### 3.1 服务状态检查

- [ ] 后端服务运行状态正常
- [ ] Worker 服务运行状态正常
- [ ] Redis 服务运行状态正常
- [ ] Nginx 服务运行状态正常

```bash
# 检查服务状态
sudo systemctl status smartalbum-backend
sudo systemctl status smartalbum-worker
sudo systemctl status redis-server
sudo systemctl status nginx
```

### 3.2 健康检查

- [ ] API 健康检查端点响应正常
- [ ] 前端页面访问正常
- [ ] 数据库连接正常
- [ ] Redis 连接正常

```bash
# 健康检查
curl http://localhost:9999/api/health
curl http://localhost/api/health
```

### 3.3 功能验证

- [ ] 用户登录功能正常
- [ ] 照片浏览功能正常
- [ ] 照片上传功能正常
- [ ] AI 分析功能正常
- [ ] 向量搜索功能正常
- [ ] 相册管理功能正常

### 3.4 数据完整性验证

- [ ] 照片数量与迁移前一致
- [ ] 相册数量与迁移前一致
- [ ] 用户数据完整
- [ ] AI 标签数据完整
- [ ] 向量索引完整

```bash
# 验证数据
sqlite3 /opt/smartalbum/data/smartalbum.db "SELECT COUNT(*) FROM photos;"
sqlite3 /opt/smartalbum/data/smartalbum.db "SELECT COUNT(*) FROM albums;"
```

### 3.5 性能验证

- [ ] 页面加载时间 < 3秒
- [ ] API 响应时间 < 1秒
- [ ] 上传速度正常
- [ ] 内存使用正常（< 80%）
- [ ] CPU 使用正常（< 80%）

---

## 四、回滚准备

### 4.1 回滚检查点

- [ ] Docker 容器镜像可用
- [ ] Docker Compose 文件完整
- [ ] 回滚脚本测试通过
- [ ] 数据备份可恢复

### 4.2 回滚测试

```bash
# 测试回滚脚本（不实际执行）
sudo ./scripts/deploy/rollback-to-docker.sh --dry-run
```

---

## 五、清理与优化

### 5.1 清理工作

- [ ] Docker 容器已停止（确认裸机稳定后）
- [ ] 临时文件已清理
- [ ] 旧数据备份已归档

### 5.2 监控配置

- [ ] 监控脚本已部署
- [ ] 定时任务已配置
- [ ] 日志轮转已配置

```bash
# 配置监控
crontab -l | grep smartalbum
```

### 5.3 性能优化

- [ ] SQLite WAL 模式已启用
- [ ] Nginx Gzip 已启用
- [ ] 静态文件缓存已配置
- [ ] 系统参数已优化

---

## 六、文档更新

- [ ] 部署文档已更新
- [ ] 运维手册已更新
- [ ] 回滚流程已记录
- [ ] 联系人信息已更新

---

## 七、应急联系

| 角色 | 姓名 | 联系方式 |
|------|------|----------|
| 技术负责人 | | |
| 运维负责人 | | |
| 业务负责人 | | |

---

## 八、迁移时间线

| 阶段 | 预计时间 | 实际时间 | 负责人 |
|------|----------|----------|--------|
| 预检查 | 15分钟 | | |
| 系统初始化 | 30分钟 | | |
| 数据迁移 | 根据数据量 | | |
| 应用部署 | 30分钟 | | |
| 验证测试 | 30分钟 | | |
| **总计** | **约2-4小时** | | |

---

## 九、常见问题处理

### Q1: 数据库迁移失败
```bash
# 手动修复
sqlite3 data/smartalbum.db ".recover" | sqlite3 data/smartalbum_fixed.db
mv data/smartalbum_fixed.db data/smartalbum.db
```

### Q2: 照片文件缺失
```bash
# 从 Docker 卷重新复制
docker cp smartalbum-backend:/app/storage/originals/ /opt/smartalbum/storage/
```

### Q3: 服务启动失败
```bash
# 查看日志
sudo journalctl -u smartalbum-backend -n 100 --no-pager
```

---

**检查清单版本**: 1.0  
**更新日期**: 2026-04-16  
**适用版本**: SmartAlbum >= 1.0.0
