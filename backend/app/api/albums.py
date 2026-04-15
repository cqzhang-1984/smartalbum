from fastapi import APIRouter, Depends, HTTPException, Query, Body
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from app.database import get_db
from app.schemas.photo import PhotoListResponse, PhotoResponse
from app.services.album_service import AlbumService

router = APIRouter()


@router.get("/")
async def get_albums(db: AsyncSession = Depends(get_db)):
    """获取相册列表"""
    albums = await AlbumService.get_albums(db)
    
    return [
        {
            "id": album.id,
            "name": album.name,
            "description": album.description,
            "cover_photo_id": album.cover_photo_id,
            "is_smart": album.is_smart,
            "photo_count": album.photo_count,
            "created_at": album.created_at.isoformat() if album.created_at else None,
            "updated_at": album.updated_at.isoformat() if album.updated_at else None
        }
        for album in albums
    ]


@router.post("/")
async def create_album(
    name: str = Query(..., min_length=1, max_length=100),
    description: Optional[str] = Query(None),
    is_smart: bool = Query(False),
    rules: Optional[str] = Query(None, description="JSON格式的规则数组"),
    db: AsyncSession = Depends(get_db)
):
    """创建相册"""
    import json
    
    parsed_rules = None
    if rules:
        try:
            parsed_rules = json.loads(rules)
        except json.JSONDecodeError:
            raise HTTPException(status_code=400, detail="rules格式错误，必须是有效的JSON")
    
    album = await AlbumService.create_album(
        db,
        name=name,
        description=description,
        is_smart=is_smart,
        rules=parsed_rules
    )
    
    return {
        "message": "相册创建成功",
        "album_id": album.id,
        "photo_count": album.photo_count if album.is_smart else 0
    }


@router.get("/{album_id}")
async def get_album(
    album_id: str,
    db: AsyncSession = Depends(get_db)
):
    """获取相册详情"""
    album = await AlbumService.get_album_by_id(db, album_id)
    if not album:
        raise HTTPException(status_code=404, detail="Album not found")
    
    return {
        "id": album.id,
        "name": album.name,
        "description": album.description,
        "cover_photo_id": album.cover_photo_id,
        "is_smart": album.is_smart,
        "rules": album.rules,
        "photo_count": album.photo_count,
        "created_at": album.created_at.isoformat() if album.created_at else None,
        "updated_at": album.updated_at.isoformat() if album.updated_at else None
    }


@router.get("/{album_id}/photos", response_model=PhotoListResponse)
async def get_album_photos(
    album_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db)
):
    """获取相册中的照片"""
    photos, total = await AlbumService.get_album_photos(db, album_id, page, page_size)
    
    return {
        "photos": [PhotoResponse.model_validate(photo) for photo in photos],
        "total": total,
        "page": page,
        "page_size": page_size
    }


@router.put("/{album_id}")
async def update_album(
    album_id: str,
    name: Optional[str] = Query(None, min_length=1, max_length=100),
    description: Optional[str] = Query(None),
    rules: Optional[str] = Query(None, description="JSON格式的规则数组"),
    db: AsyncSession = Depends(get_db)
):
    """更新相册"""
    import json

    parsed_rules = None
    if rules:
        try:
            parsed_rules = json.loads(rules)
        except json.JSONDecodeError:
            raise HTTPException(status_code=400, detail="rules格式错误，必须是有效的JSON")

    album = await AlbumService.update_album(
        db,
        album_id,
        name=name,
        description=description,
        rules=parsed_rules
    )

    if not album:
        raise HTTPException(status_code=404, detail="Album not found")

    return {
        "message": "相册更新成功",
        "album_id": album.id
    }


@router.delete("/{album_id}")
async def delete_album(
    album_id: str,
    db: AsyncSession = Depends(get_db)
):
    """删除相册"""
    try:
        success = await AlbumService.delete_album(db, album_id)
        if not success:
            raise HTTPException(status_code=404, detail="Album not found")
        
        return {"message": "相册删除成功"}
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"删除失败: {str(e)}")


@router.post("/{album_id}/photos/{photo_id}")
async def add_photo_to_album(
    album_id: str,
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """将照片添加到相册"""
    success = await AlbumService.add_photo_to_album(db, album_id, photo_id)
    if not success:
        raise HTTPException(status_code=400, detail="添加失败")
    
    return {"message": "照片已添加到相册"}


@router.delete("/{album_id}/photos/{photo_id}")
async def remove_photo_from_album(
    album_id: str,
    photo_id: str,
    db: AsyncSession = Depends(get_db)
):
    """从相册中移除照片"""
    success = await AlbumService.remove_photo_from_album(db, album_id, photo_id)
    if not success:
        raise HTTPException(status_code=404, detail="Photo not found in album")
    
    return {"message": "照片已从相册中移除"}


@router.post("/{album_id}/refresh")
async def refresh_smart_album(
    album_id: str,
    db: AsyncSession = Depends(get_db)
):
    """刷新智能相册（重新应用规则）"""
    album = await AlbumService.get_album_by_id(db, album_id)
    if not album:
        raise HTTPException(status_code=404, detail="Album not found")
    
    if not album.is_smart:
        raise HTTPException(status_code=400, detail="Not a smart album")
    
    matched_count = await AlbumService.apply_smart_album_rules(db, album_id)
    
    return {
        "message": "智能相册已刷新",
        "matched_photos": matched_count
    }
