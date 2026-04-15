"""
AI识别异步任务 - 最终版本（集成ChromaDB）
"""
from typing import Dict
from celery import shared_task
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.config import settings
from app.models.photo import Photo, FaceCluster
from app.services.ai_service import ai_service, embedding_service
from app.services.vector_service import vector_service
import os
import asyncio
import json

# 创建同步数据库引擎
engine = create_engine(
    settings.DATABASE_URL.replace('+aiosqlite', ''),
    echo=False
)
SessionLocal = sessionmaker(bind=engine)


@shared_task(name='tasks.ai_tasks.analyze_photo')
def analyze_photo(photo_id: str) -> Dict:
    """
    使用AI分析照片（异步任务）
    """
    db = SessionLocal()
    
    try:
        photo = db.query(Photo).filter(Photo.id == photo_id).first()
        if not photo:
            return {'status': 'error', 'message': 'Photo not found'}
        
        # 获取图片路径
        image_path = os.path.join(settings.ORIGINALS_PATH, photo.original_path)
        
        if not os.path.exists(image_path):
            return {'status': 'error', 'message': 'Image file not found'}
        
        # 调用AI服务进行分析
        ai_tags = asyncio.run(ai_service.analyze_image(image_path))
        
        # 更新AI标签
        photo.ai_tags = ai_tags
        db.commit()
        
        # 触发向量化任务
        if ai_tags.get('overall_description'):
            generate_embedding.delay(photo_id)
        
        return {
            'status': 'success',
            'photo_id': photo_id,
            'ai_tags': ai_tags
        }
        
    except Exception as e:
        db.rollback()
        print(f"AI分析失败: {e}")
        return {
            'status': 'error',
            'message': str(e)
        }
    finally:
        db.close()


@shared_task(name='tasks.ai_tasks.batch_analyze_photos')
def batch_analyze_photos(photo_ids: list) -> Dict:
    """
    批量分析照片
    """
    results = []
    for photo_id in photo_ids:
        result = analyze_photo(photo_id)
        results.append(result)
    
    return {
        'total': len(photo_ids),
        'processed': len(results),
        'results': results
    }


@shared_task(name='tasks.ai_tasks.generate_embedding')
def generate_embedding(photo_id: str) -> Dict:
    """
    生成照片描述的向量嵌入并存储到ChromaDB
    """
    db = SessionLocal()
    
    try:
        photo = db.query(Photo).filter(Photo.id == photo_id).first()
        if not photo or not photo.ai_tags or not photo.ai_tags.get('overall_description'):
            return {'status': 'error', 'message': 'Photo or description not found'}
        
        description = photo.ai_tags['overall_description']
        
        # 准备元数据
        metadata = {
            'filename': photo.filename,
            'camera_model': photo.camera_model or '',
            'subject_emotion': photo.ai_tags.get('subject_emotion', ''),
            'pose': photo.ai_tags.get('pose', ''),
            'clothing_style': photo.ai_tags.get('clothing_style', ''),
            'lighting': photo.ai_tags.get('lighting', ''),
            'environment': photo.ai_tags.get('environment', '')
        }
        
        # 添加向量到ChromaDB
        success = asyncio.run(vector_service.add_photo_embedding(
            photo_id,
            description,
            metadata
        ))
        
        if success:
            return {
                'status': 'success',
                'photo_id': photo_id,
                'description': description
            }
        else:
            return {
                'status': 'error',
                'message': 'Failed to add embedding to ChromaDB'
            }
        
    except Exception as e:
        print(f"生成向量失败: {e}")
        return {
            'status': 'error',
            'message': str(e)
        }
    finally:
        db.close()


@shared_task(name='tasks.ai_tasks.detect_faces')
def detect_faces(photo_id: str) -> Dict:
    """
    检测人脸并聚类
    """
    from app.services.face_service import face_service
    from app.models.photo import FaceCluster
    import numpy as np
    
    db = SessionLocal()
    
    try:
        photo = db.query(Photo).filter(Photo.id == photo_id).first()
        if not photo:
            return {'status': 'error', 'message': 'Photo not found'}
        
        # 获取图片路径
        image_path = os.path.join(settings.ORIGINALS_PATH, photo.original_path)
        
        if not os.path.exists(image_path):
            return {'status': 'error', 'message': 'Image file not found'}
        
        # 检测人脸
        face_result = face_service.detect_faces(image_path)
        
        if face_result.get('error'):
            return {
                'status': 'error',
                'message': face_result['error']
            }
        
        faces_detected = face_result['faces_detected']
        face_encodings = face_result['face_encodings']
        
        # 如果检测到人脸，尝试匹配已有聚类
        face_cluster_id = None
        if faces_detected > 0 and len(face_encodings) > 0:
            # 获取所有已有聚类
            existing_clusters = db.query(FaceCluster).all()
            
            # 准备已知聚类数据
            known_clusters = []
            for cluster in existing_clusters:
                if cluster.face_encoding:
                    encoding = face_service.list_to_encoding(cluster.face_encoding)
                    known_clusters.append({
                        'id': cluster.id,
                        'encoding': encoding
                    })
            
            # 使用第一个人脸进行匹配（假设每张照片主要是同一个人）
            primary_encoding = face_encodings[0]
            
            # 尝试匹配
            matched, cluster_id, distance = face_service.find_best_match(
                primary_encoding, 
                known_clusters
            )
            
            if matched and cluster_id:
                # 匹配成功，关联到现有聚类
                face_cluster_id = cluster_id
                cluster = db.query(FaceCluster).filter(FaceCluster.id == cluster_id).first()
                if cluster:
                    # 更新聚类的平均特征
                    existing_encoding = face_service.list_to_encoding(cluster.face_encoding)
                    new_avg_encoding = face_service.compute_average_encoding([
                        existing_encoding, primary_encoding
                    ])
                    cluster.face_encoding = face_service.encoding_to_list(new_avg_encoding)
                    cluster.photo_count += 1
            else:
                # 没有匹配，创建新聚类
                new_cluster = FaceCluster(
                    face_encoding=face_service.encoding_to_list(primary_encoding),
                    photo_count=1,
                    name=None  # 可以后续让用户命名
                )
                db.add(new_cluster)
                db.flush()  # 获取ID
                face_cluster_id = new_cluster.id
            
            # 更新照片的聚类ID
            photo.face_cluster_id = face_cluster_id
        
        db.commit()
        
        return {
            'status': 'success',
            'photo_id': photo_id,
            'faces_detected': faces_detected,
            'face_cluster_id': face_cluster_id
        }
        
    except Exception as e:
        db.rollback()
        print(f"人脸检测失败: {e}")
        import traceback
        traceback.print_exc()
        return {
            'status': 'error',
            'message': str(e)
        }
    finally:
        db.close()


@shared_task(name='tasks.ai_tasks.batch_detect_faces')
def batch_detect_faces(photo_ids: list) -> Dict:
    """
    批量检测人脸并聚类
    """
    results = []
    for photo_id in photo_ids:
        result = detect_faces(photo_id)
        results.append(result)
    
    return {
        'total': len(photo_ids),
        'processed': len(results),
        'results': results
    }


@shared_task(name='tasks.ai_tasks.recluster_all_faces')
def recluster_all_faces() -> Dict:
    """
    重新对所有照片进行人脸聚类（基于已有的人脸数据）
    这个任务会重新分析所有照片的人脸并重新聚类
    """
    from app.services.face_service import face_service
    from app.models.photo import FaceCluster
    import numpy as np
    
    db = SessionLocal()
    
    try:
        # 获取所有有AI标签的照片
        photos = db.query(Photo).filter(Photo.ai_tags.isnot(None)).all()
        
        # 收集所有照片的人脸数据
        all_face_data = []
        photos_with_faces = []
        
        for photo in photos:
            image_path = os.path.join(settings.ORIGINALS_PATH, photo.original_path)
            if os.path.exists(image_path):
                face_result = face_service.detect_faces(image_path)
                if face_result['faces_detected'] > 0:
                    all_face_data.append({
                        'photo_id': photo.id,
                        'encodings': face_result['face_encodings']
                    })
                    photos_with_faces.append(photo)
        
        if not all_face_data:
            return {
                'status': 'success',
                'message': '没有检测到人脸',
                'photos_processed': 0,
                'faces_detected': 0,
                'clusters_created': 0
            }
        
        # 执行聚类
        cluster_results = face_service.cluster_faces(all_face_data)
        
        # 清除旧的聚类数据
        db.query(FaceCluster).delete()
        
        # 创建新的聚类并更新照片关联
        clusters_created = 0
        for cluster_id, photo_ids in cluster_results.items():
            # 创建聚类记录
            # 收集该聚类所有照片的人脸编码
            cluster_encodings = []
            for face_data in all_face_data:
                if face_data['photo_id'] in photo_ids:
                    cluster_encodings.extend(face_data['encodings'])
            
            avg_encoding = face_service.compute_average_encoding(cluster_encodings)
            
            new_cluster = FaceCluster(
                face_encoding=face_service.encoding_to_list(avg_encoding),
                photo_count=len(photo_ids),
                name=None
            )
            db.add(new_cluster)
            db.flush()
            
            # 更新照片的聚类ID
            for photo_id in photo_ids:
                photo = db.query(Photo).filter(Photo.id == photo_id).first()
                if photo:
                    photo.face_cluster_id = new_cluster.id
            
            clusters_created += 1
        
        db.commit()
        
        return {
            'status': 'success',
            'photos_processed': len(photos_with_faces),
            'faces_detected': len(all_face_data),
            'clusters_created': clusters_created
        }
        
    except Exception as e:
        db.rollback()
        print(f"重新聚类失败: {e}")
        import traceback
        traceback.print_exc()
        return {
            'status': 'error',
            'message': str(e)
        }
    finally:
        db.close()


@shared_task(name='tasks.ai_tasks.deep_analyze_photo')
def deep_analyze_photo(photo_id: str) -> Dict:
    """
    AI深度分析照片（异步任务）
    生成专业级人像摄影深度分析报告并保存到数据库
    """
    from app.services.cos_service import cos_service

    db = SessionLocal()

    try:
        photo = db.query(Photo).filter(Photo.id == photo_id).first()
        if not photo:
            return {'status': 'error', 'message': 'Photo not found'}

        # 确定图片路径（支持COS和本地存储）
        image_path = None
        image_url = None

        if cos_service.is_enabled():
            key = photo.original_path.replace("/storage/", "")
            image_url = cos_service.get_url(key, expires=3600)
        else:
            image_path = os.path.join(settings.STORAGE_PATH, photo.original_path.replace("/storage/", ""))
            if not os.path.exists(image_path):
                return {'status': 'error', 'message': 'Image file not found'}

        # 调用AI服务进行深度分析
        result = asyncio.run(ai_service.deep_analyze_image(image_path, image_url=image_url))

        # 保存到数据库
        if result and result.get('deep_analysis'):
            existing_tags = photo.ai_tags or {}
            if isinstance(existing_tags, str):
                try:
                    existing_tags = json.loads(existing_tags)
                except Exception:
                    existing_tags = {}
            existing_tags['deep_analysis'] = result['deep_analysis']
            existing_tags['deep_analysis_time'] = result['deep_analysis_time']
            photo.ai_tags = existing_tags
            db.commit()

            return {
                'status': 'success',
                'photo_id': photo_id,
                'deep_analysis': result['deep_analysis'][:200] + '...',
                'deep_analysis_time': result['deep_analysis_time']
            }
        else:
            return {
                'status': 'error',
                'photo_id': photo_id,
                'message': 'Deep analysis returned empty result'
            }

    except Exception as e:
        db.rollback()
        import traceback
        traceback.print_exc()
        return {
            'status': 'error',
            'photo_id': photo_id,
            'message': str(e)
        }
    finally:
        db.close()
