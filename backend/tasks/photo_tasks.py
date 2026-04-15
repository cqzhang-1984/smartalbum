"""
照片处理异步任务
"""
import os
from typing import Dict
from celery import shared_task
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.config import settings
from app.models.photo import Photo
from app.services.thumbnail_service import ThumbnailService
from app.services.exif_service import EXIFService
from app.services.photo_service import PhotoService

# 创建同步数据库引擎（Celery任务中不能使用异步）
engine = create_engine(
    settings.DATABASE_URL.replace('+aiosqlite', ''),
    echo=False
)
SessionLocal = sessionmaker(bind=engine)


@shared_task(name='tasks.photo_tasks.process_uploaded_photo')
def process_uploaded_photo(photo_id: str, file_path: str) -> Dict:
    """
    处理上传的照片
    包括：生成缩略图、解析EXIF、更新数据库
    """
    db = SessionLocal()
    
    try:
        # 获取照片记录
        photo = db.query(Photo).filter(Photo.id == photo_id).first()
        if not photo:
            return {'status': 'error', 'message': 'Photo not found'}
        
        # 解析EXIF信息
        exif_data = EXIFService.extract_exif(file_path)
        
        # 更新EXIF信息
        if exif_data.get('shot_time'):
            photo.shot_time = exif_data['shot_time']
        if exif_data.get('camera_model'):
            photo.camera_model = exif_data['camera_model']
        if exif_data.get('lens_model'):
            photo.lens_model = exif_data['lens_model']
        if exif_data.get('focal_length'):
            photo.focal_length = exif_data['focal_length']
        if exif_data.get('aperture'):
            photo.aperture = exif_data['aperture']
        if exif_data.get('shutter_speed'):
            photo.shutter_speed = exif_data['shutter_speed']
        if exif_data.get('iso'):
            photo.iso = exif_data['iso']
        
        # 生成缩略图
        file_hash = photo.file_hash
        thumbnails = ThumbnailService.generate_thumbnails(
            file_path,
            settings.THUMBNAILS_PATH,
            file_hash
        )
        
        # 更新缩略图路径
        if thumbnails.get('small'):
            photo.thumbnail_small = thumbnails['small']
        if thumbnails.get('medium'):
            photo.thumbnail_medium = thumbnails['medium']
        if thumbnails.get('large'):
            photo.thumbnail_large = thumbnails['large']
        
        # 提交更改
        db.commit()
        
        return {
            'status': 'success',
            'photo_id': photo_id,
            'exif': exif_data,
            'thumbnails': thumbnails
        }
        
    except Exception as e:
        db.rollback()
        print(f"处理照片失败: {e}")
        return {
            'status': 'error',
            'message': str(e)
        }
    finally:
        db.close()


@shared_task(name='tasks.photo_tasks.batch_process_photos')
def batch_process_photos(photo_ids: list) -> Dict:
    """
    批量处理照片
    """
    results = []
    for photo_id in photo_ids:
        db = SessionLocal()
        try:
            photo = db.query(Photo).filter(Photo.id == photo_id).first()
            if photo:
                file_path = os.path.join(settings.ORIGINALS_PATH, photo.original_path)
                result = process_uploaded_photo(photo_id, file_path)
                results.append(result)
        finally:
            db.close()
    
    return {
        'total': len(photo_ids),
        'processed': len(results),
        'results': results
    }


@shared_task(name='tasks.photo_tasks.regenerate_thumbnails')
def regenerate_thumbnails(photo_id: str) -> Dict:
    """
    重新生成缩略图
    """
    db = SessionLocal()
    
    try:
        photo = db.query(Photo).filter(Photo.id == photo_id).first()
        if not photo:
            return {'status': 'error', 'message': 'Photo not found'}
        
        file_path = os.path.join(settings.ORIGINALS_PATH, photo.original_path)
        file_hash = photo.file_hash
        
        # 生成缩略图
        thumbnails = ThumbnailService.generate_thumbnails(
            file_path,
            settings.THUMBNAILS_PATH,
            file_hash
        )
        
        # 更新数据库
        if thumbnails.get('small'):
            photo.thumbnail_small = thumbnails['small']
        if thumbnails.get('medium'):
            photo.thumbnail_medium = thumbnails['medium']
        if thumbnails.get('large'):
            photo.thumbnail_large = thumbnails['large']
        
        db.commit()
        
        return {
            'status': 'success',
            'photo_id': photo_id,
            'thumbnails': thumbnails
        }
        
    except Exception as e:
        db.rollback()
        return {
            'status': 'error',
            'message': str(e)
        }
    finally:
        db.close()
