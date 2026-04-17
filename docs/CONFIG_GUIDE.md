# SmartAlbum 配置指南

本文档详细介绍 SmartAlbum 的配置体系，包括环境变量、配置验证和最佳实践。

## 目录

- [配置架构](#配置架构)
- [快速开始](#快速开始)
- [后端配置](#后端配置)
- [前端配置](#前端配置)
- [环境管理](#环境管理)
- [配置验证](#配置验证)
- [安全配置](#安全配置)
- [故障排除](#故障排除)

---

## 配置架构

SmartAlbum 采用分层配置架构：

```
配置优先级（从高到低）：
1. 环境变量 (os.environ)
2. .env 文件 (项目根目录)
3. 默认值 (代码中定义)
```

### 配置文件结构

```
SmartAlbum/
├── backend/
│   ├── .env.example          # 后端配置示例
│   ├── .env                  # 后端实际配置（不提交Git）
│   └── app/
│       ├── config.py         # 后端配置类
│       └── core/
│           └── config_validator.py  # 配置验证器
├── frontend/
│   ├── .env.example          # 前端配置示例
│   ├── .env.development      # 前端开发配置
│   ├── .env.production       # 前端生产配置
│   └── src/
│       └── config/
│           └── index.ts      # 前端配置模块
└── docs/
    └── CONFIG_GUIDE.md       # 本指南
```

---

## 快速开始

### 1. 后端配置

```bash
# 进入后端目录
cd backend

# 复制示例配置
cp .env.example .env

# 编辑 .env 文件，填写必要的配置
nano .env
```

**最小必需配置：**

```env
# 基础配置
ENVIRONMENT=development
SECRET_KEY=$(python -c "import secrets; print(secrets.token_hex(32))")

# AI配置（如需使用AI功能）
AI_API_KEY=your-ai-api-key
AI_API_BASE=https://api.openai.com/v1

# 管理员密码
DEFAULT_PASSWORD=your-secure-password
```

### 2. 前端配置

```bash
# 进入前端目录
cd frontend

# 开发环境使用默认配置即可
# 如需修改，复制示例文件
cp .env.example .env.local
```

---

## 后端配置

### 基础配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `ENVIRONMENT` | string | development | 运行环境：development/staging/production |
| `DEBUG` | bool | false | 调试模式（生产环境必须false） |
| `SECRET_KEY` | string | - | JWT密钥（生产环境必须32位以上） |
| `APP_NAME` | string | SmartAlbum | 应用名称 |
| `APP_VERSION` | string | 1.0.0 | 应用版本 |

### 数据库配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `DATABASE_URL` | string | sqlite+aiosqlite:///./data/smartalbum.db | 数据库连接URL |
| `DATABASE_POOL_SIZE` | int | 5 | 连接池大小 |
| `DATABASE_MAX_OVERFLOW` | int | 10 | 连接池溢出限制 |

**支持的数据库：**
- SQLite: `sqlite+aiosqlite:///./data/smartalbum.db`
- PostgreSQL: `postgresql+asyncpg://user:password@localhost:5432/smartalbum`

### AI 配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `AI_MODEL_NAME` | string | GPT-4o | 模型显示名称 |
| `AI_MODEL_ID` | string | gpt-4o | 模型ID（API调用） |
| `AI_API_KEY` | string | - | API密钥 |
| `AI_API_BASE` | string | https://api.openai.com/v1 | API基础URL |
| `AI_TIMEOUT` | int | 120 | 请求超时（秒） |
| `AI_MAX_RETRIES` | int | 3 | 最大重试次数 |

**兼容的配置（向后兼容）：**
- `OPENAI_API_KEY` - OpenAI 专用
- `DOUBAO_API_KEY` - 豆包专用

**优先级：** `AI_API_KEY` > `OPENAI_API_KEY` > `DOUBAO_API_KEY`

### 存储配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `STORAGE_PATH` | path | ./storage | 存储根目录 |
| `ORIGINALS_PATH` | path | ./storage/originals | 原始图片目录 |
| `THUMBNAILS_PATH` | path | ./storage/thumbnails | 缩略图目录 |
| `AI_GENERATED_PATH` | path | ./storage/ai_generated | AI生成图片目录 |

### 人脸识别配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `FACE_ENABLED` | bool | true | 启用人脸识别 |
| `FACE_MATCH_THRESHOLD` | float | 0.6 | 匹配阈值（0.1-1.0） |
| `FACE_DETECTION_MODEL` | string | hog | 检测模型：hog/cnn |

### 腾讯云COS配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `COS_ENABLED` | bool | false | 启用COS存储 |
| `COS_SECRET_ID` | string | - | SecretId |
| `COS_SECRET_KEY` | string | - | SecretKey |
| `COS_BUCKET` | string | - | 存储桶名称 |
| `COS_REGION` | string | ap-beijing | 区域 |

---

## 前端配置

### 基础配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `VITE_API_BASE_URL` | string | http://localhost:9999 | API基础地址 |
| `VITE_APP_TITLE` | string | SmartAlbum | 应用标题 |
| `VITE_APP_VERSION` | string | 1.0.0 | 版本号 |
| `VITE_APP_ENV` | string | development | 环境标识 |

### 功能开关

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `VITE_ENABLE_AI` | bool | true | 启用AI功能 |
| `VITE_ENABLE_FACE_RECOGNITION` | bool | true | 启用人脸识别 |
| `VITE_ENABLE_SEMANTIC_SEARCH` | bool | true | 启用语义搜索 |
| `VITE_ENABLE_IMAGE_GENERATION` | bool | true | 启用图片生成 |
| `VITE_ENABLE_DEBUG` | bool | false | 启用调试工具 |

### 性能配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `VITE_LAZY_LOAD_THRESHOLD` | number | 300 | 懒加载阈值（像素） |
| `VITE_THUMBNAIL_QUALITY` | number | 85 | 缩略图质量（1-100） |
| `VITE_PAGE_SIZE` | number | 20 | 分页大小 |
| `VITE_UPLOAD_CONCURRENCY` | number | 3 | 上传并发数 |

### 安全配置

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `VITE_REQUEST_TIMEOUT` | number | 30000 | 请求超时（毫秒） |
| `VITE_MAX_UPLOAD_SIZE` | number | 50 | 最大上传大小（MB） |
| `VITE_ALLOWED_FILE_TYPES` | string | jpg,jpeg,png,gif,webp | 允许的文件类型 |

---

## 环境管理

### 开发环境

```env
# backend/.env
ENVIRONMENT=development
DEBUG=true
SECRET_KEY=dev-secret-key
LOG_LEVEL=DEBUG

# frontend/.env.development
VITE_API_BASE_URL=http://localhost:9999
VITE_ENABLE_DEBUG=true
```

### 生产环境

```env
# backend/.env
ENVIRONMENT=production
DEBUG=false
SECRET_KEY=<strong-random-key>
LOG_LEVEL=INFO
LOG_FILE_ENABLED=true

# frontend/.env.production
VITE_API_BASE_URL=/
VITE_ENABLE_DEBUG=false
```

### 环境切换脚本

```bash
# 切换到生产环境配置
./scripts/switch-env.sh production

# 切换到开发环境配置
./scripts/switch-env.sh development
```

---

## 配置验证

### 后端验证

配置在应用启动时自动验证：

```python
from app.config import settings

# 手动触发安全验证
settings.validate_security()

# 获取AI配置状态报告
report = settings.validate_ai_config()
print(report)
# {
#     "ai_available": True,
#     "embedding_available": True,
#     "image_gen_available": False,
#     "models": [...],
#     "warnings": [...]
# }

# 获取配置摘要
summary = settings.get_config_summary()
```

### 前端验证

配置在模块加载时自动验证：

```typescript
import config, { isFeatureEnabled, getApiUrl } from '@/config';

// 检查功能是否启用
if (isFeatureEnabled('enableAI')) {
    // 使用AI功能
}

// 获取API URL
const apiUrl = getApiUrl('/photos');
```

### 验证规则

**后端验证：**
- 生产环境必须设置 `SECRET_KEY`（≥32位）
- 路径配置必须可写
- URL格式必须合法
- 数值必须在有效范围内

**前端验证：**
- 必填配置项不能为空
- URL格式必须合法
- 数值必须在范围内
- 开发环境警告，生产环境报错

---

## 安全配置

### 生产环境检查清单

- [ ] `ENVIRONMENT=production`
- [ ] `DEBUG=false`
- [ ] `SECRET_KEY` 已设置（≥32位随机字符串）
- [ ] `DEFAULT_PASSWORD` 已设置强密码
- [ ] `CORS_ORIGINS` 未设置为 `*`
- [ ] `.env` 文件已添加到 `.gitignore`
- [ ] API密钥未硬编码在代码中
- [ ] 日志中不包含敏感信息

### 生成安全密钥

```bash
# Python
python -c "import secrets; print(secrets.token_hex(32))"

# OpenSSL
openssl rand -hex 32

# Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

### 敏感信息保护

**不要提交到Git：**
```gitignore
# .gitignore
.env
.env.local
.env.*.local
*.pem
*.key
```

**日志脱敏：**
```python
# 配置自动脱敏敏感信息
 Sensitive keys are automatically masked in logs
```

---

## 故障排除

### 常见问题

**1. 配置不生效**

```bash
# 检查环境变量是否设置
echo $ENVIRONMENT

# 检查 .env 文件位置
ls -la backend/.env

# 重启应用
```

**2. 数据库连接失败**

```bash
# 检查数据库目录权限
ls -la backend/data/

# 手动创建目录
mkdir -p backend/data
chmod 755 backend/data
```

**3. AI功能不可用**

```bash
# 检查API密钥
curl -H "Authorization: Bearer $AI_API_KEY" $AI_API_BASE/models

# 查看配置报告
python -c "from app.config import settings; print(settings.validate_ai_config())"
```

**4. 前端API请求失败**

```bash
# 检查API基础地址
# 浏览器控制台查看网络请求
# 确认 VITE_API_BASE_URL 配置
```

### 调试配置

```python
# 查看当前配置
from app.config import settings
import json

print(json.dumps(settings.get_config_summary(), indent=2))
```

```typescript
// 前端查看配置
import config from '@/config';
console.log('Current config:', config);
```

---

## 最佳实践

1. **环境分离**: 开发、测试、生产使用不同的配置文件
2. **敏感信息**: 所有密钥和密码通过环境变量注入
3. **版本控制**: 只提交 `.env.example`，不提交实际 `.env`
4. **文档同步**: 修改配置后更新本文档
5. **验证优先**: 新配置必须通过验证才能使用
6. **监控告警**: 生产环境配置变更需要审计日志

---

## 参考

- [Pydantic Settings](https://docs.pydantic.dev/latest/concepts/pydantic_settings/)
- [Vite Env Variables](https://vitejs.dev/guide/env-and-mode.html)
- [Twelve-Factor App Config](https://12factor.net/config)
