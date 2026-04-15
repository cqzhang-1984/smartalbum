"""
文件处理工具函数
"""
import os
import hashlib
import shutil
from pathlib import Path
from typing import Optional, Tuple
from fastapi import UploadFile, HTTPException
from app.config import settings


def _get_image_type(header: bytes) -> Optional[str]:
    """
    检测图片类型（替代 Python 3.14 移除的 imghdr）
    
    Args:
        header: 文件头字节（至少前 32 字节）
        
    Returns:
        图片类型或 None
    """
    if len(header) < 8:
        return None
    
    # JPEG
    if header[:3] == b'\xff\xd8\xff':
        return 'jpeg'
    
    # PNG
    if header[:8] == b'\x89PNG\r\n\x1a\n':
        return 'png'
    
    # GIF
    if header[:6] in (b'GIF87a', b'GIF89a'):
        return 'gif'
    
    # WebP (RIFF....WEBP)
    if header[:4] == b'RIFF' and header[8:12] == b'WEBP':
        return 'webp'
    
    # HEIC/HEIF (ftyp 标识)
    if b'ftyp' in header[4:20]:
        if b'heic' in header[:20] or b'heix' in header[:20]:
            return 'heic'
        if b'mif1' in header[:20]:
            return 'heif'
    
    # BMP
    if header[:2] == b'BM':
        return 'bmp'
    
    # TIFF
    if header[:4] in (b'II\x2a\x00', b'MM\x00\x2a'):
        return 'tiff'
    
    return None


def calculate_file_hash(file_path: str) -> str:
    """计算文件MD5哈希值"""
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


async def save_upload_file(upload_file: UploadFile, destination: str) -> str:
    """保存上传的文件"""
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    
    with open(destination, "wb") as buffer:
        shutil.copyfileobj(upload_file.file, buffer)
    
    return destination


async def validate_upload_file(upload_file: UploadFile) -> Tuple[bool, str]:
    """
    验证上传文件的完整性和安全性
    
    Args:
        upload_file: 上传的文件对象
        
    Returns:
        (是否有效, 错误信息)
    """
    # 1. 检查文件名
    if not upload_file.filename:
        return False, "文件名不能为空"
    
    # 2. 检查文件扩展名
    ext = get_file_extension(upload_file.filename)
    if ext not in settings.ALLOWED_EXTENSIONS:
        return False, f"不支持的文件类型: {ext}，允许的类型: {', '.join(settings.ALLOWED_EXTENSIONS)}"
    
    # 3. 检查文件大小（在读取前）
    # 读取文件内容到内存进行验证
    content = await upload_file.read()
    file_size = len(content)
    
    if file_size == 0:
        return False, "文件不能为空"
    
    if file_size > settings.MAX_UPLOAD_SIZE:
        max_size_mb = settings.MAX_UPLOAD_SIZE / (1024 * 1024)
        return False, f"文件大小超过限制: {file_size / (1024 * 1024):.1f}MB > {max_size_mb}MB"
    
    # 4. 验证文件内容类型（防止伪装扩展名）
    # 使用自定义函数检测真实图片类型
    image_type = _get_image_type(content[:32])
    
    # 映射检测到的类型到扩展名
    type_to_ext = {
        'jpeg': ['.jpg', '.jpeg'],
        'png': ['.png'],
        'gif': ['.gif'],
        'webp': ['.webp'],
        'heic': ['.heic'],
        'heif': ['.heic'],
    }
    
    if image_type:
        valid_exts = type_to_ext.get(image_type, [])
        if ext not in valid_exts:
            return False, f"文件内容类型 ({image_type}) 与扩展名 ({ext}) 不匹配"
    
    # 5. 检查文件头签名（额外的安全检查）
    # 常见的图片文件头
    signatures = {
        b'\xff\xd8\xff': ['.jpg', '.jpeg'],  # JPEG
        b'\x89PNG\r\n\x1a\n': ['.png'],       # PNG
        b'RIFF': ['.webp'],                   # WebP (RIFF开头)
    }
    
    is_valid_signature = False
    for sig, valid_exts in signatures.items():
        if content.startswith(sig):
            if ext in valid_exts:
                is_valid_signature = True
                break
    
    # 对于 HEIC 文件，imghdr 可能无法检测，需要特殊处理
    if ext == '.heic':
        # HEIC 文件以 ftypheic 或类似标识开头
        if b'ftyp' in content[:20]:
            is_valid_signature = True
    elif not is_valid_signature and image_type is None:
        # 无法识别的文件类型
        return False, "无法识别的文件格式，可能不是有效的图片文件"
    
    # 将文件指针重置到开头，以便后续读取
    await upload_file.seek(0)
    
    return True, ""


def get_file_extension(filename: str) -> str:
    """获取文件扩展名"""
    return os.path.splitext(filename)[1].lower()


def is_allowed_file(filename: str) -> bool:
    """检查文件扩展名是否允许"""
    ext = get_file_extension(filename)
    return ext in settings.ALLOWED_EXTENSIONS


def generate_unique_filename(original_filename: str, file_hash: str) -> str:
    """生成唯一文件名"""
    ext = get_file_extension(original_filename)
    return f"{file_hash}{ext}"


def get_photo_path(file_hash: str, filename: str) -> tuple[str, str]:
    """
    获取照片存储路径
    返回: (相对路径, 绝对路径)
    相对路径包含 originals/ 前缀，便于 COS 存储
    """
    ext = get_file_extension(filename)
    relative_path = f"originals/{file_hash}{ext}"
    absolute_path = os.path.join(settings.ORIGINALS_PATH, f"{file_hash}{ext}")
    return relative_path, absolute_path


def get_thumbnail_paths(file_hash: str) -> dict:
    """
    获取缩略图路径
    返回: {
        'small': (相对路径, 绝对路径),
        'medium': (相对路径, 绝对路径),
        'large': (相对路径, 绝对路径)
    }
    """
    return {
        'small': (
            f"thumbnails/small/{file_hash}.jpg",
            os.path.join(settings.THUMBNAIL_SMALL_PATH, f"{file_hash}.jpg")
        ),
        'medium': (
            f"thumbnails/medium/{file_hash}.jpg",
            os.path.join(settings.THUMBNAIL_MEDIUM_PATH, f"{file_hash}.jpg")
        ),
        'large': (
            f"thumbnails/large/{file_hash}.jpg",
            os.path.join(settings.THUMBNAIL_LARGE_PATH, f"{file_hash}.jpg")
        )
    }


def format_file_size(size_bytes: int) -> str:
    """格式化文件大小"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} TB"


def ensure_storage_directories():
    """确保存储目录存在"""
    os.makedirs(settings.STORAGE_PATH, exist_ok=True)
    os.makedirs(settings.ORIGINALS_PATH, exist_ok=True)
    os.makedirs(settings.THUMBNAIL_SMALL_PATH, exist_ok=True)
    os.makedirs(settings.THUMBNAIL_MEDIUM_PATH, exist_ok=True)
    os.makedirs(settings.THUMBNAIL_LARGE_PATH, exist_ok=True)
