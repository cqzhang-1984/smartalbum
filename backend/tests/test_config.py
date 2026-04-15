"""
配置管理单元测试
"""
import pytest
import os
from app.config import Settings


class TestConfig:
    """测试配置管理"""
    
    def test_default_settings(self):
        """测试默认配置"""
        settings = Settings()
        
        # 验证基本配置
        assert settings.APP_NAME == "SmartAlbum"
        assert settings.APP_VERSION == "1.0.0"
        assert settings.DEBUG is True
    
    def test_security_config_validation(self):
        """测试安全配置验证"""
        # 测试生产环境需要 SECRET_KEY
        os.environ["ENVIRONMENT"] = "production"
        os.environ["SECRET_KEY"] = ""
        
        settings = Settings()
        
        # 应该抛出异常
        with pytest.raises(ValueError) as exc_info:
            settings.validate_security_config()
        
        assert "SECRET_KEY" in str(exc_info.value)
        
        # 清理环境变量
        os.environ["ENVIRONMENT"] = "development"
    
    def test_database_url(self):
        """测试数据库URL配置"""
        settings = Settings()
        
        assert "sqlite" in settings.DATABASE_URL
        assert "smartalbum.db" in settings.DATABASE_URL
    
    def test_storage_paths(self):
        """测试存储路径配置"""
        settings = Settings()
        
        assert settings.STORAGE_PATH == "./storage"
        assert settings.ORIGINALS_PATH == "./storage/originals"
        assert settings.THUMBNAILS_PATH == "./storage/thumbnails"
    
    def test_ai_api_key_methods(self):
        """测试AI API密钥获取方法"""
        settings = Settings()
        
        # 默认情况下应该返回 None
        assert settings.get_ai_api_key() is None
        assert settings.get_embedding_api_key() is None
    
    def test_allowed_extensions(self):
        """测试允许的文件扩展名"""
        settings = Settings()
        
        assert ".jpg" in settings.ALLOWED_EXTENSIONS
        assert ".jpeg" in settings.ALLOWED_EXTENSIONS
        assert ".png" in settings.ALLOWED_EXTENSIONS
        assert ".webp" in settings.ALLOWED_EXTENSIONS
        assert ".heic" in settings.ALLOWED_EXTENSIONS
        assert ".gif" not in settings.ALLOWED_EXTENSIONS
    
    def test_max_upload_size(self):
        """测试最大上传大小"""
        settings = Settings()
        
        # 50MB
        assert settings.MAX_UPLOAD_SIZE == 50 * 1024 * 1024
