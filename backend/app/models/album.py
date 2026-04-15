from sqlalchemy import Column, String, Integer, Boolean, DateTime, Text, JSON, ForeignKey, Table
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid
from app.database import Base


def generate_uuid():
    """生成UUID"""
    return str(uuid.uuid4())


# 照片-相册关联表
album_photos = Table(
    'album_photos',
    Base.metadata,
    Column('album_id', String(36), ForeignKey('albums.id'), primary_key=True),
    Column('photo_id', String(36), ForeignKey('photos.id'), primary_key=True),
    Column('added_at', DateTime, default=datetime.utcnow, nullable=False)
)


class Album(Base):
    """相册模型"""
    __tablename__ = "albums"
    
    id = Column(String(36), primary_key=True, default=generate_uuid)
    name = Column(String(100), nullable=False, index=True)
    description = Column(Text, nullable=True)
    cover_photo_id = Column(String(36), ForeignKey('photos.id'), nullable=True)
    
    # 智能相册标记
    is_smart = Column(Boolean, default=False, nullable=False)
    
    # 智能相册规则（JSON存储）
    # 格式：[{"field": "ai_tags.subject_emotion", "operator": "equals", "value": "慵懒"}]
    rules = Column(JSON, nullable=True)
    
    # 统计信息
    photo_count = Column(Integer, default=0, nullable=False)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # 关系
    photos = relationship("Photo", secondary=album_photos, backref="album_list")
    
    def __repr__(self):
        return f"<Album(id={self.id}, name={self.name})>"


class AlbumPhoto(Base):
    """相册-照片关联模型（用于跟踪添加时间等）"""
    __tablename__ = "album_photo_details"
    
    id = Column(String(36), primary_key=True, default=generate_uuid)
    album_id = Column(String(36), ForeignKey('albums.id'), nullable=False)
    photo_id = Column(String(36), ForeignKey('photos.id'), nullable=False)
    
    added_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    
    # 关系
    album = relationship("Album", backref="photo_details")
    photo = relationship("Photo", back_populates="albums")
    
    def __repr__(self):
        return f"<AlbumPhoto(album_id={self.album_id}, photo_id={self.photo_id})>"
