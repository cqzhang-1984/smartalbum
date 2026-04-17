# Docker脚本存档

## 说明

这些脚本已废弃，仅用于历史参考。

## 废弃原因

项目已全面转向裸机部署模式，不再使用Docker部署。

## 废弃日期

2026年4月17日

## 当前推荐脚本

- **部署**: `scripts/deploy/bare-metal-deploy.sh`
- **升级**: `scripts/deploy/bare-metal-upgrade.sh`
- **安装**: `scripts/deploy/bare-metal-install.sh`
- **备份**: `scripts/deploy/full-backup.sh`
- **管理**: `scripts/deploy/deploy-manager.sh`

## 存档脚本清单

| 脚本 | 原功能 |
|------|--------|
| deploy.sh | Docker主部署脚本 |
| deploy-low-memory.sh | Docker低内存部署 |
| debug-deploy.sh | Docker调试脚本 |
| deploy-manual.sh | Docker手动部署 |
| deploy-direct.sh | Docker直接部署 |
| install-docker.sh | Docker安装 |
| setup-docker-mirror.sh | Docker镜像加速配置 |
| troubleshoot-build.sh | Docker构建排障 |
| rollback-to-docker.sh | 回滚到Docker |
| prod-upgrade.sh | Docker蓝绿部署 |
| prod-upgrade-low-memory.sh | Docker低内存升级 |
