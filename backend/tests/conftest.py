"""
测试配置和共享夹具
"""
import pytest
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database import Base
from app.config import settings

# 测试数据库URL（使用内存数据库）
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"


@pytest.fixture(scope="session")
def event_loop():
    """创建事件循环"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
async def test_engine():
    """创建测试数据库引擎"""
    engine = create_async_engine(
        TEST_DATABASE_URL,
        echo=False,
        future=True
    )
    
    # 创建所有表
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    yield engine
    
    # 清理
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest.fixture
async def test_db(test_engine):
    """创建测试数据库会话"""
    async_session = sessionmaker(
        test_engine,
        class_=AsyncSession,
        expire_on_commit=False
    )
    
    async with async_session() as session:
        yield session
        await session.rollback()


@pytest.fixture
def sample_photo_data():
    """示例照片数据"""
    return {
        "filename": "test_photo.jpg",
        "file_hash": "abc123def456",
        "file_size": 1024000,
        "original_path": "originals/abc123def456.jpg",
        "thumbnail_small": "thumbnails/small/abc123def456.jpg",
        "thumbnail_medium": "thumbnails/medium/abc123def456.jpg",
        "thumbnail_large": "thumbnails/large/abc123def456.jpg",
    }
