"""
数据库初始化脚本
"""
import asyncio
import os
from app.database import engine, Base, init_db
from app.models import Photo, AITag, FaceCluster, Album, AlbumPhoto, AIGeneratedImage


async def create_tables():
    """创建所有表"""
    # 确保数据目录存在
    os.makedirs("./data", exist_ok=True)
    os.makedirs("./storage/originals", exist_ok=True)
    os.makedirs("./storage/thumbnails/small", exist_ok=True)
    os.makedirs("./storage/thumbnails/medium", exist_ok=True)
    os.makedirs("./storage/thumbnails/large", exist_ok=True)
    os.makedirs("./storage/ai_generated", exist_ok=True)
    
    # 创建所有表
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    print("[OK] 数据库初始化完成！")
    print("[INFO] 数据库文件: ./data/smartalbum.db")
    print("[INFO] 存储目录已创建")


if __name__ == "__main__":
    asyncio.run(create_tables())
