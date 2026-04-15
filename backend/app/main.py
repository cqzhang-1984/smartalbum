from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from app.config import settings
from app.database import init_db
from app.services.logger_service import logger_service
import os
import asyncio
import time
from typing import Dict, Tuple

# 创建FastAPI应用
app = FastAPI(
    title="SmartAlbum API",
    description="本地私房人像相册智能管理系统API",
    version="1.0.0"
)

# API 限流配置
RATE_LIMIT_REQUESTS = 100  # 每窗口最大请求数
RATE_LIMIT_WINDOW = 60     # 窗口时间（秒）
rate_limit_storage: Dict[str, Tuple[int, float]] = {}  # {client_ip: (count, window_start)}

@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    """
    API 限流中间件 - 基于 IP 的滑动窗口限流
    """
    # 跳过静态文件和文档路径
    path = request.url.path
    if path.startswith("/storage/") or path in ["/docs", "/openapi.json", "/redoc"]:
        return await call_next(request)
    
    # 获取客户端 IP
    client_ip = request.headers.get("X-Forwarded-For", request.client.host)
    if client_ip and "," in client_ip:
        client_ip = client_ip.split(",")[0].strip()
    
    current_time = time.time()
    
    # 检查当前窗口
    if client_ip in rate_limit_storage:
        count, window_start = rate_limit_storage[client_ip]
        
        # 检查窗口是否过期
        if current_time - window_start > RATE_LIMIT_WINDOW:
            # 新窗口
            rate_limit_storage[client_ip] = (1, current_time)
        elif count >= RATE_LIMIT_REQUESTS:
            # 超过限流阈值
            logger_service.warning(f"Rate limit exceeded for IP: {client_ip}")
            return JSONResponse(
                status_code=429,
                content={
                    "error": "Too Many Requests",
                    "message": f"API 限流：每 {RATE_LIMIT_WINDOW} 秒最多 {RATE_LIMIT_REQUESTS} 次请求",
                    "retry_after": int(RATE_LIMIT_WINDOW - (current_time - window_start))
                }
            )
        else:
            # 增加计数
            rate_limit_storage[client_ip] = (count + 1, window_start)
    else:
        # 新客户端
        rate_limit_storage[client_ip] = (1, current_time)
    
    return await call_next(request)


async def _init_default_user():
    """初始化默认用户"""
    try:
        from app.database import AsyncSessionLocal
        from app.services.auth_service import AuthService
        
        async with AsyncSessionLocal() as db:
            await AuthService.init_default_user(db)
            logger_service.info("[SmartAlbum] 默认用户初始化完成")
    except Exception as e:
        logger_service.error(f"初始化默认用户失败: {e}")


async def _auto_start_pending_analysis():
    """自动启动待分析照片的AI处理"""
    try:
        # 等待服务完全启动
        await asyncio.sleep(5)
        
        print("[SmartAlbum] 自动启动AI分析检查...")
        
        from app.database import AsyncSessionLocal
        from app.models.photo import Photo
        from sqlalchemy import select
        
        async with AsyncSessionLocal() as db:
            # 查询待分析照片数量
            result = await db.execute(
                select(Photo).where(Photo.ai_tags.is_(None)).limit(100)
            )
            pending_photos = result.scalars().all()
            
            if not pending_photos:
                print("[SmartAlbum] 没有待分析的照片")
                return
            
            print(f"[SmartAlbum] 发现 {len(pending_photos)} 张待分析照片，开始自动处理...")
            logger_service.info(f"发现 {len(pending_photos)} 张待分析照片，开始自动处理...")
            
            # 导入处理函数
            from app.api.ai import _process_ai_analysis_async
            from app.services.cos_service import cos_service
            
            use_cos = cos_service.is_enabled()
            
            for photo in pending_photos:
                try:
                    # 确定图片路径
                    if use_cos:
                        ai_image_path = f"cos://{photo.original_path}"
                    else:
                        ai_image_path = os.path.join(settings.STORAGE_PATH, photo.original_path.replace("/storage/", ""))
                        if not os.path.exists(ai_image_path):
                            logger_service.warning(f"照片文件不存在: {ai_image_path}")
                            continue
                    
                    # 异步处理
                    asyncio.create_task(_process_ai_analysis_async(photo.id, ai_image_path))
                    
                    # 每张照片间隔1秒，避免API限流
                    await asyncio.sleep(1)
                    
                except Exception as e:
                    logger_service.error(f"启动分析任务失败 {photo.id}: {e}")
                    
    except Exception as e:
        logger_service.error(f"自动启动AI分析失败: {e}")


@app.on_event("startup")
async def startup_event():
    """应用启动时初始化数据库"""
    # 打印环境信息
    env_info = f"""
╔══════════════════════════════════════════════════════════╗
║  SmartAlbum 启动                                          ║
╠══════════════════════════════════════════════════════════╣
║  环境: {settings.ENVIRONMENT:<15} {'[生产]' if settings.IS_PRODUCTION else '[开发]':<10}          ║
║  Redis: {settings.REDIS_URL:<45}  ║
║  COS: {'启用' if settings.COS_ENABLED else '禁用':<15} 前缀: {settings.COS_PREFIX:<20}    ║
╚══════════════════════════════════════════════════════════╝
"""
    print(env_info)
    logger_service.info(f"SmartAlbum 启动 - 环境: {settings.ENVIRONMENT}, Redis: {settings.REDIS_URL}, COS前缀: {settings.COS_PREFIX}")
    
    await init_db()
    
    # 初始化默认用户
    await _init_default_user()
    
    # 自动启动待分析照片的AI处理
    asyncio.create_task(_auto_start_pending_analysis())

# CORS配置 - 支持开发环境和生产环境
import os

# 从环境变量读取允许的源，默认为开发环境
cors_origins_str = os.getenv("CORS_ORIGINS", "http://localhost:8888,http://localhost:3000")
allow_origins = [origin.strip() for origin in cors_origins_str.split(",") if origin.strip()]

# 生产环境安全检查：禁止允许所有来源
if settings.IS_PRODUCTION and "*" in allow_origins:
    import warnings
    warnings.warn(
        "生产环境 CORS 不允许配置为 '*' (所有来源)。"
        "请设置 CORS_ORIGINS 环境变量指定允许的来源。"
        "例如: CORS_ORIGINS=https://yourdomain.com,https://app.yourdomain.com"
    )
    # 移除 *，使用默认的localhost作为后备（仅用于启动，实际应配置正确）
    allow_origins = ["http://localhost:8888"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 创建必要的存储目录
os.makedirs(settings.STORAGE_PATH, exist_ok=True)
os.makedirs(settings.ORIGINALS_PATH, exist_ok=True)
os.makedirs(settings.THUMBNAILS_PATH, exist_ok=True)
os.makedirs(settings.THUMBNAIL_SMALL_PATH, exist_ok=True)
os.makedirs(settings.THUMBNAIL_MEDIUM_PATH, exist_ok=True)
os.makedirs(settings.THUMBNAIL_LARGE_PATH, exist_ok=True)
os.makedirs(settings.AI_GENERATED_PATH, exist_ok=True)

# 挂载静态文件目录
app.mount("/storage", StaticFiles(directory=settings.STORAGE_PATH), name="storage")


@app.get("/")
async def root():
    """根路径接口"""
    return {"message": "SmartAlbum API is running", "version": "1.0.0"}


@app.get("/health")
async def health_check():
    """健康检查"""
    return {"status": "healthy"}


@app.get("/api/health")
async def api_health_check():
    """API 健康检查端点"""
    return {"status": "healthy", "service": "smartalbum-backend"}


# 导入并注册路由
from app.api import photos, albums, search, upload, ai, logs, auth

app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(photos.router, prefix="/api/photos", tags=["photos"])
app.include_router(albums.router, prefix="/api/albums", tags=["albums"])
app.include_router(search.router, prefix="/api/search", tags=["search"])
app.include_router(upload.router, prefix="/api/upload", tags=["upload"])
app.include_router(ai.router, prefix="/api/ai", tags=["ai"])
app.include_router(logs.router, prefix="/api/logs", tags=["logs"])


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=9999,
        reload=True
    )
