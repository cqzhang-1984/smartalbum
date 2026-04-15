"""
照片处理服务
"""
import os
from typing import List, Optional, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_
from app.models.photo import Photo
from app.schemas.photo import PhotoCreate, PhotoUpdate
from app.utils.file_utils import calculate_file_hash, get_photo_path, get_thumbnail_paths


class PhotoService:
    """照片服务类"""
    
    @staticmethod
    def _delete_photo_files(photo: Photo) -> None:
        """
        删除照片关联的文件（原图和缩略图）
        支持 COS 和本地存储
        
        Args:
            photo: 照片对象
        """
        from app.services.cos_service import cos_service
        from app.config import settings
        
        if cos_service.is_enabled():
            # 删除 COS 上的文件
            if photo.original_path:
                cos_service.delete_file(photo.original_path)
            if photo.thumbnail_small:
                cos_service.delete_file(photo.thumbnail_small)
            if photo.thumbnail_medium:
                cos_service.delete_file(photo.thumbnail_medium)
            if photo.thumbnail_large:
                cos_service.delete_file(photo.thumbnail_large)
        else:
            # 删除本地文件
            storage_path = settings.STORAGE_PATH
            
            for file_path in [photo.original_path, photo.thumbnail_small, 
                             photo.thumbnail_medium, photo.thumbnail_large]:
                if file_path:
                    local_path = os.path.join(storage_path, file_path)
                    if os.path.exists(local_path):
                        os.remove(local_path)
    
    @staticmethod
    async def create_photo(db: AsyncSession, photo_data: PhotoCreate) -> Photo:
        """创建照片记录"""
        photo = Photo(**photo_data.model_dump())
        db.add(photo)
        await db.commit()
        await db.refresh(photo)
        return photo
    
    @staticmethod
    async def get_photo_by_id(db: AsyncSession, photo_id: str) -> Optional[Photo]:
        """根据ID获取照片"""
        result = await db.execute(
            select(Photo).where(Photo.id == photo_id)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_photo_by_hash(db: AsyncSession, file_hash: str) -> Optional[Photo]:
        """根据文件哈希获取照片"""
        result = await db.execute(
            select(Photo).where(Photo.file_hash == file_hash)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_photos(
        db: AsyncSession,
        page: int = 1,
        page_size: int = 20,
        camera: Optional[str] = None,
        min_rating: Optional[int] = None,
        is_favorite: Optional[bool] = None,
        year: Optional[int] = None,
        month: Optional[int] = None,
        shot_start_date: Optional[str] = None,
        shot_end_date: Optional[str] = None,
        order_by: str = "created_at",
        order_desc: bool = True
    ) -> tuple[List[Photo], int]:
        """
        获取照片列表（带筛选）
        返回: (照片列表, 总数)
        """
        from datetime import datetime
        from sqlalchemy import and_
        
        query = select(Photo)
        count_query = select(func.count(Photo.id))
        
        # 应用筛选条件
        filters = []
        if camera:
            filters.append(Photo.camera_model == camera)
        if min_rating is not None:
            filters.append(Photo.rating >= min_rating)
        if is_favorite is not None:
            filters.append(Photo.is_favorite == is_favorite)
        
        # 时间筛选
        if year is not None:
            filters.append(func.strftime('%Y', Photo.shot_time) == str(year))
        if month is not None:
            filters.append(func.strftime('%m', Photo.shot_time) == str(month).zfill(2))
        if shot_start_date:
            try:
                start_dt = datetime.strptime(shot_start_date, '%Y-%m-%d')
                filters.append(Photo.shot_time >= start_dt)
            except ValueError:
                pass
        if shot_end_date:
            try:
                end_dt = datetime.strptime(shot_end_date, '%Y-%m-%d')
                filters.append(Photo.shot_time <= end_dt)
            except ValueError:
                pass
        
        if filters:
            query = query.where(and_(*filters))
            count_query = count_query.where(and_(*filters))
        
        # 排序
        order_column = getattr(Photo, order_by, Photo.created_at)
        if order_desc:
            query = query.order_by(order_column.desc())
        else:
            query = query.order_by(order_column.asc())
        
        # 分页
        offset = (page - 1) * page_size
        query = query.offset(offset).limit(page_size)
        
        # 执行查询
        result = await db.execute(query)
        photos = result.scalars().all()
        
        # 获取总数
        count_result = await db.execute(count_query)
        total = count_result.scalar()
        
        return photos, total
    
    @staticmethod
    async def update_photo(
        db: AsyncSession,
        photo_id: str,
        update_data: PhotoUpdate
    ) -> Optional[Photo]:
        """更新照片信息"""
        photo = await PhotoService.get_photo_by_id(db, photo_id)
        if not photo:
            return None
        
        for field, value in update_data.model_dump(exclude_unset=True).items():
            setattr(photo, field, value)
        
        await db.commit()
        await db.refresh(photo)
        return photo
    
    @staticmethod
    async def update_rating(db: AsyncSession, photo_id: str, rating: int) -> Optional[Photo]:
        """更新照片评分"""
        photo = await PhotoService.get_photo_by_id(db, photo_id)
        if not photo:
            return None
        
        photo.rating = rating
        await db.commit()
        await db.refresh(photo)
        return photo
    
    @staticmethod
    async def toggle_favorite(db: AsyncSession, photo_id: str) -> Optional[Photo]:
        """切换收藏状态"""
        photo = await PhotoService.get_photo_by_id(db, photo_id)
        if not photo:
            return None
        
        photo.is_favorite = not photo.is_favorite
        await db.commit()
        await db.refresh(photo)
        return photo
    
    @staticmethod
    async def delete_photo(db: AsyncSession, photo_id: str) -> bool:
        """删除照片"""
        photo = await PhotoService.get_photo_by_id(db, photo_id)
        if not photo:
            return False
        
        # 删除关联文件
        PhotoService._delete_photo_files(photo)
        
        # 删除数据库记录
        await db.delete(photo)
        await db.commit()
        return True

    @staticmethod
    async def delete_photos_batch(db: AsyncSession, photo_ids: List[str]) -> Tuple[List[str], List[str]]:
        """
        批量删除照片
        
        Args:
            db: 数据库会话
            photo_ids: 要删除的照片ID列表
            
        Returns:
            (成功删除的ID列表, 失败的ID列表)
        """
        success_ids = []
        failed_ids = []
        
        for photo_id in photo_ids:
            try:
                photo = await PhotoService.get_photo_by_id(db, photo_id)
                if not photo:
                    failed_ids.append(photo_id)
                    continue
                
                # 删除关联文件
                PhotoService._delete_photo_files(photo)
                
                # 删除数据库记录
                await db.delete(photo)
                success_ids.append(photo_id)
                
            except Exception as e:
                print(f"删除照片失败 {photo_id}: {e}")
                failed_ids.append(photo_id)
        
        # 提交所有删除操作
        if success_ids:
            await db.commit()
            
        return success_ids, failed_ids
    
    @staticmethod
    async def update_thumbnails(
        db: AsyncSession,
        photo_id: str,
        thumbnail_small: str,
        thumbnail_medium: str,
        thumbnail_large: str
    ) -> Optional[Photo]:
        """更新缩略图路径"""
        photo = await PhotoService.get_photo_by_id(db, photo_id)
        if not photo:
            return None
        
        photo.thumbnail_small = thumbnail_small
        photo.thumbnail_medium = thumbnail_medium
        photo.thumbnail_large = thumbnail_large
        await db.commit()
        await db.refresh(photo)
        return photo
    
    @staticmethod
    async def update_ai_tags(
        db: AsyncSession,
        photo_id: str,
        ai_tags: dict
    ) -> Optional[Photo]:
        """更新AI标签"""
        photo = await PhotoService.get_photo_by_id(db, photo_id)
        if not photo:
            return None
        
        photo.ai_tags = ai_tags
        await db.commit()
        await db.refresh(photo)
        return photo
