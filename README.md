# SmartAlbum - 本地私房人像相册智能管理系统

一个基于B/S架构的智能照片管理系统，支持AI识别、自然语言检索和智能相册管理。

## 功能特性

- 📸 **照片管理**：批量上传、多级缩略图、EXIF解析
- 🤖 **AI识别**：多模态大模型识别照片内容，自动生成标签
- 🔍 **语义搜索**：自然语言检索照片
- 📁 **智能相册**：基于规则自动归类照片
- ⭐ **评分系统**：手动评分与AI美学评分
- 🔒 **本地存储**：所有数据本地保存，保护隐私

## 技术栈

### 前端
- Vue 3 + TypeScript
- Tailwind CSS
- PhotoSwipe（图片浏览）
- Pinia（状态管理）
- Vue Router

### 后端
- FastAPI（Python异步框架）
- SQLAlchemy + SQLite
- Celery + Redis（任务队列）
- ChromaDB（向量数据库）
- LangChain（AI集成）

## 快速开始

### 环境要求

- Node.js 18+
- Python 3.10+
- Redis

### 安装依赖

#### 后端
```bash
cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

#### 前端
```bash
cd frontend
npm install
```

### 配置

1. 复制环境变量配置：
```bash
cp backend/.env.example backend/.env
```

2. 编辑 `.env` 文件，配置AI模型API密钥

### 启动服务

#### 启动Redis
```bash
redis-server
```

#### 启动后端
```bash
cd backend
uvicorn app.main:app --reload
```

#### 启动前端
```bash
cd frontend
npm run dev
```

访问 http://localhost:5173 开始使用

### Docker部署（可选）

```bash
docker-compose up -d
```

## 项目结构

```
SmartAlbum/
├── frontend/          # Vue 3前端项目
├── backend/           # FastAPI后端项目
│   ├── app/          # 应用代码
│   │   ├── api/      # API路由
│   │   ├── models/   # 数据库模型
│   │   ├── schemas/  # Pydantic模式
│   │   └── services/ # 业务服务
│   └── tasks/        # Celery任务
├── storage/          # 文件存储
│   ├── originals/    # 原图
│   └── thumbnails/   # 缩略图
└── data/            # 数据库文件
```

## 开发指南

详细的开发文档请参考项目Wiki。

## 许可证

MIT License
