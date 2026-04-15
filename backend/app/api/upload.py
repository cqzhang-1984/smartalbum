from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
import os
import uuid
from app.database import get_db
from app.config import settings
from app.models.photo import Photo
from app.schemas.photo import PhotoCreate
from app.services.photo_service import PhotoService
from app.services.thumbnail_service import ThumbnailService
from app.services.exif_service import EXIFService
from app.services.ai_service import ai_service
from app.services.vector_service import vector_service
from app.services.cos_service import cos_service
from app.services.logger_service import logger_service
from app.utils.file_utils import (
    calculate_file_hash,
    save_upload_file,
    is_allowed_file,
    get_photo_path,
    get_thumbnail_paths,
    ensure_storage_directories,
    validate_upload_file
)

router = APIRouter()


def process_ai_analysis_sync(photo_id: str, image_path: str):
    """
    后台任务：执行AI分析和向量化（同步包装器）
    """
    import asyncio
    asyncio.run(_process_ai_analysis_async(photo_id, image_path))


async def _process_ai_analysis_async(photo_id: str, image_path: str, cos_key: str = None):
    """
    后台任务：执行AI分析和向量化
    
    Args:
        photo_id: 照片ID
        image_path: 本地图片路径（如果是COS存储，需要下载）
        cos_key: COS文件key（如果使用COS存储）
    """
    try:
        logger_service.info(f"开始AI分析: {photo_id}")
        
        # 如果是COS存储，需要先下载到本地
        local_path = image_path
        temp_file = None
        image_url = None
        
        if image_path.startswith('cos://'):
            # 从COS下载到临时文件
            import tempfile
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
            local_path = temp_file.name
            temp_file.close()
            
            key = image_path.replace('cos://', '')
            success, error = cos_service.download_file(key, local_path)
            if not success:
                logger_service.error(f"COS下载失败: {error}")
                return
            
            # 生成COS签名URL供AI API使用
            image_url = cos_service.get_url(key, expires=3600)
            logger_service.info(f"生成COS签名URL: {image_url[:100]}...")
        
        # 执行AI分析（传递URL优先）
        result = await ai_service.analyze_image(local_path, image_url=image_url)
        
        # 清理临时文件
        if temp_file:
            try:
                os.unlink(local_path)
            except:
                pass
        
        if result and result.get('overall_description'):
            # 更新数据库中的AI标签
            from app.database import AsyncSessionLocal
            async with AsyncSessionLocal() as db:
                photo = await PhotoService.get_photo_by_id(db, photo_id)
                if photo:
                    photo.ai_tags = result
                    await db.commit()
                    logger_service.info(f"AI标签已保存: {photo_id}")
                    
                    # 生成向量嵌入
                    description = result['overall_description']
                    metadata = {
                        'subject_emotion': result.get('subject_emotion'),
                        'pose': result.get('pose'),
                        'clothing_style': result.get('clothing_style'),
                        'lighting': result.get('lighting'),
                        'environment': result.get('environment'),
                        'aesthetic_score': result.get('aesthetic_score')
                    }
                    await vector_service.add_photo_embedding(photo_id, description, metadata)
                    logger_service.info(f"向量嵌入完成: {photo_id}")
        
        logger_service.info(f"AI分析完成: {photo_id}")
        
    except Exception as e:
        logger_service.error(f"AI分析失败 {photo_id}: {e}")


@router.post("/")
async def upload_photos(
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    files: List[UploadFile] = File(...)
):
    """批量上传照片（支持COS存储，自动触发AI分析）"""
    ensure_storage_directories()
    
    uploaded_files = []
    skipped_files = []
    use_cos = cos_service.is_enabled()
    
    for file in files:
        # 完整文件验证（扩展名、大小、内容类型、文件头签名）
        is_valid, error_msg = await validate_upload_file(file)
        if not is_valid:
            skipped_files.append({
                "filename": file.filename,
                "reason": error_msg
            })
            continue
        
        # 保存临时文件以计算哈希
        temp_path = os.path.join(settings.STORAGE_PATH, f"temp_{uuid.uuid4()}")
        await save_upload_file(file, temp_path)
        
        # 获取文件大小
        file_size = os.path.getsize(temp_path)
        
        # 计算文件哈希
        file_hash = calculate_file_hash(temp_path)
        
        # 检查是否已存在
        existing_photo = await PhotoService.get_photo_by_hash(db, file_hash)
        if existing_photo:
            os.remove(temp_path)
            skipped_files.append({
                "filename": file.filename,
                "reason": "照片已存在",
                "photo_id": existing_photo.id
            })
            continue
        
        # 生成存储路径
        relative_path, absolute_path = get_photo_path(file_hash, file.filename)
        
        # 存储文件
        if use_cos:
            # 上传到COS
            success, result = cos_service.upload_file(temp_path, relative_path)
            if success:
                # 删除本地临时文件
                os.remove(temp_path)
                logger_service.info(f"COS上传成功: {file.filename} -> {relative_path}")
                # 记录COS路径用于后续处理
                cos_path = relative_path
            else:
                # COS上传失败，使用本地存储
                logger_service.warning(f"COS上传失败，使用本地存储: {result}")
                os.makedirs(os.path.dirname(absolute_path), exist_ok=True)
                os.rename(temp_path, absolute_path)
                cos_path = None
        else:
            # 使用本地存储
            os.makedirs(os.path.dirname(absolute_path), exist_ok=True)
            os.rename(temp_path, absolute_path)
            logger_service.info(f"本地存储: {file.filename} -> {absolute_path}")
            cos_path = None
        
        # 同步生成缩略图
        # 需要本地文件来生成缩略图
        if use_cos and cos_path:
            # 从COS下载到临时文件生成缩略图
            import tempfile
            
            # 创建临时目录存放缩略图
            temp_thumb_dir = tempfile.mkdtemp(prefix='thumbnails_')
            
            with tempfile.NamedTemporaryFile(delete=False, suffix='.jpg') as tmp:
                temp_local_path = tmp.name
            cos_service.download_file(cos_path, temp_local_path)
            
            # 生成缩略图到临时目录
            thumbnail_paths = ThumbnailService.generate_thumbnails(
                temp_local_path,
                temp_thumb_dir,
                file_hash
            )
            logger_service.info(f"生成缩略图结果: {thumbnail_paths}")
            
            # 上传缩略图到COS
            for size_name, thumb_path in thumbnail_paths.items():
                if thumb_path:
                    # 缩略图在临时目录中
                    local_thumb = os.path.join(temp_thumb_dir, os.path.basename(thumb_path))
                    # 对于子目录结构
                    if '/' in thumb_path:
                        subdir = os.path.dirname(thumb_path).split('/')[-1]  # small/medium/large
                        local_thumb = os.path.join(temp_thumb_dir, subdir, os.path.basename(thumb_path))
                    
                    logger_service.info(f"检查缩略图文件: {local_thumb}")
                    if os.path.exists(local_thumb):
                        success, result = cos_service.upload_file(local_thumb, thumb_path)
                        if success:
                            logger_service.info(f"缩略图上传到COS成功: {thumb_path}")
                        else:
                            logger_service.error(f"缩略图上传到COS失败: {result}")
                    else:
                        logger_service.warning(f"缩略图文件不存在: {local_thumb}")
            
            # 清理临时文件和目录
            os.remove(temp_local_path)
            import shutil
            shutil.rmtree(temp_thumb_dir, ignore_errors=True)
        else:
            thumbnail_paths = ThumbnailService.generate_thumbnails(
                absolute_path,
                settings.THUMBNAILS_PATH,
                file_hash
            )
        
        logger_service.info(f"生成缩略图: {thumbnail_paths}")
        
        # 提取EXIF信息
        if use_cos and cos_path:
            import tempfile
            with tempfile.NamedTemporaryFile(delete=False, suffix='.jpg') as tmp:
                temp_local_path = tmp.name
            cos_service.download_file(cos_path, temp_local_path)
            exif_data = EXIFService.extract_exif(temp_local_path)
            os.remove(temp_local_path)
        else:
            exif_data = EXIFService.extract_exif(absolute_path)
        
        logger_service.info(f"提取EXIF: {exif_data}")
        
        # 创建数据库记录
        photo_data = PhotoCreate(
            filename=file.filename,
            original_path=relative_path,
            file_size=file_size,
            file_hash=file_hash
        )
        
        photo = await PhotoService.create_photo(db, photo_data)
        
        # 更新缩略图路径和EXIF信息
        if thumbnail_paths:
            photo.thumbnail_small = thumbnail_paths.get('small')
            photo.thumbnail_medium = thumbnail_paths.get('medium')
            photo.thumbnail_large = thumbnail_paths.get('large')
        
        if exif_data:
            photo.shot_time = exif_data.get('shot_time')
            photo.camera_model = exif_data.get('camera_model')
            photo.lens_model = exif_data.get('lens_model')
            photo.focal_length = exif_data.get('focal_length')
            photo.aperture = exif_data.get('aperture')
            photo.shutter_speed = exif_data.get('shutter_speed')
            photo.iso = exif_data.get('iso')
        
        await db.commit()
        await db.refresh(photo)
        
        # 添加后台任务：自动触发AI分析
        if background_tasks:
            if use_cos and cos_path:
                # COS存储，传递COS路径标识
                ai_image_path = f"cos://{cos_path}"
            else:
                ai_image_path = absolute_path
            background_tasks.add_task(process_ai_analysis_sync, photo.id, ai_image_path)
            logger_service.info(f"已添加AI分析任务: {photo.id}")
        
        uploaded_files.append({
            "photo_id": photo.id,
            "filename": file.filename,
            "size": file_size,
            "status": "completed",
            "thumbnails": thumbnail_paths,
            "ai_analysis": "queued",
            "storage": "cos" if use_cos else "local"
        })
    
    logger_service.info(f"上传完成: {len(uploaded_files)} 成功, {len(skipped_files)} 跳过")
    
    return {
        "uploaded": len(uploaded_files),
        "skipped": len(skipped_files),
        "files": uploaded_files,
        "skipped_files": skipped_files,
        "storage": "cos" if use_cos else "local",
        "message": "上传完成，AI分析将在后台自动进行"
    }


@router.post("/single")
async def upload_single_photo(
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    file: UploadFile = File(...)
):
    """上传单张照片（自动触发AI分析）"""
    result = await upload_photos([file], background_tasks, db)
    
    if result["uploaded"] > 0:
        return {
            "message": "上传成功，AI分析将在后台进行",
            "photo_id": result["files"][0]["photo_id"],
            "thumbnails": result["files"][0]["thumbnails"],
            "ai_analysis": "queued",
            "storage": result.get("storage", "local")
        }
    else:
        raise HTTPException(
            status_code=400,
            detail=result["skipped_files"][0]["reason"] if result["skipped_files"] else "上传失败"
        )


@router.get("/status/{task_id}")
async def get_upload_status(task_id: str):
    """获取上传任务状态（已弃用，保留兼容）"""
    return {
        'state': 'SUCCESS',
        'status': '已完成（同步处理）'
    }
