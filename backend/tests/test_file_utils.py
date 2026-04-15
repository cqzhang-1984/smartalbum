"""
文件工具函数单元测试
"""
import pytest
import os
import tempfile
from app.utils.file_utils import (
    calculate_file_hash,
    get_file_extension,
    is_allowed_file,
    format_file_size,
    get_photo_path,
    get_thumbnail_paths
)


class TestFileUtils:
    """测试文件工具函数"""
    
    def test_calculate_file_hash(self):
        """测试文件哈希计算"""
        # 创建临时文件
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write("test content")
            temp_path = f.name
        
        try:
            # 计算哈希
            file_hash = calculate_file_hash(temp_path)
            
            # 验证哈希是32位MD5
            assert len(file_hash) == 32
            assert all(c in '0123456789abcdef' for c in file_hash)
            
            # 相同内容应产生相同哈希
            file_hash2 = calculate_file_hash(temp_path)
            assert file_hash == file_hash2
        finally:
            os.unlink(temp_path)
    
    def test_get_file_extension(self):
        """测试获取文件扩展名"""
        assert get_file_extension("photo.jpg") == ".jpg"
        assert get_file_extension("photo.JPG") == ".jpg"
        assert get_file_extension("photo.Jpeg") == ".jpeg"
        assert get_file_extension("photo") == ""
        assert get_file_extension("path/to/photo.png") == ".png"
    
    def test_is_allowed_file(self):
        """测试文件类型检查"""
        assert is_allowed_file("photo.jpg") is True
        assert is_allowed_file("photo.jpeg") is True
        assert is_allowed_file("photo.png") is True
        assert is_allowed_file("photo.webp") is True
        assert is_allowed_file("photo.heic") is True
        assert is_allowed_file("photo.gif") is False
        assert is_allowed_file("photo.txt") is False
        assert is_allowed_file("photo.exe") is False
    
    def test_format_file_size(self):
        """测试文件大小格式化"""
        assert format_file_size(100) == "100.0 B"
        assert format_file_size(1024) == "1.0 KB"
        assert format_file_size(1024 * 1024) == "1.0 MB"
        assert format_file_size(1024 * 1024 * 1024) == "1.0 GB"
    
    def test_get_photo_path(self):
        """测试照片路径生成"""
        relative, absolute = get_photo_path("abc123", "photo.jpg")
        
        assert relative.startswith("originals/")
        assert relative.endswith(".jpg")
        assert "abc123" in relative
        assert os.path.isabs(absolute)
    
    def test_get_thumbnail_paths(self):
        """测试缩略图路径生成"""
        paths = get_thumbnail_paths("abc123")
        
        assert "small" in paths
        assert "medium" in paths
        assert "large" in paths
        
        for size, (relative, absolute) in paths.items():
            assert relative.startswith(f"thumbnails/{size}/")
            assert relative.endswith(".jpg")
            assert "abc123" in relative
            assert os.path.isabs(absolute)
