from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, declarative_base
from app.config import settings

# 检测是否为 SQLite（SQLite 不支持连接池参数）
is_sqlite = settings.DATABASE_URL.startswith('sqlite')

# 创建异步数据库引擎 - 配置连接池
engine_kwargs = {
    'echo': settings.DEBUG,
    'future': True,
}

# 只有非 SQLite 数据库才使用连接池配置
if not is_sqlite:
    engine_kwargs.update({
        'pool_size': 10,                    # 连接池大小
        'max_overflow': 20,                 # 最大溢出连接数
        'pool_timeout': 30,                 # 获取连接超时时间（秒）
        'pool_recycle': 3600,               # 连接回收时间（秒）
        'pool_pre_ping': True,              # 连接前ping检测，避免使用失效连接
    })

engine = create_async_engine(settings.DATABASE_URL, **engine_kwargs)

# 创建异步会话工厂
AsyncSessionLocal = sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False
)

# 创建基类
Base = declarative_base()


async def get_db():
    """获取数据库会话"""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db():
    """初始化数据库"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
