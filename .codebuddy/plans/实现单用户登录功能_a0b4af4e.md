---
name: 实现单用户登录功能
overview: 为SmartAlbum添加简单的单用户登录功能，包括后端JWT认证和前端登录界面
design:
  architecture:
    framework: vue
  styleKeywords:
    - Glassmorphism
    - Modern
    - Minimalist
    - Dark Theme
    - Gradient
  fontSystem:
    fontFamily: PingFang SC
    heading:
      size: 28px
      weight: 600
    subheading:
      size: 16px
      weight: 400
    body:
      size: 14px
      weight: 400
  colorSystem:
    primary:
      - "#3B82F6"
      - "#60A5FA"
    background:
      - "#0F172A"
      - rgba(15, 23, 42, 0.8)
      - rgba(255, 255, 255, 0.1)
    text:
      - "#FFFFFF"
      - "#94A3B8"
      - "#EF4444"
    functional:
      - "#10B981"
      - "#F59E0B"
      - "#EF4444"
todos:
  - id: add-backend-deps
    content: 添加后端依赖：python-jose 和 passlib
    status: completed
  - id: create-user-model
    content: 创建 User 模型和数据库表
    status: completed
    dependencies:
      - add-backend-deps
  - id: create-security-utils
    content: 创建 security.py 工具模块（JWT、密码哈希）
    status: completed
  - id: create-auth-service
    content: 创建 auth_service.py 认证服务
    status: completed
    dependencies:
      - create-security-utils
      - create-user-model
  - id: create-auth-api
    content: 创建 auth.py API 路由（登录、获取用户、改密码）
    status: completed
    dependencies:
      - create-auth-service
  - id: init-default-user
    content: 系统启动时初始化默认 admin 用户
    status: completed
    dependencies:
      - create-user-model
  - id: create-frontend-auth-store
    content: 创建 authStore.ts 用户状态管理
    status: completed
  - id: create-auth-api-frontend
    content: 创建前端 auth.ts API 模块
    status: completed
    dependencies:
      - create-frontend-auth-store
  - id: create-request-utils
    content: 封装 axios 请求拦截器
    status: completed
    dependencies:
      - create-auth-api-frontend
  - id: create-login-view
    content: 创建 LoginView.vue 登录页面
    status: completed
    dependencies:
      - create-auth-api-frontend
  - id: update-router
    content: 更新路由配置，添加登录页和路由守卫
    status: completed
    dependencies:
      - create-login-view
      - create-frontend-auth-store
  - id: add-change-password
    content: 在设置页面添加修改密码功能
    status: completed
    dependencies:
      - create-auth-api-frontend
---

## 需求描述

为 SmartAlbum 项目添加简单的单用户登录系统，仅支持单用户登录。

### 功能需求

1. **单用户系统**：无需注册功能，系统内置默认用户（admin）
2. **用户登录**：支持用户名+密码登录验证
3. **JWT Token 认证**：使用 JWT 进行身份认证和状态保持
4. **登录状态持久化**：前端使用 localStorage 存储 token
5. **路由保护**：未登录用户自动重定向到登录页
6. **修改密码**：支持登录后修改密码

### 视觉需求

- 登录界面简洁美观，符合现代设计规范
- 与现有项目风格保持一致

## 技术栈

### 后端技术

- **FastAPI**：现有后端框架
- **SQLAlchemy**：ORM 框架（复用现有）
- **SQLite**：数据库（复用现有）
- **python-jose**：JWT Token 生成与验证
- **passlib**：密码哈希（bcrypt）
- **python-multipart**：表单解析（已存在）

### 前端技术

- **Vue 3**：现有前端框架
- **TypeScript**：类型安全
- **Pinia**：状态管理（复用现有 store 模式）
- **Vue Router**：路由守卫实现权限控制
- **Tailwind CSS**：样式（复用现有）

## 实现方案

### 后端实现

1. **依赖添加**：`python-jose[cryptography]` 和 `passlib[bcrypt]`
2. **用户模型**：创建 `User` 模型，字段包含 id、username、password_hash
3. **认证服务**：封装密码验证、Token 生成/验证逻辑
4. **登录 API**：POST /api/auth/login，验证成功后返回 JWT
5. **获取用户信息 API**：GET /api/auth/me，验证 Token 返回用户信息
6. **修改密码 API**：POST /api/auth/change-password
7. **初始化默认用户**：系统启动时自动创建 admin 用户（默认密码可配置）
8. **API 保护**：需要登录的路由添加依赖注入验证

### 前端实现

1. **用户状态管理**：创建 `authStore`，管理登录状态、token、用户信息
2. **登录页面**：创建 `LoginView.vue`，包含表单验证、错误提示
3. **路由守卫**：修改 router，添加 `requiresAuth` 元数据，未登录跳转登录页
4. **请求拦截器**：axios 请求自动添加 Authorization Header
5. **响应拦截器**：401 状态码自动跳转登录页
6. **设置页面修改密码**：在现有 Settings 页面添加修改密码功能

### 数据模型

```python
class User(Base):
    __tablename__ = "users"
    
    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime] = mapped_column(default=func.now())
    updated_at: Mapped[datetime] = mapped_column(default=func.now(), onupdate=func.now())
```

### 安全策略

- 密码使用 bcrypt 哈希存储
- JWT Token 设置合理过期时间（24小时）
- 使用 HTTP-only Cookie 或 secure localStorage 存储策略
- 密码修改需要验证旧密码

## 目录结构

```
backend/
├── requirements.txt              # [MODIFY] 添加 python-jose, passlib
├── app/
│   ├── models/
│   │   ├── __init__.py          # [MODIFY] 导出 User 模型
│   │   └── user.py              # [NEW] User 模型定义
│   ├── schemas/
│   │   └── auth.py              # [NEW] 认证相关 Pydantic 模型
│   ├── services/
│   │   └── auth_service.py      # [NEW] 认证服务（密码验证、Token管理）
│   ├── api/
│   │   ├── __init__.py          # [MODIFY] 注册 auth 路由
│   │   └── auth.py              # [NEW] 登录、获取用户信息、修改密码接口
│   ├── core/
│   │   └── security.py          # [NEW] JWT、密码哈希工具函数
│   └── main.py                  # [MODIFY] 初始化默认用户

frontend/
├── src/
│   ├── stores/
│   │   └── authStore.ts         # [NEW] 用户认证状态管理
│   ├── api/
│   │   └── auth.ts              # [NEW] 认证相关 API 请求
│   ├── views/
│   │   └── LoginView.vue        # [NEW] 登录页面
│   ├── router/
│   │   └── index.ts             # [MODIFY] 添加登录路由、路由守卫
│   └── utils/
│       └── request.ts           # [NEW] 封装 axios，添加拦截器
```

## 设计概述

采用现代简约设计风格，登录界面以深色/半透明玻璃效果为主，与 SmartAlbum 相册管理系统的视觉风格保持一致。

## 页面设计

### 登录页面 (LoginView.vue)

**整体布局**

- 全屏背景：使用渐变色或模糊化的相册照片作为背景
- 居中卡片：玻璃态(Glassmorphism)登录卡片，半透明毛玻璃效果

**登录卡片结构**

1. **Logo区域**：顶部显示 SmartAlbum 图标和名称
2. **标题区域**："欢迎回来" / 副标题提示
3. **表单区域**：

- 用户名输入框：带用户图标前缀
- 密码输入框：带锁图标前缀，支持显示/隐藏密码切换
- 登录按钮：渐变背景，加载状态动画

4. **错误提示**：表单验证错误以红色文字显示在输入框下方
5. **页脚信息**：版本号或版权信息

**交互效果**

- 输入框聚焦时：边框高亮，轻微上浮阴影
- 登录按钮：hover 时渐变加深，点击时有缩放反馈
- 加载状态：按钮显示旋转 loading 图标，禁用表单
- 错误动画：验证失败时输入框轻微左右摇晃

### 修改密码弹窗 (Settings 页面内)

**弹窗设计**

- 模态对话框，背景遮罩
- 三个输入框：旧密码、新密码、确认新密码
- 密码强度指示条（可选）
- 确认/取消按钮

## 设计风格

- 玻璃态设计 (Glassmorphism)
- 深色/半透明背景
- 圆角卡片 (16px border-radius)
- 柔和阴影和光晕效果