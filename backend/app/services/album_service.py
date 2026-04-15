"""
相册服务
"""
from typing import List, Optional, Dict
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_
from sqlalchemy.orm import joinedload
from app.models.album import Album, AlbumPhoto
from app.models.photo import Photo
import json


class AlbumService:
    """相册服务类"""
    
    @staticmethod
    async def create_album(
        db: AsyncSession,
        name: str,
        description: Optional[str] = None,
        is_smart: bool = False,
        rules: Optional[List[Dict]] = None
    ) -> Album:
        """创建相册"""
        album = Album(
            name=name,
            description=description,
            is_smart=is_smart,
            rules=rules if is_smart else None
        )
        db.add(album)
        await db.commit()
        await db.refresh(album)
        
        # 如果是智能相册，立即应用规则
        if is_smart and rules:
            await AlbumService.apply_smart_album_rules(db, album.id)
        
        return album
    
    @staticmethod
    async def get_album_by_id(db: AsyncSession, album_id: str) -> Optional[Album]:
        """根据ID获取相册"""
        result = await db.execute(
            select(Album).options(joinedload(Album.photos)).where(Album.id == album_id)
        )
        return result.unique().scalar_one_or_none()
    
    @staticmethod
    async def get_albums(db: AsyncSession) -> List[Album]:
        """获取所有相册"""
        result = await db.execute(
            select(Album).order_by(Album.created_at.desc())
        )
        return result.scalars().all()
    
    @staticmethod
    async def update_album(
        db: AsyncSession,
        album_id: str,
        name: Optional[str] = None,
        description: Optional[str] = None,
        rules: Optional[List[Dict]] = None
    ) -> Optional[Album]:
        """更新相册"""
        album = await AlbumService.get_album_by_id(db, album_id)
        if not album:
            return None
        
        if name:
            album.name = name
        if description is not None:
            album.description = description
        if rules is not None:
            album.rules = rules
            # 重新应用规则
            await AlbumService.apply_smart_album_rules(db, album_id)
        
        await db.commit()
        await db.refresh(album)
        return album
    
    @staticmethod
    async def delete_album(db: AsyncSession, album_id: str) -> bool:
        """删除相册"""
        from sqlalchemy import delete, select
        
        # 检查相册是否存在
        result = await db.execute(
            select(Album).where(Album.id == album_id)
        )
        album = result.scalar_one_or_none()
        if not album:
            return False
        
        # 先删除关联的照片记录
        from app.models.album import album_photos, AlbumPhoto
        
        try:
            # 删除 album_photos 关联记录
            await db.execute(
                delete(album_photos).where(album_photos.c.album_id == album_id)
            )
            
            # 删除 AlbumPhoto 关联记录
            await db.execute(
                delete(AlbumPhoto).where(AlbumPhoto.album_id == album_id)
            )
            
            # 删除相册
            await db.delete(album)
            await db.commit()
            return True
        except Exception as e:
            await db.rollback()
            raise e
    
    @staticmethod
    async def add_photo_to_album(
        db: AsyncSession,
        album_id: str,
        photo_id: str
    ) -> bool:
        """将照片添加到相册"""
        # 检查是否已存在
        result = await db.execute(
            select(AlbumPhoto).where(
                and_(
                    AlbumPhoto.album_id == album_id,
                    AlbumPhoto.photo_id == photo_id
                )
            )
        )
        if result.scalar_one_or_none():
            return True  # 已存在
        
        album_photo = AlbumPhoto(album_id=album_id, photo_id=photo_id)
        db.add(album_photo)
        
        # 更新相册照片计数
        album = await AlbumService.get_album_by_id(db, album_id)
        if album:
            album.photo_count += 1
        
        await db.commit()
        return True
    
    @staticmethod
    async def remove_photo_from_album(
        db: AsyncSession,
        album_id: str,
        photo_id: str
    ) -> bool:
        """从相册中移除照片"""
        result = await db.execute(
            select(AlbumPhoto).where(
                and_(
                    AlbumPhoto.album_id == album_id,
                    AlbumPhoto.photo_id == photo_id
                )
            )
        )
        album_photo = result.scalar_one_or_none()
        
        if not album_photo:
            return False
        
        await db.delete(album_photo)
        
        # 更新相册照片计数
        album = await AlbumService.get_album_by_id(db, album_id)
        if album:
            album.photo_count = max(0, album.photo_count - 1)
        
        await db.commit()
        return True
    
    @staticmethod
    async def apply_smart_album_rules(
        db: AsyncSession,
        album_id: str
    ) -> int:
        """
        应用智能相册规则
        返回匹配的照片数量
        """
        album = await AlbumService.get_album_by_id(db, album_id)
        if not album or not album.is_smart or not album.rules:
            return 0
        
        # 查询所有照片
        result = await db.execute(select(Photo))
        photos = result.scalars().all()
        
        matched_count = 0
        
        for photo in photos:
            if AlbumService._match_rules(photo, album.rules):
                await AlbumService.add_photo_to_album(db, album_id, photo.id)
                matched_count += 1
        
        return matched_count
    
    @staticmethod
    def _match_rules(photo: Photo, rules: List[Dict]) -> bool:
        """
        检查照片是否匹配规则
        
        规则格式：
        [
            {"field": "ai_tags.subject_emotion", "operator": "equals", "value": "慵懒"},
            {"field": "camera_model", "operator": "contains", "value": "Canon"}
        ]
        
        所有规则为AND关系
        """
        for rule in rules:
            field = rule.get('field')
            operator = rule.get('operator')
            value = rule.get('value')
            
            # 获取字段值
            field_value = AlbumService._get_field_value(photo, field)
            
            if not AlbumService._compare(field_value, operator, value):
                return False
        
        return True
    
    @staticmethod
    def _get_field_value(photo: Photo, field: str):
        """
        获取照片字段值
        支持嵌套字段，如 ai_tags.subject_emotion
        """
        parts = field.split('.')
        value = photo
        
        for part in parts:
            if hasattr(value, part):
                value = getattr(value, part)
            elif isinstance(value, dict) and part in value:
                value = value[part]
            else:
                return None
        
        return value
    
    @staticmethod
    def _compare(field_value, operator: str, target_value) -> bool:
        """
        比较字段值
        """
        if field_value is None:
            return False
        
        # 转换为字符串进行比较
        field_value_str = str(field_value).lower()
        target_value_str = str(target_value).lower()
        
        if operator == 'equals':
            return field_value_str == target_value_str
        elif operator == 'contains':
            return target_value_str in field_value_str
        elif operator == 'starts_with':
            return field_value_str.startswith(target_value_str)
        elif operator == 'ends_with':
            return field_value_str.endswith(target_value_str)
        elif operator == 'not_equals':
            return field_value_str != target_value_str
        elif operator == 'greater_than':
            try:
                return float(field_value) > float(target_value)
            except:
                return False
        elif operator == 'less_than':
            try:
                return float(field_value) < float(target_value)
            except:
                return False
        else:
            return False
    
    @staticmethod
    async def get_album_photos(
        db: AsyncSession,
        album_id: str,
        page: int = 1,
        page_size: int = 20
    ) -> tuple[List[Photo], int]:
        """
        获取相册中的照片
        返回: (照片列表, 总数)
        """
        # 查询总数
        count_result = await db.execute(
            select(AlbumPhoto).where(AlbumPhoto.album_id == album_id)
        )
        total = len(count_result.scalars().all())
        
        # 查询照片
        offset = (page - 1) * page_size
        result = await db.execute(
            select(Photo)
            .join(AlbumPhoto)
            .where(AlbumPhoto.album_id == album_id)
            .order_by(AlbumPhoto.added_at.desc())
            .offset(offset)
            .limit(page_size)
        )
        photos = result.scalars().all()
        
        return photos, total
