from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, Text, JSON, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid
from app.database import Base


def generate_uuid():
    """生成UUID"""
    return str(uuid.uuid4())


class Photo(Base):
    """照片模型"""
    __tablename__ = "photos"
    
    id = Column(String(36), primary_key=True, default=generate_uuid)
    filename = Column(String(255), nullable=False)
    original_path = Column(String(500), nullable=False)
    file_size = Column(Integer, nullable=False)
    file_hash = Column(String(64), unique=True, nullable=False, index=True)
    
    # 缩略图路径
    thumbnail_small = Column(String(500), nullable=True)
    thumbnail_medium = Column(String(500), nullable=True)
    thumbnail_large = Column(String(500), nullable=True)
    
    # EXIF信息
    shot_time = Column(DateTime, nullable=True, index=True)
    camera_model = Column(String(100), nullable=True, index=True)
    lens_model = Column(String(100), nullable=True)
    focal_length = Column(Float, nullable=True)
    aperture = Column(Float, nullable=True)
    shutter_speed = Column(String(20), nullable=True)
    iso = Column(Integer, nullable=True)
    
    # AI标签（JSON存储）
    ai_tags = Column(JSON, nullable=True)
    
    # 用户数据
    rating = Column(Integer, default=0, nullable=False)
    is_favorite = Column(Boolean, default=False, nullable=False)
    
    # 人脸聚类
    face_cluster_id = Column(String(36), ForeignKey('face_clusters.id'), nullable=True)
    
    # 时间戳
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # 关系
    face_cluster = relationship("FaceCluster", back_populates="photos")
    albums = relationship("AlbumPhoto", back_populates="photo")
    
    def __repr__(self):
        return f"<Photo(id={self.id}, filename={self.filename})>"


class AITag(Base):
    """AI标签模型（用于统计分析）"""
    __tablename__ = "ai_tags"
    
    id = Column(String(36), primary_key=True, default=generate_uuid)
    photo_id = Column(String(36), ForeignKey('photos.id'), nullable=False)
    
    # 结构化标签
    subject_emotion = Column(String(50), nullable=True, index=True)
    pose = Column(String(50), nullable=True, index=True)
    clothing_style = Column(String(50), nullable=True, index=True)
    lighting = Column(String(50), nullable=True, index=True)
    environment = Column(String(50), nullable=True, index=True)
    
    # 完整描述
    overall_description = Column(Text, nullable=True)
    
    # 美学评分
    aesthetic_score = Column(Float, nullable=True)
    
    # 向量ID（ChromaDB）
    vector_id = Column(String(100), nullable=True, unique=True)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    
    def __repr__(self):
        return f"<AITag(id={self.id}, photo_id={self.photo_id})>"


class FaceCluster(Base):
    """人脸聚类模型"""
    __tablename__ = "face_clusters"
    
    id = Column(String(36), primary_key=True, default=generate_uuid)
    name = Column(String(100), nullable=True)
    cover_photo_id = Column(String(36), nullable=True)
    
    # 人脸特征（存储平均特征向量）
    face_encoding = Column(JSON, nullable=True)
    
    # 统计信息
    photo_count = Column(Integer, default=0, nullable=False)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # 关系
    photos = relationship("Photo", back_populates="face_cluster")
    
    def __repr__(self):
        return f"<FaceCluster(id={self.id}, name={self.name})>"


class AIGeneratedImage(Base):
    """AI生成图片模型"""
    __tablename__ = "ai_generated_images"
    
    id = Column(String(36), primary_key=True, default=generate_uuid)
    
    # 生成信息
    prompt = Column(Text, nullable=False)  # 原始提示词
    negative_prompt = Column(Text, nullable=True)  # 负向提示词
    model_id = Column(String(100), nullable=False)  # 使用的模型ID
    model_name = Column(String(100), nullable=True)  # 模型显示名称
    
    # 图片尺寸
    width = Column(Integer, nullable=True)  # 图片宽度
    height = Column(Integer, nullable=True)  # 图片高度
    size_ratio = Column(String(10), nullable=True)  # 尺寸比例（如 "1:1", "16:9"）
    output_format = Column(String(10), default="png")  # 输出格式
    
    # 图片信息
    image_url = Column(String(1000), nullable=True)  # 原始URL（临时）
    local_path = Column(String(500), nullable=True)  # 本地存储路径
    file_size = Column(Integer, nullable=True)  # 文件大小
    
    # 来源照片（如果是基于照片生成）
    source_photo_id = Column(String(36), ForeignKey('photos.id'), nullable=True)
    
    # 用户数据
    title = Column(String(255), nullable=True)  # 用户标题
    is_saved = Column(Boolean, default=False, nullable=False)  # 是否已保存到相册
    saved_photo_id = Column(String(36), ForeignKey('photos.id'), nullable=True)  # 保存后的照片ID
    
    # 元数据
    generation_params = Column(JSON, nullable=True)  # 生成参数
    usage_info = Column(JSON, nullable=True)  # API用量信息
    
    # 时间戳
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    
    def __repr__(self):
        return f"<AIGeneratedImage(id={self.id}, prompt={self.prompt[:30]}...)>"
    
    @property
    def size_display(self) -> str:
        """返回尺寸显示字符串"""
        if self.width and self.height:
            return f"{self.width}x{self.height}"
        return self.size_ratio or "未知"
