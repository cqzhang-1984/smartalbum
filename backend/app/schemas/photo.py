from pydantic import BaseModel
from typing import Optional, Dict
from datetime import datetime


class AITags(BaseModel):
    """AI标签模型"""
    subject_emotion: Optional[str] = None
    pose: Optional[str] = None
    clothing_style: Optional[str] = None
    lighting: Optional[str] = None
    environment: Optional[str] = None
    overall_description: Optional[str] = None
    aesthetic_score: Optional[float] = None
    deep_analysis: Optional[str] = None
    deep_analysis_time: Optional[str] = None


class PhotoBase(BaseModel):
    """照片基础模型"""
    filename: str
    file_size: int
    shot_time: Optional[datetime] = None
    camera_model: Optional[str] = None
    lens_model: Optional[str] = None
    focal_length: Optional[float] = None
    aperture: Optional[float] = None
    shutter_speed: Optional[str] = None
    iso: Optional[int] = None


class PhotoCreate(PhotoBase):
    """照片创建模型"""
    original_path: str
    file_hash: str


class PhotoResponse(PhotoBase):
    """照片响应模型"""
    id: str
    original_path: Optional[str] = None
    thumbnail_small: Optional[str] = None
    thumbnail_medium: Optional[str] = None
    thumbnail_large: Optional[str] = None
    ai_tags: Optional[AITags] = None
    rating: int = 0
    is_favorite: bool = False
    face_cluster_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class PhotoListResponse(BaseModel):
    """照片列表响应模型"""
    photos: list[PhotoResponse]
    total: int
    page: int
    page_size: int


class PhotoUpdate(BaseModel):
    """照片更新模型"""
    rating: Optional[int] = None
    is_favorite: Optional[bool] = None
