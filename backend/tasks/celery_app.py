"""
Celery应用配置
"""
from celery import Celery
from app.config import settings

# 创建Celery应用
celery_app = Celery(
    'smartalbum',
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=[
        'tasks.photo_tasks',
        'tasks.ai_tasks'
    ]
)

# Celery配置
celery_app.conf.update(
    # 任务结果过期时间（秒）
    result_expires=3600,
    
    # 任务序列化格式
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    
    # 时区
    timezone='Asia/Shanghai',
    enable_utc=True,
    
    # 任务路由
    task_routes={
        'tasks.photo_tasks.*': {'queue': 'photo'},
        'tasks.ai_tasks.*': {'queue': 'ai'},
    },
    
    # 任务默认配置
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    
    # Worker配置
    worker_prefetch_multiplier=1,
    worker_max_tasks_per_child=1000,
)

if __name__ == '__main__':
    celery_app.start()
