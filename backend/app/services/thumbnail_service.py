"""
缩略图生成服务
"""
import os
from PIL import Image
from typing import Tuple
from app.config import settings


class ThumbnailService:
    """缩略图服务类"""
    
    @staticmethod
    def generate_thumbnails(
        image_path: str,
        output_dir: str,
        file_hash: str
    ) -> dict:
        """
        生成多级缩略图
        返回: {
            'small': '路径',
            'medium': '路径',
            'large': '路径'
        }
        """
        try:
            # 打开原始图片
            with Image.open(image_path) as img:
                # 转换为RGB模式（如果需要）
                if img.mode in ('RGBA', 'LA', 'P'):
                    img = img.convert('RGB')
                
                thumbnails = {}
                
                # 生成小缩略图（150x150）
                small_path = os.path.join(output_dir, 'small', f"{file_hash}.jpg")
                ThumbnailService._create_thumbnail(
                    img, 
                    small_path, 
                    settings.THUMBNAIL_SMALL_SIZE
                )
                thumbnails['small'] = f"thumbnails/small/{file_hash}.jpg"
                
                # 生成中等缩略图（400x400）
                medium_path = os.path.join(output_dir, 'medium', f"{file_hash}.jpg")
                ThumbnailService._create_thumbnail(
                    img, 
                    medium_path, 
                    settings.THUMBNAIL_MEDIUM_SIZE
                )
                thumbnails['medium'] = f"thumbnails/medium/{file_hash}.jpg"
                
                # 生成大缩略图（1920x1080）
                large_path = os.path.join(output_dir, 'large', f"{file_hash}.jpg")
                ThumbnailService._create_thumbnail(
                    img, 
                    large_path, 
                    settings.THUMBNAIL_LARGE_SIZE
                )
                thumbnails['large'] = f"thumbnails/large/{file_hash}.jpg"
                
                return thumbnails
                
        except Exception as e:
            print(f"生成缩略图失败: {e}")
            return {}
    
    @staticmethod
    def _create_thumbnail(
        img: Image.Image,
        output_path: str,
        size: Tuple[int, int]
    ):
        """创建单个缩略图"""
        # 确保输出目录存在
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        # 创建副本
        thumbnail = img.copy()
        
        # 调整大小（保持宽高比）
        thumbnail.thumbnail(size, Image.Resampling.LANCZOS)
        
        # 保存
        thumbnail.save(
            output_path,
            'JPEG',
            quality=85,
            optimize=True
        )
    
    @staticmethod
    def get_image_dimensions(image_path: str) -> Tuple[int, int]:
        """获取图片尺寸"""
        try:
            with Image.open(image_path) as img:
                return img.size
        except Exception as e:
            print(f"获取图片尺寸失败: {e}")
            return (0, 0)
    
    @staticmethod
    def create_square_thumbnail(
        image_path: str,
        output_path: str,
        size: int = 200
    ):
        """创建正方形缩略图（居中裁剪）"""
        try:
            with Image.open(image_path) as img:
                # 转换为RGB模式
                if img.mode in ('RGBA', 'LA', 'P'):
                    img = img.convert('RGB')
                
                # 计算裁剪区域
                width, height = img.size
                min_dim = min(width, height)
                left = (width - min_dim) / 2
                top = (height - min_dim) / 2
                right = (width + min_dim) / 2
                bottom = (height + min_dim) / 2
                
                # 裁剪为正方形
                img_cropped = img.crop((left, top, right, bottom))
                
                # 调整大小
                img_resized = img_cropped.resize((size, size), Image.Resampling.LANCZOS)
                
                # 保存
                os.makedirs(os.path.dirname(output_path), exist_ok=True)
                img_resized.save(output_path, 'JPEG', quality=85)
                
        except Exception as e:
            print(f"创建正方形缩略图失败: {e}")
