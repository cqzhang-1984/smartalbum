# SmartAlbum Docker 部署指南

## 系统要求

- **服务器**: 腾讯云 Lighthouse
- **操作系统**: Ubuntu Server 24.04 LTS 64bit
- **配置建议**: 
  - CPU: 2核+
  - 内存: 4GB+
  - 磁盘: 50GB+

## 端口说明

| 端口 | 用途 | 说明 |
|------|------|------|
| 5173 | 前端页面 | 通过 IP:5173 访问相册 |
| 9000 | 后端 API | FastAPI 服务端口 |

## 快速部署

### 1. 连接服务器

```bash
ssh ubuntu@<你的服务器IP>
```

### 2. 克隆代码

```bash
cd ~
git clone <你的代码仓库地址> SmartAlbum
cd SmartAlbum
```

### 3. 安装 Docker

```bash
chmod +x deploy/install-docker.sh
./deploy/install-docker.sh
```

安装完成后，**重新登录**服务器以应用权限。

### 4. 配置环境变量

```bash
cp backend/.env.example backend/.env
nano backend/.env
```

**必须配置项**（豆包AI）：
```ini
# AI模型配置（豆包多模态API）
AI_MODEL_NAME=doubao-seed-2-0-mini
AI_MODEL_ID=doubao-seed-2-0-mini-260215
AI_API_KEY=你的豆包API密钥
AI_API_BASE=https://ark.cn-beijing.volces.com/api/v3
AI_API_PATH=/responses

# 图片生成模型配置
IMAGE_GEN_MODEL_NAME=doubao-seedream-5-0
IMAGE_GEN_MODEL_ID=doubao-seedream-5-0-260128
IMAGE_GEN_API_KEY=你的豆包API密钥
```

### 5. 执行部署

```bash
chmod +x deploy/deploy.sh
./deploy/deploy.sh
```

### 6. 访问应用

部署完成后，通过浏览器访问：
```
http://<服务器IP>:5173
```

## 常用操作

### 查看日志

```bash
# 查看所有服务日志
docker compose logs -f

# 只看后端日志
docker compose logs -f backend

# 只看前端日志
docker compose logs -f frontend
```

### 停止服务

```bash
docker compose down
```

### 重启服务

```bash
docker compose restart
```

### 更新代码后重新部署

```bash
# 拉取最新代码
git pull

# 重新构建并启动
docker compose down
docker compose build --no-cache
docker compose up -d
```

### 备份数据

```bash
# 备份数据库和照片
tar -czvf smartalbum-backup-$(date +%Y%m%d).tar.gz data/ storage/
```

### 恢复数据

```bash
# 解压备份到项目目录
tar -xzvf smartalbum-backup-20240101.tar.gz
```

## 防火墙配置

如果无法访问，请检查防火墙：

```bash
# 查看防火墙状态
sudo ufw status

# 允许端口
sudo ufw allow 5173/tcp
sudo ufw allow 9000/tcp

# 启用防火墙（如果未启用）
sudo ufw enable
```

## 故障排查

### 容器无法启动

```bash
# 查看详细日志
docker compose logs

# 检查端口占用
sudo netstat -tlnp | grep -E '5173|9000'
```

### 前端无法连接后端

1. 检查后端是否正常运行：
```bash
curl http://localhost:9000/health
```

2. 检查防火墙是否放行 9000 端口

### AI 分析失败

1. 检查 API 密钥配置：
```bash
cat backend/.env | grep API_KEY
```

2. 查看后端日志：
```bash
docker compose logs backend | tail -50
```

## 目录结构

```
SmartAlbum/
├── backend/          # 后端代码
│   ├── Dockerfile    # 后端镜像构建
│   └── .env          # 后端环境配置
├── frontend/         # 前端代码
│   └── Dockerfile    # 前端镜像构建
├── data/             # 数据库文件（持久化）
├── storage/          # 照片文件（持久化）
├── docker-compose.yml
└── deploy/           # 部署脚本
    ├── install-docker.sh
    ├── deploy.sh
    └── README.md
```

## 安全建议

1. **修改默认端口**（如需）：编辑 `docker-compose.yml`
2. **定期备份数据**：数据库和 storage 目录
3. **配置防火墙**：只开放必要端口
4. **使用强密码**：如有需要配置登录认证

## 技术支持

遇到问题请查看：
- 后端日志：`docker compose logs backend`
- 前端日志：`docker compose logs frontend`
- API 文档：`http://<IP>:9000/docs`
