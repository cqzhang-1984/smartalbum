---
name: SmartAlbum代码修复计划
overview: 根据代码审查报告，系统性修复22个代码质量问题，包括安全漏洞、性能瓶颈、重复代码等，提升项目整体质量从6.5分到8.5分以上。
todos:
  - id: fix-hardcoded-path
    content: 移除硬编码绝对路径 (ai.py:265)
    status: pending
  - id: fix-jwt-secret
    content: 修复硬编码JWT密钥安全漏洞 (config.py:24)
    status: pending
  - id: fix-cors-config
    content: 收紧生产环境CORS配置 (main.py:119)
    status: pending
  - id: fix-default-credentials
    content: 移除默认账号弱密码 (config.py:27-28)
    status: pending
  - id: refactor-vector-service
    content: 重构向量服务使用ChromaDB替代JSON文件
    status: pending
  - id: extract-common-code
    content: 提取公共方法消除重复删除逻辑 (photo_service.py)
    status: pending
  - id: async-image-processing
    content: 异步化图像处理避免阻塞事件循环 (ai_service.py)
    status: pending
  - id: optimize-db-queries
    content: 优化数据库查询消除N+1问题 (search.py)
    status: pending
  - id: add-type-annotations
    content: 完善类型注解覆盖率至90%以上
    status: pending
  - id: unify-exception-handling
    content: 统一异常处理中间件
    status: pending
  - id: remove-debug-code
    content: 清理调试日志代码残留 (ai.py:173)
    status: pending
  - id: config-connection-pool
    content: 配置数据库连接池参数 (database.py)
    status: pending
  - id: add-api-rate-limit
    content: 添加API限流保护 (slowapi)
    status: pending
  - id: enhance-file-validation
    content: 增强文件上传验证 (内容类型检查)
    status: pending
  - id: unify-logging
    content: 统一日志系统使用structlog
    status: pending
  - id: add-unit-tests
    content: 添加核心业务单元测试 (pytest)
    status: pending
  - id: frontend-types
    content: 完善前端TypeScript类型定义
    status: pending
---

## 项目概述

SmartAlbum 智能相册管理系统代码修复任务计划，基于前期代码审查报告发现的22个问题，按优先级制定可执行的修复方案。

## 核心修复目标

1. **安全性修复**: 消除硬编码密钥、弱密码、CORS配置等安全隐患
2. **性能优化**: 解决向量搜索O(n)复杂度、同步阻塞、数据库查询优化
3. **代码质量**: 消除重复代码、完善类型注解、统一异常处理
4. **架构改进**: 统一向量存储实现、优化服务层设计

## 问题优先级划分

### P0 - 紧急 (必须立即修复，影响安全或基础功能)

- 硬编码绝对路径导致部署失败
- 硬编码JWT密钥严重安全漏洞
- CORS生产环境配置过于宽松
- 默认账号密码弱

### P1 - 高优先级 (影响性能和可维护性)

- 向量搜索全表扫描性能瓶颈
- 重复代码严重
- 同步操作阻塞事件循环
- N+1查询问题
- 向量存储实现不一致

### P2 - 中优先级 (改进代码质量)

- 类型注解不完整
- 异常处理不一致
- 调试代码残留
- 缺少数据库连接池配置
- 文件上传验证不足
- 缺少API限流

### P3 - 低优先级 (长期改进)

- 配置管理混乱
- 日志记录不一致
- 缺少单元测试
- 前端类型定义不完整
- 循环导入风险

## 技术栈

- **后端**: FastAPI 0.109.0, SQLAlchemy 2.0.25, aiosqlite, Celery 5.3.6
- **前端**: Vue 3.5.12, TypeScript 5.6, Tailwind CSS 3.4
- **AI/向量**: ChromaDB 0.4.22, OpenAI/豆包 API
- **基础设施**: Redis, 腾讯云COS

## 实施策略

### 阶段一: 安全加固 (P0)

- 移除所有硬编码配置
- 强化安全默认值
- 修复CORS配置

### 阶段二: 性能优化 (P1)

- 重构向量服务使用ChromaDB
- 异步化图像处理
- 优化数据库查询模式

### 阶段三: 代码重构 (P2)

- 提取公共逻辑消除重复
- 统一类型注解
- 标准化异常处理

### 阶段四: 质量提升 (P3)

- 统一日志系统
- 添加测试覆盖
- 前端类型完善

## 关键技术决策

1. **向量数据库**: 统一使用ChromaDB，利用HNSW索引实现O(log n)搜索
2. **异步处理**: 图像处理使用ThreadPoolExecutor避免阻塞
3. **配置管理**: 强制环境变量，Pydantic验证，无默认值
4. **依赖注入**: 使用FastAPI Depends替代全局单例