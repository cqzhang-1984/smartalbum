"""
日志管理API
"""
from fastapi import APIRouter, Query, HTTPException
from typing import Optional
from app.services.logger_service import logger_service

router = APIRouter()


@router.get("/")
async def get_logs(
    level: Optional[str] = Query(None, description="日志级别: INFO, WARNING, ERROR, DEBUG"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0)
):
    """获取日志列表"""
    logs = logger_service.get_logs(level=level, limit=limit, offset=offset)
    return {
        "logs": logs,
        "total": len(logs),
        "level": level,
        "limit": limit,
        "offset": offset
    }


@router.get("/stats")
async def get_log_stats():
    """获取日志统计"""
    stats = logger_service.get_log_stats()
    return stats


@router.delete("/clear")
async def clear_logs(
    before_days: int = Query(7, ge=1, le=365, description="删除多少天前的日志")
):
    """清理旧日志"""
    removed = logger_service.clear_logs(before_days=before_days)
    return {
        "message": f"已清理 {removed} 条日志",
        "removed": removed
    }
