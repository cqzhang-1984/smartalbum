from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional
from app.database import get_db
from app.models.photo import Photo
from app.services.vector_service import vector_service
from app.api.photos import get_photo_urls

router = APIRouter()


@router.get("/")
async def search_photos(
    q: str = Query(..., min_length=1, description="搜索查询文本"),
    limit: int = Query(20, ge=1, le=100, description="返回结果数量"),
    db: AsyncSession = Depends(get_db)
):
    """
    自然语言搜索照片
    
    使用向量相似度搜索，支持自然语言查询，如：
    - "穿着白色吊带裙坐在地毯上的黑发女孩"
    - "眼神忧郁的胶片感特写"
    - "窗边逆光的慵懒姿态"
    """
    # 使用向量服务搜索相似照片
    similar_photos = await vector_service.search_similar_photos(q, limit)
    
    # 获取照片详细信息
    photo_ids = [p['photo_id'] for p in similar_photos]
    
    if not photo_ids:
        return {
            "query": q,
            "results": [],
            "total": 0
        }
    
    # 查询数据库获取完整照片信息
    result = await db.execute(
        select(Photo).where(Photo.id.in_(photo_ids))
    )
    photos = result.scalars().all()
    
    # 创建ID到照片的映射
    photo_map = {photo.id: photo for photo in photos}
    
    # 按相似度排序返回结果（使用 get_photo_urls 获取完整URL）
    results = []
    for item in similar_photos:
        photo = photo_map.get(item['photo_id'])
        if photo:
            photo_data = get_photo_urls(photo)
            photo_data['similarity_score'] = 1 - (item['distance'] or 0)
            results.append(photo_data)
    
    return {
        "query": q,
        "results": results,
        "total": len(results)
    }


@router.get("/filters")
async def get_filter_options(db: AsyncSession = Depends(get_db)):
    """获取筛选选项"""
    from sqlalchemy import func
    
    # 获取相机列表
    camera_result = await db.execute(
        select(Photo.camera_model, func.count(Photo.id).label('count'))
        .where(Photo.camera_model.isnot(None))
        .group_by(Photo.camera_model)
        .order_by(func.count(Photo.id).desc())
        .limit(10)
    )
    cameras = [{"model": row[0], "count": row[1]} for row in camera_result.all()]
    
    # 获取AI标签统计（从已识别的照片中提取）
    # 注意：这需要查询所有照片的ai_tags字段并聚合，性能可能较差
    # 在生产环境中应该考虑使用单独的标签表
    
    return {
        "cameras": cameras,
        "emotions": ["慵懒", "清冷", "热烈", "忧郁", "恬静", "俏皮", "温柔"],
        "styles": ["JK", "纯欲", "法式复古", "暗黑", "甜美", "性感", "文艺"],
        "lightings": ["逆光", "侧光", "伦勃朗光", "高调", "暗调", "自然光"],
        "environments": ["室内", "户外", "窗边", "海边", "森林", "城市"]
    }


@router.get("/stats")
async def get_search_stats():
    """获取向量数据库统计信息"""
    stats = vector_service.get_collection_stats()
    
    return {
        "vector_database": stats,
        "search_enabled": stats['total_vectors'] > 0
    }
