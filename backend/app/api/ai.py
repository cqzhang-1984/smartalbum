from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from typing import List, Optional
from pydantic import BaseModel
from app.database import get_db
from app.config import settings
from app.services.ai_service import ai_service, embedding_service
from app.services.logger_service import logger_service
from app.services.vector_service import vector_service
from app.services.cos_service import cos_service
from app.services.face_service import face_service
import json
import os
import uuid

router = APIRouter()


class AIConfig(BaseModel):
    """AI配置模型"""
    ai_model_name: Optional[str] = None
    ai_model_id: Optional[str] = None
    ai_api_base: Optional[str] = None
    ai_api_key: Optional[str] = None
    embedding_model_name: Optional[str] = None
    embedding_model_id: Optional[str] = None
    embedding_api_base: Optional[str] = None
    embedding_api_key: Optional[str] = None


@router.get("/config")
async def get_ai_config():
    """获取AI配置"""
    return {
        "ai_model_name": settings.AI_MODEL_NAME,
        "ai_model_id": settings.AI_MODEL_ID,
        "ai_api_base": settings.AI_API_BASE,
        "ai_api_key": "***" if settings.get_ai_api_key() else None,
        "embedding_model_name": settings.EMBEDDING_MODEL_NAME,
        "embedding_model_id": settings.EMBEDDING_MODEL_ID,
        "embedding_api_base": settings.EMBEDDING_API_BASE,
        "embedding_api_key": "***" if settings.get_embedding_api_key() else None
    }


@router.post("/config")
async def update_ai_config(config: AIConfig):
    """更新AI配置（写入.env文件）"""
    env_path = os.path.join(os.path.dirname(__file__), "../../.env")
    
    # 读取现有配置
    existing_lines = []
    if os.path.exists(env_path):
        with open(env_path, 'r', encoding='utf-8') as f:
            existing_lines = f.readlines()
    
    # 更新配置
    config_map = {
        "AI_MODEL_NAME": config.ai_model_name,
        "AI_MODEL_ID": config.ai_model_id,
        "AI_API_BASE": config.ai_api_base,
        "AI_API_KEY": config.ai_api_key,
        "EMBEDDING_MODEL_NAME": config.embedding_model_name,
        "EMBEDDING_MODEL_ID": config.embedding_model_id,
        "EMBEDDING_API_BASE": config.embedding_api_base,
        "EMBEDDING_API_KEY": config.embedding_api_key,
    }
    
    # 过滤掉None值
    config_map = {k: v for k, v in config_map.items() if v is not None}
    
    # 更新或添加配置
    updated_keys = set()
    for i, line in enumerate(existing_lines):
        for key, value in config_map.items():
            if line.startswith(f"{key}="):
                existing_lines[i] = f"{key}={value}\n"
                updated_keys.add(key)
    
    # 添加新配置
    for key, value in config_map.items():
        if key not in updated_keys:
            existing_lines.append(f"{key}={value}\n")
    
    # 写回文件
    with open(env_path, 'w', encoding='utf-8') as f:
        f.writelines(existing_lines)
    
    logger_service.info(f"AI配置已更新: {list(config_map.keys())}")
    
    return {
        "message": "配置已保存，重启服务后生效",
        "updated_keys": list(config_map.keys())
    }


@router.post("/analyze/{photo_id}")
async def trigger_photo_analysis(
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """触发照片AI分析（同步执行）"""
    from app.services.photo_service import PhotoService
    from app.models.photo import Photo
    
    # 获取照片
    photo = await PhotoService.get_photo_by_id(db, photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    
    # 构建完整路径
    image_path = os.path.join(settings.STORAGE_PATH, photo.original_path.replace("/storage/", ""))
    
    if not os.path.exists(image_path):
        raise HTTPException(status_code=404, detail="Photo file not found")
    
    # 执行AI分析
    logger_service.info(f"开始AI分析: {photo_id}")
    result = await ai_service.analyze_image(image_path)
    
    # 更新数据库
    if result:
        photo.ai_tags = result
        await db.commit()
        logger_service.info(f"AI分析完成: {photo_id}")
        
        # 生成向量嵌入
        if result.get('overall_description'):
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
    
    return {
        "message": "AI分析完成",
        "photo_id": photo_id,
        "result": result
    }


@router.post("/deep-analyze/{photo_id}")
async def trigger_deep_analysis(
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """触发照片AI深度分析（后台任务），立即返回"""
    import asyncio
    from app.services.photo_service import PhotoService

    photo = await PhotoService.get_photo_by_id(db, photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="照片不存在")

    # 使用 asyncio.create_task 在后台执行深度分析（比 BackgroundTasks 更可靠）
    asyncio.create_task(_run_deep_analysis(photo_id))
    logger_service.info(f"已提交AI深度分析后台任务: photo_id={photo_id}")

    return {
        "message": "AI深度分析任务已提交",
        "photo_id": photo_id,
        "status": "pending"
    }


def _debug_log(msg):
    """使用统一的日志服务记录调试信息"""
    logger_service.debug(f"[DeepAnalysis] {msg}")

async def _run_deep_analysis(photo_id: str):
    """后台执行深度分析并保存结果到数据库"""
    _debug_log(f"=== _run_deep_analysis START photo_id={photo_id} ===")
    from app.database import AsyncSessionLocal
    from app.services.photo_service import PhotoService

    image_path = None
    image_url = None

    # === 阶段1：获取图片路径信息 ===
    _debug_log("Phase 1: Getting image path...")
    async with AsyncSessionLocal() as db:
        try:
            photo = await PhotoService.get_photo_by_id(db, photo_id)
            if not photo:
                logger_service.error(f"深度分析失败: 照片不存在 {photo_id}")
                return

            if cos_service.is_enabled():
                key = photo.original_path.replace("/storage/", "")
                image_url = cos_service.get_url(key, expires=3600)
                logger_service.info(f"深度分析使用COS URL: {image_url[:100]}...")
            else:
                image_path = os.path.join(settings.STORAGE_PATH, photo.original_path.replace("/storage/", ""))
                if not os.path.exists(image_path):
                    logger_service.error(f"深度分析失败: 文件不存在 {image_path}")
                    return
                logger_service.info(f"深度分析使用本地文件: {image_path}")
        except Exception as e:
            _debug_log(f"Phase 1 FAILED: {e}")
            import traceback
            _debug_log(traceback.format_exc())
            return
    _debug_log(f"Phase 1 OK: image_path={image_path}, image_url={image_url[:80] if image_url else None}...")

    # === 阶段2：执行AI深度分析（耗时1-3分钟） ===
    _debug_log("Phase 2: Calling AI API...")
    try:
        result = await ai_service.deep_analyze_image(image_path, image_url=image_url)
        _debug_log(f"Phase 2 OK: has_result={bool(result)}, has_text={bool(result and result.get('deep_analysis'))}, len={len(result.get('deep_analysis','')) if result else 0}")
    except Exception as e:
        _debug_log(f"Phase 2 FAILED: {e}")
        import traceback
        _debug_log(traceback.format_exc())
        return

    # === 阶段3：保存结果到数据库 ===
    if not result or not result.get('deep_analysis'):
        _debug_log(f"Phase 3 SKIPPED: empty result, result={result}")
        return

    _debug_log("Phase 3: Saving to database...")
    async with AsyncSessionLocal() as db:
        try:
            photo = await PhotoService.get_photo_by_id(db, photo_id)
            if not photo:
                _debug_log(f"Phase 3 FAILED: photo not found {photo_id}")
                return

            existing_tags = photo.ai_tags or {}
            if isinstance(existing_tags, str):
                try:
                    existing_tags = json.loads(existing_tags)
                except Exception:
                    existing_tags = {}

            # 创建新字典确保 SQLAlchemy 检测到变化
            new_tags = dict(existing_tags)
            new_tags['deep_analysis'] = result['deep_analysis']
            new_tags['deep_analysis_time'] = result['deep_analysis_time']
            
            # 使用原生SQL更新，绕过SQLAlchemy JSON变更检测问题
            from app.models.photo import Photo
            stmt = (
                update(Photo)
                .where(Photo.id == photo_id)
                .values(ai_tags=new_tags)
            )
            await db.execute(stmt)
            await db.commit()
            _debug_log(f"Phase 3 OK: commit done, report length={len(result['deep_analysis'])}")

            # 用原始 sqlite3 验证是否写入磁盘
            try:
                import sqlite3 as _sqlite3
                # 从 settings 获取数据库路径，移除 aiosqlite 前缀
                db_path = settings.DATABASE_URL.replace("sqlite+aiosqlite:///.", ".")
                _vconn = _sqlite3.connect(db_path)
                _vcur = _vconn.cursor()
                _vcur.execute("SELECT ai_tags FROM photos WHERE id=?", (photo_id,))
                _vr = _vcur.fetchone()
                _vconn.close()
                _vdata = json.loads(_vr[0]) if _vr and _vr[0] else {}
                _debug_log(f"Phase 3 VERIFY: sqlite3 read has_deep={bool(_vdata.get('deep_analysis'))}")
            except Exception as _ve:
                _debug_log(f"Phase 3 VERIFY ERROR: {_ve}")
        except Exception as e:
            await db.rollback()
            _debug_log(f"Phase 3 FAILED: {e}")
            import traceback
            _debug_log(traceback.format_exc())

    _debug_log(f"=== _run_deep_analysis END photo_id={photo_id} ===")


@router.get("/deep-analyze/{photo_id}/status")
async def get_deep_analysis_status(
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """获取照片AI深度分析的状态和结果"""
    from app.services.photo_service import PhotoService

    photo = await PhotoService.get_photo_by_id(db, photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="照片不存在")

    # 从数据库读取已保存的深度分析结果
    ai_tags = photo.ai_tags or {}
    if isinstance(ai_tags, str):
        try:
            ai_tags = json.loads(ai_tags)
        except Exception:
            ai_tags = {}

    if ai_tags.get('deep_analysis'):
        return {
            "status": "completed",
            "photo_id": photo_id,
            "deep_analysis": ai_tags['deep_analysis'],
            "deep_analysis_time": ai_tags.get('deep_analysis_time')
        }
    else:
        return {
            "status": "not_found",
            "photo_id": photo_id
        }


@router.post("/batch-analyze")
async def trigger_batch_analysis(
    photo_ids: List[str],
    db: AsyncSession = Depends(get_db)
):
    """批量触发照片AI分析"""
    from app.services.photo_service import PhotoService
    
    results = []
    for photo_id in photo_ids:
        try:
            photo = await PhotoService.get_photo_by_id(db, photo_id)
            if photo:
                image_path = os.path.join(settings.STORAGE_PATH, photo.original_path.replace("/storage/", ""))
                if os.path.exists(image_path):
                    result = await ai_service.analyze_image(image_path)
                    if result:
                        photo.ai_tags = result
                        # 生成向量嵌入
                        if result.get('overall_description'):
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
                    results.append({"photo_id": photo_id, "status": "success"})
                else:
                    results.append({"photo_id": photo_id, "status": "file_not_found"})
            else:
                results.append({"photo_id": photo_id, "status": "not_found"})
        except Exception as e:
            results.append({"photo_id": photo_id, "status": "error", "error": str(e)})
    
    await db.commit()
    logger_service.info(f"批量AI分析完成: {len(photo_ids)} 张照片")
    
    return {
        "message": "批量AI分析完成",
        "photo_count": len(photo_ids),
        "results": results
    }


@router.post("/analyze-pending")
async def analyze_pending_photos(
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    limit: int = Query(default=50, ge=1, le=500)
):
    """
    分析所有未进行AI分析的照片（容错机制）
    
    系统异常重启后可调用此接口继续完成未识别的图片
    """
    from app.services.photo_service import PhotoService
    from app.services.cos_service import cos_service
    from app.models.photo import Photo
    from sqlalchemy import select
    
    # 查询所有 ai_tags 为空的照片
    result = await db.execute(
        select(Photo).where(Photo.ai_tags.is_(None)).limit(limit)
    )
    pending_photos = result.scalars().all()
    
    if not pending_photos:
        return {
            "message": "没有待分析的照片",
            "pending_count": 0,
            "queued_count": 0
        }
    
    queued_count = 0
    use_cos = cos_service.is_enabled()
    
    for photo in pending_photos:
        try:
            # 确定图片路径
            if use_cos:
                # COS 存储，传递 COS 路径标识
                ai_image_path = f"cos://{photo.original_path}"
            else:
                # 本地存储
                ai_image_path = os.path.join(settings.STORAGE_PATH, photo.original_path.replace("/storage/", ""))
                if not os.path.exists(ai_image_path):
                    logger_service.warning(f"照片文件不存在: {ai_image_path}")
                    continue
            
            # 添加后台任务
            background_tasks.add_task(
                _process_pending_analysis,
                photo.id,
                ai_image_path
            )
            queued_count += 1
            
        except Exception as e:
            logger_service.error(f"添加分析任务失败 {photo.id}: {e}")
    
    return {
        "message": f"已将 {queued_count} 张照片加入分析队列",
        "pending_count": len(pending_photos),
        "queued_count": queued_count
    }


async def _process_pending_analysis(photo_id: str, image_path: str):
    """后台处理待分析的照片"""
    import asyncio
    await _process_ai_analysis_async(photo_id, image_path)


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
                import os
                os.unlink(local_path)
            except:
                pass
        
        if result and result.get('overall_description'):
            # 更新数据库中的AI标签
            from app.database import AsyncSessionLocal
            from app.services.photo_service import PhotoService
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


@router.get("/models")
async def get_available_models():
    """获取可用的AI模型列表"""
    return {
        "models": [
            {
                "provider": "openai",
                "name": "GPT-4o",
                "model": "gpt-4o",
                "supports_vision": True
            },
            {
                "provider": "google",
                "name": "Gemini 1.5 Pro",
                "model": "gemini-1.5-pro",
                "supports_vision": True
            },
            {
                "provider": "anthropic",
                "name": "Claude 3.5 Sonnet",
                "model": "claude-3-5-sonnet-20241022",
                "supports_vision": True
            },
            {
                "provider": "doubao",
                "name": "豆包 Seed",
                "model": "doubao-seed-2-0-mini-260215",
                "supports_vision": True
            }
        ],
        "current": {
            "model_name": settings.AI_MODEL_NAME,
            "model_id": settings.AI_MODEL_ID
        }
    }


# ==================== 人脸识别相关API ====================

@router.post("/faces/detect/{photo_id}")
async def detect_photo_faces(
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """
    检测单张照片中的人脸并尝试匹配到已有聚类
    """
    from app.models.photo import Photo, FaceCluster
    
    # 获取照片
    result = await db.execute(select(Photo).where(Photo.id == photo_id))
    photo = result.scalar_one_or_none()
    
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    
    # 构建图片路径
    image_path = os.path.join(settings.STORAGE_PATH, photo.original_path.replace("/storage/", ""))
    
    if not os.path.exists(image_path):
        raise HTTPException(status_code=404, detail="Photo file not found")
    
    # 检测人脸
    logger_service.info(f"开始人脸检测: {photo_id}")
    face_result = face_service.detect_faces(image_path)
    
    if face_result.get('error'):
        raise HTTPException(status_code=500, detail=face_result['error'])
    
    faces_detected = face_result['faces_detected']
    face_encodings = face_result['face_encodings']
    face_cluster_id = None
    
    # 如果检测到人脸，尝试匹配已有聚类
    if faces_detected > 0 and len(face_encodings) > 0:
        # 获取所有已有聚类
        clusters_result = await db.execute(select(FaceCluster))
        existing_clusters = clusters_result.scalars().all()
        
        # 准备已知聚类数据
        known_clusters = []
        for cluster in existing_clusters:
            if cluster.face_encoding:
                encoding = face_service.list_to_encoding(cluster.face_encoding)
                known_clusters.append({
                    'id': cluster.id,
                    'encoding': encoding
                })
        
        # 使用第一个人脸进行匹配
        primary_encoding = face_encodings[0]
        
        # 尝试匹配
        matched, matched_cluster_id, distance = face_service.find_best_match(
            primary_encoding, 
            known_clusters
        )
        
        if matched and matched_cluster_id:
            face_cluster_id = matched_cluster_id
            # 更新聚类信息
            cluster_result = await db.execute(
                select(FaceCluster).where(FaceCluster.id == matched_cluster_id)
            )
            cluster = cluster_result.scalar_one_or_none()
            if cluster and cluster.face_encoding:
                existing_encoding = face_service.list_to_encoding(cluster.face_encoding)
                new_avg_encoding = face_service.compute_average_encoding([
                    existing_encoding, primary_encoding
                ])
                cluster.face_encoding = face_service.encoding_to_list(new_avg_encoding)
                cluster.photo_count += 1
        else:
            # 创建新聚类
            new_cluster = FaceCluster(
                face_encoding=face_service.encoding_to_list(primary_encoding),
                photo_count=1,
                name=None
            )
            db.add(new_cluster)
            await db.flush()
            face_cluster_id = new_cluster.id
        
        # 更新照片的聚类ID
        photo.face_cluster_id = face_cluster_id
    
    await db.commit()
    logger_service.info(f"人脸检测完成: {photo_id}, 检测到 {faces_detected} 张人脸")
    
    return {
        "message": "人脸检测完成",
        "photo_id": photo_id,
        "faces_detected": faces_detected,
        "face_cluster_id": face_cluster_id
    }


@router.post("/faces/batch-detect")
async def batch_detect_faces(
    photo_ids: List[str],
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db)
):
    """
    批量检测人脸（后台任务）
    """
    from app.models.photo import Photo
    
    # 验证照片是否存在
    valid_photo_ids = []
    result = await db.execute(select(Photo.id).where(Photo.id.in_(photo_ids)))
    existing_ids = [row[0] for row in result.fetchall()]
    
    for photo_id in photo_ids:
        if photo_id in existing_ids:
            valid_photo_ids.append(photo_id)
    
    if not valid_photo_ids:
        return {
            "message": "没有有效的照片",
            "queued_count": 0
        }
    
    # 触发Celery后台任务
    from tasks.ai_tasks import batch_detect_faces as celery_batch_detect
    celery_batch_detect.delay(valid_photo_ids)
    
    return {
        "message": f"已将 {len(valid_photo_ids)} 张照片加入人脸检测队列",
        "queued_count": len(valid_photo_ids)
    }


@router.post("/faces/recluster")
async def recluster_all_faces():
    """
    重新对所有照片进行人脸聚类
    这个操作会重新分析所有照片的人脸并重新建立聚类
    """
    from tasks.ai_tasks import recluster_all_faces as celery_recluster
    
    # 触发后台任务
    task = celery_recluster.delay()
    
    return {
        "message": "人脸重新聚类任务已启动",
        "task_id": task.id
    }


@router.get("/faces/clusters")
async def get_face_clusters(
    db: AsyncSession = Depends(get_db)
):
    """
    获取所有人脸聚类
    """
    from app.models.photo import FaceCluster, Photo
    from sqlalchemy.orm import selectinload
    
    result = await db.execute(
        select(FaceCluster).order_by(FaceCluster.photo_count.desc())
    )
    clusters = result.scalars().all()
    
    cluster_list = []
    for cluster in clusters:
        # 获取聚类下的照片
        photos_result = await db.execute(
            select(Photo).where(Photo.face_cluster_id == cluster.id).limit(4)
        )
        sample_photos = photos_result.scalars().all()
        
        cluster_list.append({
            "id": cluster.id,
            "name": cluster.name,
            "photo_count": cluster.photo_count,
            "cover_photo_id": cluster.cover_photo_id,
            "sample_photos": [
                {
                    "id": p.id,
                    "filename": p.filename,
                    "thumbnail_small": p.thumbnail_small
                } for p in sample_photos
            ],
            "created_at": cluster.created_at.isoformat() if cluster.created_at else None
        })
    
    return {
        "clusters": cluster_list,
        "total_clusters": len(cluster_list)
    }


@router.get("/faces/clusters/{cluster_id}")
async def get_face_cluster(
    cluster_id: str,
    db: AsyncSession = Depends(get_db),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100)
):
    """
    获取指定人脸聚类的详情和照片列表
    """
    from app.models.photo import FaceCluster, Photo
    
    # 获取聚类
    result = await db.execute(
        select(FaceCluster).where(FaceCluster.id == cluster_id)
    )
    cluster = result.scalar_one_or_none()
    
    if not cluster:
        raise HTTPException(status_code=404, detail="Cluster not found")
    
    # 获取照片总数
    count_result = await db.execute(
        select(Photo).where(Photo.face_cluster_id == cluster_id)
    )
    total_photos = len(count_result.scalars().all())
    
    # 分页获取照片
    offset = (page - 1) * page_size
    photos_result = await db.execute(
        select(Photo)
        .where(Photo.face_cluster_id == cluster_id)
        .order_by(Photo.shot_time.desc())
        .offset(offset)
        .limit(page_size)
    )
    photos = photos_result.scalars().all()
    
    return {
        "cluster": {
            "id": cluster.id,
            "name": cluster.name,
            "photo_count": cluster.photo_count,
            "cover_photo_id": cluster.cover_photo_id,
            "created_at": cluster.created_at.isoformat() if cluster.created_at else None
        },
        "photos": [
            {
                "id": p.id,
                "filename": p.filename,
                "thumbnail_small": p.thumbnail_small,
                "thumbnail_medium": p.thumbnail_medium,
                "shot_time": p.shot_time.isoformat() if p.shot_time else None,
                "is_favorite": p.is_favorite,
                "rating": p.rating
            } for p in photos
        ],
        "pagination": {
            "page": page,
            "page_size": page_size,
            "total_photos": total_photos,
            "total_pages": (total_photos + page_size - 1) // page_size
        }
    }


@router.put("/faces/clusters/{cluster_id}")
async def update_face_cluster(
    cluster_id: str,
    name: Optional[str] = None,
    cover_photo_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """
    更新人脸聚类信息（名称、封面照片）
    """
    from app.models.photo import FaceCluster
    
    result = await db.execute(
        select(FaceCluster).where(FaceCluster.id == cluster_id)
    )
    cluster = result.scalar_one_or_none()
    
    if not cluster:
        raise HTTPException(status_code=404, detail="Cluster not found")
    
    if name:
        cluster.name = name
    
    if cover_photo_id:
        cluster.cover_photo_id = cover_photo_id
    
    await db.commit()
    
    return {
        "message": "聚类信息已更新",
        "cluster_id": cluster_id,
        "name": cluster.name,
        "cover_photo_id": cluster.cover_photo_id
    }


@router.delete("/faces/clusters/{cluster_id}")
async def delete_face_cluster(
    cluster_id: str,
    db: AsyncSession = Depends(get_db)
):
    """
    删除人脸聚类（不影响照片，只是解除关联）
    """
    from app.models.photo import FaceCluster, Photo
    
    result = await db.execute(
        select(FaceCluster).where(FaceCluster.id == cluster_id)
    )
    cluster = result.scalar_one_or_none()
    
    if not cluster:
        raise HTTPException(status_code=404, detail="Cluster not found")
    
    # 解除照片关联
    await db.execute(
        Photo.__table__.update()
        .where(Photo.face_cluster_id == cluster_id)
        .values(face_cluster_id=None)
    )
    
    # 删除聚类
    await db.delete(cluster)
    await db.commit()
    
    return {
        "message": "聚类已删除",
        "cluster_id": cluster_id
    }


# ==================== AI图片生成相关API ====================

class ImageGenRequest(BaseModel):
    """图片生成请求模型"""
    prompt: str
    negative_prompt: Optional[str] = None
    model_id: Optional[str] = None
    size_ratio: Optional[str] = None  # 尺寸比例（1:1, 16:9, 9:16 等）
    width: Optional[int] = None
    height: Optional[int] = None
    output_format: Optional[str] = None
    seed: Optional[int] = None
    save_to_album: bool = False
    title: Optional[str] = None
    source_photo_id: Optional[str] = None


class ImageToImageRequest(BaseModel):
    """图生图请求模型"""
    prompt: str
    negative_prompt: Optional[str] = None
    model_id: Optional[str] = None
    size_ratio: Optional[str] = None
    strength: float = 0.7  # 参考强度
    output_format: Optional[str] = None
    save_to_album: bool = False
    title: Optional[str] = None


@router.get("/image-gen/models")
async def get_image_gen_models():
    """获取可用的文生图模型列表"""
    from app.services.image_generation_service import image_generation_service
    return {
        "models": image_generation_service.get_available_models(),
        "sizes": image_generation_service.get_available_sizes(),
        "current": image_generation_service.get_current_config()
    }


@router.post("/image-gen/generate")
async def generate_image(
    request: ImageGenRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    生成AI图片（文生图）
    """
    from app.services.image_generation_service import image_generation_service
    from app.models.photo import AIGeneratedImage
    
    # 调用生成服务
    result = await image_generation_service.generate_image(
        prompt=request.prompt,
        negative_prompt=request.negative_prompt,
        model_id=request.model_id,
        size_ratio=request.size_ratio,
        width=request.width,
        height=request.height,
        output_format=request.output_format,
        seed=request.seed
    )
    
    if not result.get('success'):
        raise HTTPException(status_code=500, detail=result.get('error', '生成失败'))
    
    # 保存生成记录到数据库
    generated_image = AIGeneratedImage(
        prompt=request.prompt,
        negative_prompt=request.negative_prompt,
        model_id=request.model_id or image_generation_service.default_model,
        model_name=image_generation_service.available_models.get(request.model_id or image_generation_service.default_model, {}).get('name', request.model_id),
        width=result.get('width'),
        height=result.get('height'),
        size_ratio=request.size_ratio,
        output_format=request.output_format or image_generation_service.default_format,
        image_url=result.get('image_url'),
        local_path=result.get('local_path'),
        source_photo_id=request.source_photo_id,
        title=request.title,
        generation_params=result.get('generation_params', {}),
        usage_info=result.get('usage')
    )
    
    # 如果需要保存到相册
    if request.save_to_album and result.get('local_path'):
        from app.services.photo_service import PhotoService
        import shutil
        
        ext = request.output_format or 'png'
        new_filename = f"ai_{uuid.uuid4().hex[:8]}.{ext}"
        originals_dir = os.path.join(settings.STORAGE_PATH, "originals")
        os.makedirs(originals_dir, exist_ok=True)
        new_path = os.path.join(originals_dir, new_filename)
        
        shutil.copy(result['local_path'], new_path)
        
        file_size = os.path.getsize(new_path)
        photo = await PhotoService.create_photo(
            db=db,
            filename=request.title or f"AI生成_{new_filename}",
            original_path=f"/storage/originals/{new_filename}",
            file_size=file_size,
            file_hash=uuid.uuid4().hex
        )
        
        generated_image.is_saved = True
        generated_image.saved_photo_id = photo.id
        logger_service.info(f"AI生成图片已保存到相册: {photo.id}")
    
    db.add(generated_image)
    await db.commit()
    await db.refresh(generated_image)
    
    logger_service.info(f"AI图片生成记录已保存: {generated_image.id}")
    
    return {
        "success": True,
        "id": generated_image.id,
        "image_url": result.get('image_url'),
        "local_path": f"/storage/ai_generated/{os.path.basename(result.get('local_path'))}" if result.get('local_path') else None,
        "model": result.get('model'),
        "width": result.get('width'),
        "height": result.get('height'),
        "size_ratio": request.size_ratio,
        "is_saved": generated_image.is_saved,
        "saved_photo_id": generated_image.saved_photo_id,
        "created_at": generated_image.created_at.isoformat()
    }


@router.post("/image-gen/generate-from-photo/{photo_id}")
async def generate_from_photo(
    photo_id: str,
    request: ImageToImageRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    基于照片生成AI图片（图生图）
    """
    from app.services.image_generation_service import image_generation_service
    from app.models.photo import AIGeneratedImage, Photo
    from app.services.photo_service import PhotoService
    
    # 获取源照片
    photo = await PhotoService.get_photo_by_id(db, photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="照片不存在")
    
    # 构建源图片路径
    image_path = os.path.join(settings.STORAGE_PATH, photo.original_path.replace("/storage/", ""))
    if not os.path.exists(image_path):
        raise HTTPException(status_code=404, detail="照片文件不存在")
    
    # 调用图生图服务
    result = await image_generation_service.generate_from_photo(
        photo_path=image_path,
        prompt=request.prompt,
        negative_prompt=request.negative_prompt,
        model_id=request.model_id,
        strength=request.strength,
        size_ratio=request.size_ratio,
        output_format=request.output_format
    )
    
    if not result.get('success'):
        raise HTTPException(status_code=500, detail=result.get('error', '生成失败'))
    
    # 保存生成记录
    generated_image = AIGeneratedImage(
        prompt=request.prompt,
        negative_prompt=request.negative_prompt,
        model_id=request.model_id or image_generation_service.default_model,
        model_name=image_generation_service.available_models.get(request.model_id or image_generation_service.default_model, {}).get('name', request.model_id),
        width=result.get('width'),
        height=result.get('height'),
        size_ratio=request.size_ratio,
        output_format=request.output_format or image_generation_service.default_format,
        image_url=result.get('image_url'),
        local_path=result.get('local_path'),
        source_photo_id=photo_id,
        title=request.title,
        generation_params=result.get('generation_params', {}),
        usage_info=result.get('usage')
    )
    
    # 保存到相册
    if request.save_to_album and result.get('local_path'):
        import shutil
        
        ext = request.output_format or 'png'
        new_filename = f"ai_{uuid.uuid4().hex[:8]}.{ext}"
        originals_dir = os.path.join(settings.STORAGE_PATH, "originals")
        os.makedirs(originals_dir, exist_ok=True)
        new_path = os.path.join(originals_dir, new_filename)
        
        shutil.copy(result['local_path'], new_path)
        
        file_size = os.path.getsize(new_path)
        new_photo = await PhotoService.create_photo(
            db=db,
            filename=request.title or f"AI创作_{new_filename}",
            original_path=f"/storage/originals/{new_filename}",
            file_size=file_size,
            file_hash=uuid.uuid4().hex
        )
        
        generated_image.is_saved = True
        generated_image.saved_photo_id = new_photo.id
        logger_service.info(f"AI创作图片已保存到相册: {new_photo.id}")
    
    db.add(generated_image)
    await db.commit()
    await db.refresh(generated_image)
    
    return {
        "success": True,
        "id": generated_image.id,
        "source_photo_id": photo_id,
        "image_url": result.get('image_url'),
        "local_path": f"/storage/ai_generated/{os.path.basename(result.get('local_path'))}" if result.get('local_path') else None,
        "width": result.get('width'),
        "height": result.get('height'),
        "is_saved": generated_image.is_saved,
        "created_at": generated_image.created_at.isoformat()
    }


@router.get("/image-gen/history")
async def get_image_gen_history(
    db: AsyncSession = Depends(get_db),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    saved_only: bool = Query(default=False, description="仅显示已保存的")
):
    """
    获取AI生成图片历史记录
    """
    from app.models.photo import AIGeneratedImage
    
    query = select(AIGeneratedImage)
    
    if saved_only:
        query = query.where(AIGeneratedImage.is_saved == True)
    
    # 统计总数
    count_query = select(AIGeneratedImage)
    if saved_only:
        count_query = count_query.where(AIGeneratedImage.is_saved == True)
    
    total_result = await db.execute(count_query)
    total = len(total_result.scalars().all())
    
    # 分页查询
    query = query.order_by(AIGeneratedImage.created_at.desc())
    query = query.offset((page - 1) * page_size).limit(page_size)
    
    result = await db.execute(query)
    images = result.scalars().all()
    
    return {
        "images": [
            {
                "id": img.id,
                "prompt": img.prompt,
                "negative_prompt": img.negative_prompt,
                "title": img.title,
                "model_id": img.model_id,
                "model_name": img.model_name,
                "width": img.width,
                "height": img.height,
                "size_ratio": img.size_ratio,
                "size_display": img.size_display,
                "image_url": img.image_url,
                "local_path": f"/storage/ai_generated/{os.path.basename(img.local_path)}" if img.local_path else None,
                "is_saved": img.is_saved,
                "saved_photo_id": img.saved_photo_id,
                "source_photo_id": img.source_photo_id,
                "created_at": img.created_at.isoformat()
            } for img in images
        ],
        "pagination": {
            "page": page,
            "page_size": page_size,
            "total": total,
            "total_pages": (total + page_size - 1) // page_size
        }
    }


@router.post("/image-gen/{image_id}/save")
async def save_generated_image_to_album(
    image_id: str,
    title: Optional[str] = Query(None, description="图片标题"),
    db: AsyncSession = Depends(get_db)
):
    """
    将AI生成的图片保存到相册
    """
    from app.models.photo import AIGeneratedImage
    from app.services.photo_service import PhotoService
    import shutil
    
    # 获取生成记录
    result = await db.execute(
        select(AIGeneratedImage).where(AIGeneratedImage.id == image_id)
    )
    generated_image = result.scalar_one_or_none()
    
    if not generated_image:
        raise HTTPException(status_code=404, detail="生成记录不存在")
    
    if generated_image.is_saved:
        return {
            "message": "图片已保存到相册",
            "photo_id": generated_image.saved_photo_id
        }
    
    if not generated_image.local_path or not os.path.exists(generated_image.local_path):
        raise HTTPException(status_code=404, detail="图片文件不存在")
    
    # 复制到 originals 目录
    ext = generated_image.output_format or 'png'
    new_filename = f"ai_{uuid.uuid4().hex[:8]}.{ext}"
    originals_dir = os.path.join(settings.STORAGE_PATH, "originals")
    os.makedirs(originals_dir, exist_ok=True)
    new_path = os.path.join(originals_dir, new_filename)
    
    shutil.copy(generated_image.local_path, new_path)

    # 生成缩略图
    from app.services.thumbnail_service import ThumbnailService
    thumbnails_dir = os.path.join(settings.STORAGE_PATH, "thumbnails")
    file_hash = uuid.uuid4().hex
    thumbnails = ThumbnailService.generate_thumbnails(new_path, thumbnails_dir, file_hash)

    # 如果启用COS，上传原图和缩略图
    if cos_service.is_enabled():
        # 上传原图
        cos_service.upload_file(new_path, f"originals/{new_filename}")
        # 上传缩略图
        if thumbnails:
            for size_name, thumb_path in thumbnails.items():
                local_thumb = os.path.join(settings.STORAGE_PATH, thumb_path)
                if os.path.exists(local_thumb):
                    cos_service.upload_file(local_thumb, thumb_path)

    # 创建照片记录
    from app.schemas.photo import PhotoCreate
    file_size = os.path.getsize(new_path)
    photo_data = PhotoCreate(
        filename=title or generated_image.title or f"AI生成_{new_filename}",
        original_path=f"originals/{new_filename}",  # 使用相对路径
        file_size=file_size,
        file_hash=file_hash
    )
    photo = await PhotoService.create_photo(db=db, photo_data=photo_data)

    # 更新缩略图路径
    if thumbnails:
        photo.thumbnail_small = thumbnails.get('small')
        photo.thumbnail_medium = thumbnails.get('medium')
        photo.thumbnail_large = thumbnails.get('large')

    # 保存AI生成信息到ai_tags
    photo.ai_tags = {
        "source": "ai_generated",
        "prompt": generated_image.prompt,
        "negative_prompt": generated_image.negative_prompt,
        "model_id": generated_image.model_id,
        "model_name": generated_image.model_name,
        "generation_params": {
            "width": generated_image.width,
            "height": generated_image.height,
            "size_ratio": generated_image.size_ratio,
            "output_format": generated_image.output_format
        }
    }

    # 确保photo对象的修改被保存
    await db.flush()

    # 更新生成记录
    generated_image.is_saved = True
    generated_image.saved_photo_id = photo.id
    generated_image.title = title or generated_image.title
    
    await db.commit()
    logger_service.info(f"AI生成图片已保存到相册: {photo.id}")

    # 触发AI分析（异步执行，不阻塞响应）
    try:
        result = await ai_service.analyze_image(new_path)
        if result:
            # 更新AI标签（保留AI生成信息，添加分析结果）
            existing_tags = photo.ai_tags or {}
            photo.ai_tags = {
                **existing_tags,
                "subject_emotion": result.get('subject_emotion'),
                "pose": result.get('pose'),
                "clothing_style": result.get('clothing_style'),
                "lighting": result.get('lighting'),
                "environment": result.get('environment'),
                "overall_description": result.get('overall_description'),
                "aesthetic_score": result.get('aesthetic_score')
            }
            await db.commit()
            logger_service.info(f"AI分析完成: {photo.id}")

            # 添加向量嵌入
            description = result.get('overall_description', '')
            if description:
                metadata = {
                    'subject_emotion': result.get('subject_emotion'),
                    'pose': result.get('pose'),
                    'clothing_style': result.get('clothing_style'),
                    'lighting': result.get('lighting'),
                    'environment': result.get('environment'),
                    'aesthetic_score': result.get('aesthetic_score')
                }
                await vector_service.add_photo_embedding(photo.id, description, metadata)
    except Exception as e:
        logger_service.warning(f"AI分析失败（不影响保存）: {e}")
    
    return {
        "message": "图片已保存到相册",
        "photo_id": photo.id,
        "generated_image_id": image_id
    }


@router.delete("/image-gen/{image_id}")
async def delete_generated_image(
    image_id: str,
    db: AsyncSession = Depends(get_db)
):
    """
    删除AI生成的图片记录（不删除已保存的照片）
    """
    from app.models.photo import AIGeneratedImage
    
    result = await db.execute(
        select(AIGeneratedImage).where(AIGeneratedImage.id == image_id)
    )
    generated_image = result.scalar_one_or_none()
    
    if not generated_image:
        raise HTTPException(status_code=404, detail="生成记录不存在")
    
    # 删除本地文件
    if generated_image.local_path and os.path.exists(generated_image.local_path):
        try:
            os.unlink(generated_image.local_path)
        except Exception as e:
            logger_service.warning(f"删除文件失败: {e}")
    
    # 删除数据库记录
    await db.delete(generated_image)
    await db.commit()
    
    logger_service.info(f"AI生成图片记录已删除: {image_id}")
    
    return {
        "message": "删除成功",
        "image_id": image_id
    }
