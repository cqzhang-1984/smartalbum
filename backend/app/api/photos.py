from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, Body
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import List, Optional, Dict, Any
from pydantic import BaseModel
import os
from app.database import get_db
from app.models.photo import Photo
from app.schemas.photo import PhotoResponse, PhotoListResponse, PhotoUpdate
from app.services.photo_service import PhotoService
from app.services.thumbnail_service import ThumbnailService
from app.services.cos_service import cos_service
from app.config import settings

router = APIRouter()


class BatchDeleteRequest(BaseModel):
    """批量删除请求"""
    photo_ids: List[str]


def get_photo_urls(photo: Photo) -> Dict[str, Any]:
    """
    获取照片的完整URL（支持COS和本地存储）
    
    Args:
        photo: 照片模型实例
        
    Returns:
        包含完整URL的字典
    """
    base_data = {
        'id': photo.id,
        'filename': photo.filename,
        'file_size': photo.file_size,
        'shot_time': photo.shot_time,
        'camera_model': photo.camera_model,
        'lens_model': photo.lens_model,
        'focal_length': photo.focal_length,
        'aperture': photo.aperture,
        'shutter_speed': photo.shutter_speed,
        'iso': photo.iso,
        'original_path': photo.original_path,
        'thumbnail_small': photo.thumbnail_small,
        'thumbnail_medium': photo.thumbnail_medium,
        'thumbnail_large': photo.thumbnail_large,
        'ai_tags': photo.ai_tags,
        'rating': photo.rating,
        'is_favorite': photo.is_favorite,
        'face_cluster_id': photo.face_cluster_id,
        'created_at': photo.created_at,
        'updated_at': photo.updated_at,
    }
    
    # 生成完整URL
    if cos_service.is_enabled():
        # 使用COS URL
        base_data['original_url'] = cos_service.get_url(photo.original_path) if photo.original_path else None
        base_data['thumbnail_small_url'] = cos_service.get_url(photo.thumbnail_small) if photo.thumbnail_small else None
        base_data['thumbnail_medium_url'] = cos_service.get_url(photo.thumbnail_medium) if photo.thumbnail_medium else None
        base_data['thumbnail_large_url'] = cos_service.get_url(photo.thumbnail_large) if photo.thumbnail_large else None
    else:
        # 使用本地存储URL
        base_url = f"/storage"
        base_data['original_url'] = f"{base_url}/{photo.original_path}" if photo.original_path else None
        base_data['thumbnail_small_url'] = f"{base_url}/{photo.thumbnail_small}" if photo.thumbnail_small else None
        base_data['thumbnail_medium_url'] = f"{base_url}/{photo.thumbnail_medium}" if photo.thumbnail_medium else None
        base_data['thumbnail_large_url'] = f"{base_url}/{photo.thumbnail_large}" if photo.thumbnail_large else None
    
    return base_data


@router.post("/regenerate-thumbnails")
async def regenerate_thumbnails(db: AsyncSession = Depends(get_db)):
    """重新生成所有照片的缩略图"""
    result = await db.execute(select(Photo))
    photos = result.scalars().all()
    
    regenerated = 0
    failed = 0
    
    for photo in photos:
        try:
            # 修复原始图片路径 - 添加 originals/ 前缀
            if not photo.original_path.startswith('originals/'):
                photo.original_path = f"originals/{photo.original_path}"
            
            # 构建原始图片的绝对路径
            original_absolute = os.path.join(settings.STORAGE_PATH, photo.original_path)
            
            # 检查文件是否存在（本地或COS）
            local_file_exists = os.path.exists(original_absolute)
            
            if not local_file_exists and not cos_service.is_enabled():
                print(f"文件不存在: {original_absolute}")
                failed += 1
                continue
            
            # 生成缩略图
            if cos_service.is_enabled() and not local_file_exists:
                # 从COS下载到临时文件
                import tempfile
                import shutil
                
                temp_thumb_dir = tempfile.mkdtemp(prefix='thumbnails_')
                with tempfile.NamedTemporaryFile(delete=False, suffix='.jpg') as tmp:
                    temp_local_path = tmp.name
                
                # 移除 storage/ 前缀获取COS key
                cos_key = photo.original_path
                if cos_key.startswith('storage/'):
                    cos_key = cos_key[8:]
                
                success, error = cos_service.download_file(cos_key, temp_local_path)
                if not success:
                    print(f"COS下载失败: {error}")
                    os.remove(temp_local_path)
                    shutil.rmtree(temp_thumb_dir, ignore_errors=True)
                    failed += 1
                    continue
                
                # 生成缩略图
                thumbnail_paths = ThumbnailService.generate_thumbnails(
                    temp_local_path,
                    temp_thumb_dir,
                    photo.file_hash
                )
                
                # 上传缩略图到COS
                if thumbnail_paths:
                    for size_name, thumb_path in thumbnail_paths.items():
                        if thumb_path:
                            subdir = os.path.dirname(thumb_path).split('/')[-1] if '/' in thumb_path else ''
                            local_thumb = os.path.join(temp_thumb_dir, subdir, os.path.basename(thumb_path))
                            if os.path.exists(local_thumb):
                                cos_service.upload_file(local_thumb, thumb_path)
                    
                    photo.thumbnail_small = thumbnail_paths.get('small')
                    photo.thumbnail_medium = thumbnail_paths.get('medium')
                    photo.thumbnail_large = thumbnail_paths.get('large')
                    regenerated += 1
                else:
                    failed += 1
                
                # 清理临时文件
                os.remove(temp_local_path)
                shutil.rmtree(temp_thumb_dir, ignore_errors=True)
            else:
                # 本地文件存在，直接生成缩略图
                thumbnail_paths = ThumbnailService.generate_thumbnails(
                    original_absolute,
                    settings.THUMBNAILS_PATH,
                    photo.file_hash
                )
                
                if thumbnail_paths:
                    # 如果使用COS，上传缩略图
                    if cos_service.is_enabled():
                        for size_name, thumb_path in thumbnail_paths.items():
                            if thumb_path:
                                local_thumb = os.path.join(settings.STORAGE_PATH, thumb_path)
                                if os.path.exists(local_thumb):
                                    cos_service.upload_file(local_thumb, thumb_path)
                    
                    photo.thumbnail_small = thumbnail_paths.get('small')
                    photo.thumbnail_medium = thumbnail_paths.get('medium')
                    photo.thumbnail_large = thumbnail_paths.get('large')
                    regenerated += 1
                else:
                    failed += 1
                
        except Exception as e:
            print(f"重新生成缩略图失败 {photo.filename}: {e}")
            import traceback
            traceback.print_exc()
            failed += 1
    
    await db.commit()
    
    return {
        "message": "缩略图重新生成完成",
        "total": len(photos),
        "regenerated": regenerated,
        "failed": failed
    }


@router.get("/cameras/list")
async def get_camera_list(db: AsyncSession = Depends(get_db)):
    """获取相机列表"""
    result = await db.execute(
        select(Photo.camera_model, func.count(Photo.id).label('count'))
        .where(Photo.camera_model.isnot(None))
        .group_by(Photo.camera_model)
        .order_by(func.count(Photo.id).desc())
    )
    
    cameras = [{"model": row[0], "count": row[1]} for row in result.all()]
    return cameras


@router.get("/")
async def get_photos(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    camera: Optional[str] = Query(None),
    min_rating: Optional[int] = Query(None, ge=0, le=5),
    is_favorite: Optional[bool] = Query(None),
    year: Optional[int] = Query(None, ge=1900, le=2100),
    month: Optional[int] = Query(None, ge=1, le=12),
    shot_start_date: Optional[str] = Query(None, description="Format: YYYY-MM-DD"),
    shot_end_date: Optional[str] = Query(None, description="Format: YYYY-MM-DD"),
    db: AsyncSession = Depends(get_db)
):
    """获取照片列表"""
    photos, total = await PhotoService.get_photos(
        db,
        page=page,
        page_size=page_size,
        camera=camera,
        min_rating=min_rating,
        is_favorite=is_favorite,
        year=year,
        month=month,
        shot_start_date=shot_start_date,
        shot_end_date=shot_end_date
    )
    
    return {
        "photos": [get_photo_urls(photo) for photo in photos],
        "total": total,
        "page": page,
        "page_size": page_size
    }


@router.get("/{photo_id}")
async def get_photo(
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """获取单张照片详情"""
    photo = await PhotoService.get_photo_by_id(db, photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    
    return get_photo_urls(photo)


@router.delete("/{photo_id}")
async def delete_photo(
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """删除照片"""
    success = await PhotoService.delete_photo(db, photo_id)
    if not success:
        raise HTTPException(status_code=404, detail="Photo not found")
    
    return {"message": "Photo deleted successfully"}


@router.post("/batch-delete")
async def batch_delete_photos(
    request: BatchDeleteRequest,
    db: AsyncSession = Depends(get_db)
):
    """批量删除照片"""
    if not request.photo_ids:
        raise HTTPException(status_code=400, detail="No photo IDs provided")
    
    success_ids, failed_ids = await PhotoService.delete_photos_batch(db, request.photo_ids)
    
    return {
        "message": f"成功删除 {len(success_ids)} 张照片",
        "deleted_count": len(success_ids),
        "success_ids": success_ids,
        "failed_ids": failed_ids
    }


@router.patch("/{photo_id}/rating")
async def update_photo_rating(
    photo_id: str,
    rating: int = Query(..., ge=1, le=5),
    db: AsyncSession = Depends(get_db)
):
    """更新照片评分"""
    photo = await PhotoService.update_rating(db, photo_id, rating)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    
    return {"message": "Rating updated", "rating": rating}


@router.patch("/{photo_id}/favorite")
async def toggle_favorite(
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """切换收藏状态"""
    photo = await PhotoService.toggle_favorite(db, photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    
    return {
        "message": "Favorite toggled",
        "is_favorite": photo.is_favorite
    }
