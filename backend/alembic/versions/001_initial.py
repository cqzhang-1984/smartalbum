"""Initial database schema

Revision ID: 001
Revises: 
Create Date: 2026-03-04

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '001'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 创建照片表
    op.create_table(
        'photos',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('filename', sa.String(255), nullable=False),
        sa.Column('original_path', sa.String(500), nullable=False),
        sa.Column('file_size', sa.Integer, nullable=False),
        sa.Column('file_hash', sa.String(64), unique=True, nullable=False),
        sa.Column('thumbnail_small', sa.String(500), nullable=True),
        sa.Column('thumbnail_medium', sa.String(500), nullable=True),
        sa.Column('thumbnail_large', sa.String(500), nullable=True),
        sa.Column('shot_time', sa.DateTime, nullable=True),
        sa.Column('camera_model', sa.String(100), nullable=True),
        sa.Column('lens_model', sa.String(100), nullable=True),
        sa.Column('focal_length', sa.Float, nullable=True),
        sa.Column('aperture', sa.Float, nullable=True),
        sa.Column('shutter_speed', sa.String(20), nullable=True),
        sa.Column('iso', sa.Integer, nullable=True),
        sa.Column('ai_tags', sa.JSON, nullable=True),
        sa.Column('rating', sa.Integer, default=0, nullable=False),
        sa.Column('is_favorite', sa.Boolean, default=False, nullable=False),
        sa.Column('face_cluster_id', sa.String(36), sa.ForeignKey('face_clusters.id'), nullable=True),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('updated_at', sa.DateTime, nullable=False),
    )
    
    # 创建索引
    op.create_index('idx_photos_file_hash', 'photos', ['file_hash'])
    op.create_index('idx_photos_shot_time', 'photos', ['shot_time'])
    op.create_index('idx_photos_camera_model', 'photos', ['camera_model'])
    
    # 创建人脸聚类表
    op.create_table(
        'face_clusters',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('name', sa.String(100), nullable=True),
        sa.Column('cover_photo_id', sa.String(36), nullable=True),
        sa.Column('face_encoding', sa.JSON, nullable=True),
        sa.Column('photo_count', sa.Integer, default=0, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('updated_at', sa.DateTime, nullable=False),
    )
    
    # 创建AI标签表
    op.create_table(
        'ai_tags',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('photo_id', sa.String(36), sa.ForeignKey('photos.id'), nullable=False),
        sa.Column('subject_emotion', sa.String(50), nullable=True),
        sa.Column('pose', sa.String(50), nullable=True),
        sa.Column('clothing_style', sa.String(50), nullable=True),
        sa.Column('lighting', sa.String(50), nullable=True),
        sa.Column('environment', sa.String(50), nullable=True),
        sa.Column('overall_description', sa.Text, nullable=True),
        sa.Column('aesthetic_score', sa.Float, nullable=True),
        sa.Column('vector_id', sa.String(100), unique=True, nullable=True),
        sa.Column('created_at', sa.DateTime, nullable=False),
    )
    
    # 创建AI标签索引
    op.create_index('idx_ai_tags_emotion', 'ai_tags', ['subject_emotion'])
    op.create_index('idx_ai_tags_pose', 'ai_tags', ['pose'])
    op.create_index('idx_ai_tags_style', 'ai_tags', ['clothing_style'])
    op.create_index('idx_ai_tags_lighting', 'ai_tags', ['lighting'])
    op.create_index('idx_ai_tags_environment', 'ai_tags', ['environment'])
    
    # 创建相册表
    op.create_table(
        'albums',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('name', sa.String(100), nullable=False),
        sa.Column('description', sa.Text, nullable=True),
        sa.Column('cover_photo_id', sa.String(36), sa.ForeignKey('photos.id'), nullable=True),
        sa.Column('is_smart', sa.Boolean, default=False, nullable=False),
        sa.Column('rules', sa.JSON, nullable=True),
        sa.Column('photo_count', sa.Integer, default=0, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('updated_at', sa.DateTime, nullable=False),
    )
    
    # 创建相册索引
    op.create_index('idx_albums_name', 'albums', ['name'])
    
    # 创建照片-相册关联表
    op.create_table(
        'album_photos',
        sa.Column('album_id', sa.String(36), sa.ForeignKey('albums.id'), primary_key=True),
        sa.Column('photo_id', sa.String(36), sa.ForeignKey('photos.id'), primary_key=True),
        sa.Column('added_at', sa.DateTime, nullable=False),
    )
    
    # 创建相册照片详情表
    op.create_table(
        'album_photo_details',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('album_id', sa.String(36), sa.ForeignKey('albums.id'), nullable=False),
        sa.Column('photo_id', sa.String(36), sa.ForeignKey('photos.id'), nullable=False),
        sa.Column('added_at', sa.DateTime, nullable=False),
    )


def downgrade() -> None:
    op.drop_table('album_photo_details')
    op.drop_table('album_photos')
    op.drop_table('albums')
    op.drop_table('ai_tags')
    op.drop_table('photos')
    op.drop_table('face_clusters')
