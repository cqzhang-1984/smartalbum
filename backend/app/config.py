"""
SmartAlbum 应用配置模块
支持多环境配置和运行时验证
"""
from pydantic_settings import BaseSettings
from pydantic import Field, field_validator, ValidationInfo
from typing import Optional, List, Set, Tuple, Dict, Any
from pathlib import Path
import os
import secrets
import logging

logger = logging.getLogger(__name__)

# 读取环境变量
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development").lower()
IS_PRODUCTION: bool = ENVIRONMENT == "production"
IS_DEVELOPMENT: bool = ENVIRONMENT == "development"


class Settings(BaseSettings):
    """
    SmartAlbum 应用配置类
    
    配置优先级（从高到低）：
    1. 环境变量
    2. .env 文件
    3. 默认值
    """
    
    # ==========================================
    # 基础应用配置
    # ==========================================
    APP_NAME: str = Field(default="SmartAlbum", description="应用名称")
    APP_VERSION: str = Field(default="1.0.0", description="应用版本号")
    DEBUG: bool = Field(default=not IS_PRODUCTION, description="调试模式")
    
    # 运行环境
    ENVIRONMENT: str = Field(default=ENVIRONMENT, description="运行环境")
    IS_PRODUCTION: bool = Field(default=IS_PRODUCTION, description="是否为生产环境")
    IS_DEVELOPMENT: bool = Field(default=IS_DEVELOPMENT, description="是否为开发环境")
    
    # ==========================================
    # 安全配置
    # ==========================================
    SECRET_KEY: str = Field(
        default="dev-secret-key-change-in-production-min-32-chars-long",
        description="JWT密钥，生产环境必须设置（至少32位）"
    )
    
    @field_validator('SECRET_KEY')
    @classmethod
    def validate_secret_key(cls, v: str, info: ValidationInfo) -> str:
        """验证SECRET_KEY长度"""
        # 获取环境信息
        is_prod = False
        if info.data and 'IS_PRODUCTION' in info.data:
            is_prod = info.data['IS_PRODUCTION']
        
        if is_prod and len(v) < 32:
            raise ValueError('生产环境 SECRET_KEY 必须至少32个字符')
        return v
    
    # 默认用户配置
    DEFAULT_USERNAME: str = Field(default="admin", description="默认管理员用户名")
    DEFAULT_PASSWORD: str = Field(default="", description="默认管理员密码（生产环境必须设置）")
    
    # CORS配置
    CORS_ORIGINS: str = Field(
        default="http://localhost:8888,http://localhost:3000",
        description="允许的CORS来源，逗号分隔"
    )
    
    @field_validator('CORS_ORIGINS')
    @classmethod
    def parse_cors_origins(cls, v: str) -> List[str]:
        """解析CORS来源列表"""
        if not v:
            return ["*"] if not IS_PRODUCTION else []
        return [origin.strip() for origin in v.split(',') if origin.strip()]
    
    # ==========================================
    # 数据库配置
    # ==========================================
    DATABASE_URL: str = Field(
        default="sqlite+aiosqlite:///./data/smartalbum.db",
        description="数据库连接URL"
    )
    
    DATABASE_POOL_SIZE: int = Field(default=5, ge=1, le=50, description="数据库连接池大小")
    DATABASE_MAX_OVERFLOW: int = Field(default=10, ge=0, le=100, description="数据库连接池溢出限制")
    
    @field_validator('DATABASE_URL')
    @classmethod
    def validate_database_url(cls, v: str) -> str:
        """验证数据库URL格式"""
        if not v:
            raise ValueError("DATABASE_URL 不能为空")
        
        # 确保 SQLite 路径存在
        if 'sqlite' in v.lower():
            # 提取路径部分
            path_part = v.replace('sqlite+aiosqlite:///', '').replace('sqlite:///', '')
            if path_part and not path_part.startswith(':'):
                db_path = Path(path_part)
                db_dir = db_path.parent
                if not db_dir.exists():
                    logger.info(f"创建数据库目录: {db_dir}")
                    db_dir.mkdir(parents=True, exist_ok=True)
        
        return v
    
    # ==========================================
    # Redis配置
    # ==========================================
    REDIS_HOST: str = Field(default="localhost", description="Redis主机地址")
    REDIS_PORT: int = Field(default=6379, ge=1, le=65535, description="Redis端口")
    REDIS_DB: int = Field(default=1 if IS_PRODUCTION else 11, ge=0, le=15, description="Redis数据库编号")
    REDIS_PASSWORD: Optional[str] = Field(default=None, description="Redis密码")
    
    @property
    def REDIS_URL(self) -> str:
        """构建Redis连接URL"""
        auth = f":{self.REDIS_PASSWORD}@" if self.REDIS_PASSWORD else ""
        return f"redis://{auth}{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"
    
    # ==========================================
    # 存储路径配置
    # ==========================================
    STORAGE_PATH: str = Field(default="./storage", description="存储根目录")
    ORIGINALS_PATH: str = Field(default="./storage/originals", description="原始图片存储路径")
    THUMBNAILS_PATH: str = Field(default="./storage/thumbnails", description="缩略图存储路径")
    AI_GENERATED_PATH: str = Field(default="./storage/ai_generated", description="AI生成图片存储路径")
    
    # 缩略图子目录
    THUMBNAIL_SMALL_PATH: str = Field(default="./storage/thumbnails/small", description="小缩略图路径")
    THUMBNAIL_MEDIUM_PATH: str = Field(default="./storage/thumbnails/medium", description="中缩略图路径")
    THUMBNAIL_LARGE_PATH: str = Field(default="./storage/thumbnails/large", description="大缩略图路径")
    
    # 数据库文件路径
    DATABASE_PATH: str = Field(default="./data/smartalbum.db", description="数据库文件路径")
    CHROMA_PATH: str = Field(default="./data/chroma", description="ChromaDB存储路径")
    
    @field_validator('STORAGE_PATH', 'ORIGINALS_PATH', 'THUMBNAILS_PATH', 'AI_GENERATED_PATH')
    @classmethod
    def ensure_path_exists(cls, v: str) -> str:
        """确保存储路径存在"""
        if v:
            Path(v).mkdir(parents=True, exist_ok=True)
        return v
    
    # ==========================================
    # 缩略图配置
    # ==========================================
    THUMBNAIL_SMALL_SIZE: Tuple[int, int] = Field(
        default=(150, 150),
        description="小缩略图尺寸"
    )
    THUMBNAIL_MEDIUM_SIZE: Tuple[int, int] = Field(
        default=(400, 400),
        description="中缩略图尺寸"
    )
    THUMBNAIL_LARGE_SIZE: Tuple[int, int] = Field(
        default=(1920, 1080),
        description="大缩略图尺寸"
    )
    THUMBNAIL_QUALITY: int = Field(
        default=85,
        ge=1,
        le=100,
        description="缩略图质量（1-100）"
    )
    THUMBNAIL_FORMAT: str = Field(
        default="JPEG",
        pattern=r"^(JPEG|PNG|WEBP)$",
        description="缩略图格式"
    )
    
    # ==========================================
    # AI模型配置
    # ==========================================
    AI_MODEL_NAME: str = Field(default="GPT-4o", description="AI模型显示名称")
    AI_MODEL_ID: str = Field(default="gpt-4o", description="AI模型ID（API调用使用）")
    AI_API_KEY: Optional[str] = Field(default=None, description="AI API密钥")
    AI_API_BASE: str = Field(default="https://api.openai.com/v1", description="AI API基础URL")
    AI_API_PATH: str = Field(default="/chat/completions", description="AI API路径")
    AI_TIMEOUT: int = Field(default=120, ge=10, le=600, description="AI请求超时（秒）")
    AI_MAX_RETRIES: int = Field(default=3, ge=0, le=10, description="AI请求最大重试次数")
    
    # ==========================================
    # Embedding模型配置
    # ==========================================
    EMBEDDING_MODEL_NAME: str = Field(default="text-embedding-3-small", description="Embedding模型名称")
    EMBEDDING_MODEL_ID: str = Field(default="text-embedding-3-small", description="Embedding模型ID")
    EMBEDDING_API_KEY: Optional[str] = Field(default=None, description="Embedding API密钥（为空使用AI_API_KEY）")
    EMBEDDING_API_BASE: str = Field(default="https://api.openai.com/v1", description="Embedding API基础URL")
    EMBEDDING_API_PATH: str = Field(default="/embeddings", description="Embedding API路径")
    EMBEDDING_DIMENSIONS: int = Field(default=1536, ge=128, le=4096, description="向量维度")
    
    # ==========================================
    # 兼容旧配置（向后兼容）
    # ==========================================
    AI_MODEL_PROVIDER: str = Field(default="openai", description="AI模型提供商")
    OPENAI_API_KEY: Optional[str] = Field(default=None, description="[兼容] OpenAI API密钥")
    OPENAI_MODEL: str = Field(default="gpt-4o", description="[兼容] OpenAI模型")
    DOUBAO_API_KEY: Optional[str] = Field(default=None, description="[兼容] 豆包API密钥")
    DOUBAO_MODEL: str = Field(default="doubao-seed-2-0-mini-260215", description="[兼容] 豆包模型")
    DOUBAO_API_BASE: str = Field(default="https://ark.cn-beijing.volces.com/api/v3", description="豆包API基础URL")
    DOUBAO_API_PATH: str = Field(default="/responses", description="豆包API路径")
    
    # ==========================================
    # 文件上传配置
    # ==========================================
    MAX_UPLOAD_SIZE: int = Field(
        default=50 * 1024 * 1024,  # 50MB
        ge=1 * 1024 * 1024,  # 最小1MB
        le=500 * 1024 * 1024,  # 最大500MB
        description="最大上传文件大小（字节）"
    )
    
    ALLOWED_EXTENSIONS: Set[str] = Field(
        default={".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".gif"},
        description="允许的图片文件扩展名"
    )
    
    UPLOAD_CHUNK_SIZE: int = Field(
        default=1024 * 1024,  # 1MB
        ge=64 * 1024,
        le=10 * 1024 * 1024,
        description="上传分块大小"
    )
    
    MAX_CONCURRENT_UPLOADS: int = Field(
        default=5,
        ge=1,
        le=20,
        description="最大并发上传数"
    )
    
    # ==========================================
    # 腾讯云COS配置
    # ==========================================
    COS_ENABLED: bool = Field(default=False, description="是否启用COS存储")
    COS_SECRET_ID: Optional[str] = Field(default=None, description="COS SecretId")
    COS_SECRET_KEY: Optional[str] = Field(default=None, description="COS SecretKey")
    COS_BUCKET: Optional[str] = Field(default=None, description="COS存储桶名称")
    COS_REGION: str = Field(default="ap-beijing", description="COS区域")
    COS_CDN_DOMAIN: Optional[str] = Field(default=None, description="COS CDN加速域名")
    COS_PREFIX: str = Field(default=f"{ENVIRONMENT}/", description="COS对象键前缀")
    COS_EXPIRE_SECONDS: int = Field(default=3600, ge=60, le=86400, description="COS签名URL过期时间（秒）")
    
    @field_validator('COS_CDN_DOMAIN')
    @classmethod
    def validate_cdn_domain(cls, v: Optional[str]) -> Optional[str]:
        """验证CDN域名格式"""
        if v and not v.startswith(('http://', 'https://')):
            return f"https://{v}"
        return v
    
    # ==========================================
    # 人脸识别配置
    # ==========================================
    FACE_ENABLED: bool = Field(default=True, description="是否启用人脸识别")
    FACE_MATCH_THRESHOLD: float = Field(
        default=0.6,
        ge=0.1,
        le=1.0,
        description="人脸匹配阈值（越小越严格）"
    )
    FACE_MIN_SIZE: int = Field(default=50, ge=20, le=200, description="最小人脸检测尺寸（像素）")
    FACE_DETECTION_MODEL: str = Field(
        default="hog",
        pattern=r"^(hog|cnn)$",
        description="人脸检测模型：hog（快速，CPU）或 cnn（准确，需GPU）"
    )
    FACE_ENCODING_MODEL: str = Field(default="small", pattern=r"^(small|large)$", description="人脸编码模型")
    
    # ==========================================
    # 文生图配置（火山引擎豆包）
    # ==========================================
    VOLCENGINE_ACCESS_KEY: Optional[str] = Field(default=None, description="火山引擎AccessKey")
    VOLCENGINE_SECRET_KEY: Optional[str] = Field(default=None, description="火山引擎SecretKey")
    
    IMAGE_GEN_ENABLED: bool = Field(default=True, description="是否启用文生图功能")
    IMAGE_GEN_MODEL_NAME: Optional[str] = Field(default=None, description="文生图模型名称")
    IMAGE_GEN_MODEL_ID: Optional[str] = Field(default=None, description="文生图模型ID")
    IMAGE_GEN_API_KEY: Optional[str] = Field(default=None, description="文生图API密钥")
    IMAGE_GEN_API_BASE: Optional[str] = Field(default=None, description="文生图API基础URL")
    IMAGE_GEN_API_PATH: str = Field(default="/contents/generations/tasks", description="文生图API路径")
    IMAGE_GEN_DEFAULT_FORMAT: str = Field(default="png", pattern=r"^(png|jpeg|jpg|webp)$", description="默认输出格式")
    IMAGE_GEN_WATERMARK: bool = Field(default=False, description="是否添加水印")
    IMAGE_GEN_USE_ENV_MODEL: bool = Field(default=True, description="是否使用环境变量配置的模型")
    IMAGE_GEN_TIMEOUT: int = Field(default=300, ge=30, le=600, description="文生图超时时间（秒）")
    
    # ==========================================
    # 限流配置
    # ==========================================
    RATE_LIMIT_ENABLED: bool = Field(default=True, description="是否启用限流")
    RATE_LIMIT_DEFAULT: str = Field(default="100/minute", description="默认限流规则")
    RATE_LIMIT_UPLOAD: str = Field(default="10/minute", description="上传接口限流")
    RATE_LIMIT_AI: str = Field(default="30/minute", description="AI接口限流")
    
    # ==========================================
    # 日志配置
    # ==========================================
    LOG_LEVEL: str = Field(
        default="INFO" if IS_PRODUCTION else "DEBUG",
        pattern=r"^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$",
        description="日志级别"
    )
    LOG_FORMAT: str = Field(
        default="json" if IS_PRODUCTION else "text",
        pattern=r"^(json|text)$",
        description="日志格式"
    )
    LOG_FILE_ENABLED: bool = Field(default=IS_PRODUCTION, description="是否启用文件日志")
    LOG_FILE_PATH: str = Field(default="./logs/smartalbum.log", description="日志文件路径")
    LOG_FILE_MAX_BYTES: int = Field(default=10 * 1024 * 1024, description="日志文件最大大小")
    LOG_FILE_BACKUP_COUNT: int = Field(default=5, ge=1, le=100, description="日志文件备份数量")
    
    # ==========================================    
    # Pydantic配置
    # ==========================================
    model_config = {
        # 使用绝对路径查找.env文件
        "env_file": os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"
        ),
        "env_file_encoding": 'utf-8',
        "case_sensitive": True,
        # 忽略额外的字段（如REDIS_URL等计算属性）
        "extra": 'ignore',
        # 支持额外的字段类型
        "json_encoders": {
            set: list,
            Path: str
        }
    }
    
    # ==========================================
    # 便捷方法
    # ==========================================
    
    def get_ai_api_key(self) -> Optional[str]:
        """
        获取AI API密钥（支持多源配置）
        
        优先级：AI_API_KEY > OPENAI_API_KEY > DOUBAO_API_KEY
        """
        return self.AI_API_KEY or self.OPENAI_API_KEY or self.DOUBAO_API_KEY
    
    def get_embedding_api_key(self) -> Optional[str]:
        """
        获取Embedding API密钥
        
        优先级：EMBEDDING_API_KEY > AI_API_KEY > OPENAI_API_KEY
        """
        return self.EMBEDDING_API_KEY or self.AI_API_KEY or self.OPENAI_API_KEY
    
    def get_image_gen_config(self) -> Dict[str, Any]:
        """获取文生图完整配置"""
        return {
            "enabled": self.IMAGE_GEN_ENABLED,
            "model_name": self.IMAGE_GEN_MODEL_NAME or self.AI_MODEL_NAME,
            "model_id": self.IMAGE_GEN_MODEL_ID or self.AI_MODEL_ID,
            "api_key": self.IMAGE_GEN_API_KEY or self.get_ai_api_key(),
            "api_base": self.IMAGE_GEN_API_BASE or self.AI_API_BASE,
            "api_path": self.IMAGE_GEN_API_PATH,
            "timeout": self.IMAGE_GEN_TIMEOUT,
            "default_format": self.IMAGE_GEN_DEFAULT_FORMAT,
            "watermark": self.IMAGE_GEN_WATERMARK,
        }
    
    def get_volcengine_credentials(self) -> Tuple[Optional[str], Optional[str]]:
        """获取火山引擎 AK/SK"""
        return (self.VOLCENGINE_ACCESS_KEY, self.VOLCENGINE_SECRET_KEY)
    
    def get_cors_origins(self) -> List[str]:
        """获取CORS来源列表"""
        if isinstance(self.CORS_ORIGINS, list):
            return self.CORS_ORIGINS
        return [origin.strip() for origin in str(self.CORS_ORIGINS).split(',') if origin.strip()]
    
    def get_storage_paths(self) -> Dict[str, Path]:
        """获取所有存储路径"""
        return {
            "storage": Path(self.STORAGE_PATH),
            "originals": Path(self.ORIGINALS_PATH),
            "thumbnails": Path(self.THUMBNAILS_PATH),
            "thumbnail_small": Path(self.THUMBNAIL_SMALL_PATH),
            "thumbnail_medium": Path(self.THUMBNAIL_MEDIUM_PATH),
            "thumbnail_large": Path(self.THUMBNAIL_LARGE_PATH),
            "ai_generated": Path(self.AI_GENERATED_PATH),
        }
    
    def get_ai_models(self) -> List[Dict[str, str]]:
        """获取可用的AI模型列表"""
        models = []
        
        # 当前配置的模型
        if self.get_ai_api_key():
            models.append({
                "id": self.AI_MODEL_ID,
                "name": self.AI_MODEL_NAME,
                "provider": self.AI_MODEL_PROVIDER,
                "active": True
            })
        
        # 兼容的旧配置
        if self.OPENAI_API_KEY and self.OPENAI_API_KEY != self.AI_API_KEY:
            models.append({
                "id": self.OPENAI_MODEL,
                "name": f"OpenAI {self.OPENAI_MODEL}",
                "provider": "openai",
                "active": False
            })
        
        if self.DOUBAO_API_KEY and self.DOUBAO_API_KEY != self.AI_API_KEY:
            models.append({
                "id": self.DOUBAO_MODEL,
                "name": f"豆包 {self.DOUBAO_MODEL}",
                "provider": "doubao",
                "active": False
            })
        
        return models
    
    def get_upload_config(self) -> Dict[str, Any]:
        """获取上传配置"""
        return {
            "max_size": self.MAX_UPLOAD_SIZE,
            "max_size_mb": self.MAX_UPLOAD_SIZE / (1024 * 1024),
            "allowed_extensions": list(self.ALLOWED_EXTENSIONS),
            "chunk_size": self.UPLOAD_CHUNK_SIZE,
            "max_concurrent": self.MAX_CONCURRENT_UPLOADS,
        }
    
    def get_database_config(self) -> Dict[str, Any]:
        """获取数据库配置"""
        return {
            "url": self.DATABASE_URL,
            "pool_size": self.DATABASE_POOL_SIZE,
            "max_overflow": self.DATABASE_MAX_OVERFLOW,
        }
    
    def get_redis_config(self) -> Dict[str, Any]:
        """获取Redis配置"""
        return {
            "host": self.REDIS_HOST,
            "port": self.REDIS_PORT,
            "db": self.REDIS_DB,
            "password": self.REDIS_PASSWORD,
            "url": self.REDIS_URL,
        }
    
    # ==========================================
    # 验证方法
    # ==========================================
    
    def validate_security(self) -> None:
        """验证安全配置"""
        errors = []
        warnings = []
        
        # 生产环境密钥检查
        if self.IS_PRODUCTION:
            if not self.SECRET_KEY:
                errors.append(
                    "生产环境必须设置 SECRET_KEY 环境变量。\n"
                    "请运行: python -c \"import secrets; print(secrets.token_hex(32))\" 生成密钥"
                )
            elif len(self.SECRET_KEY) < 32:
                errors.append(
                    f"生产环境 SECRET_KEY 长度必须至少32位，当前长度: {len(self.SECRET_KEY)}"
                )
            
            if not self.DEFAULT_PASSWORD:
                warnings.append("生产环境建议设置 DEFAULT_PASSWORD 环境变量")
            
            # 检查是否为默认密钥
            weak_keys = ['secret', 'password', '123456', 'admin', 'default']
            if self.SECRET_KEY and any(weak in self.SECRET_KEY.lower() for weak in weak_keys):
                errors.append("SECRET_KEY 不能使用弱密钥或常见密码")
        
        # AI 配置检查
        if not self.get_ai_api_key():
            warnings.append("未配置 AI API 密钥，AI 功能将不可用")
        
        # COS 配置检查
        if self.COS_ENABLED:
            missing = []
            if not self.COS_SECRET_ID:
                missing.append("COS_SECRET_ID")
            if not self.COS_SECRET_KEY:
                missing.append("COS_SECRET_KEY")
            if not self.COS_BUCKET:
                missing.append("COS_BUCKET")
            if missing:
                errors.append(f"启用COS存储但未配置: {', '.join(missing)}")
        
        # 路径权限检查
        for name, path in self.get_storage_paths().items():
            try:
                path.mkdir(parents=True, exist_ok=True)
                test_file = path / ".write_test"
                test_file.touch()
                test_file.unlink()
            except (OSError, PermissionError) as e:
                errors.append(f"存储路径 {name} ({path}) 无写入权限: {e}")
        
        # 输出警告
        for warning in warnings:
            logger.warning(f"[配置警告] {warning}")
        
        # 抛出错误
        if errors:
            raise ValueError("\n".join(f"[配置错误] {e}" for e in errors))
    
    def validate_ai_config(self) -> Dict[str, Any]:
        """验证AI配置并返回状态报告"""
        report = {
            "ai_available": False,
            "embedding_available": False,
            "image_gen_available": False,
            "models": [],
            "warnings": []
        }
        
        # 检查 AI API
        ai_key = self.get_ai_api_key()
        if ai_key:
            report["ai_available"] = True
            report["models"].append({
                "type": "chat",
                "name": self.AI_MODEL_NAME,
                "id": self.AI_MODEL_ID
            })
        else:
            report["warnings"].append("AI API 密钥未配置")
        
        # 检查 Embedding API
        emb_key = self.get_embedding_api_key()
        if emb_key:
            report["embedding_available"] = True
        else:
            report["warnings"].append("Embedding API 密钥未配置")
        
        # 检查文生图配置
        if self.IMAGE_GEN_ENABLED and self.get_volcengine_credentials()[0]:
            report["image_gen_available"] = True
        
        return report
    
    def get_config_summary(self) -> Dict[str, Any]:
        """获取配置摘要（用于诊断和日志）"""
        ai_report = self.validate_ai_config()
        
        return {
            "app": {
                "name": self.APP_NAME,
                "version": self.APP_VERSION,
                "environment": self.ENVIRONMENT,
                "debug": self.DEBUG,
            },
            "features": {
                "ai": ai_report["ai_available"],
                "embedding": ai_report["embedding_available"],
                "image_gen": ai_report["image_gen_available"],
                "face_recognition": self.FACE_ENABLED,
                "cos_storage": self.COS_ENABLED,
            },
            "storage": {
                "paths": {k: str(v) for k, v in self.get_storage_paths().items()},
            },
            "ai_models": ai_report["models"],
            "warnings": ai_report["warnings"],
        }


# ==========================================
# 全局配置实例
# ==========================================

settings = Settings()

# 启动时验证配置
try:
    settings.validate_security()
    logger.info(f"配置加载成功 [环境: {settings.ENVIRONMENT}]")
    
    # 开发环境打印配置摘要
    if settings.IS_DEVELOPMENT:
        import json
        summary = settings.get_config_summary()
        logger.debug(f"配置摘要:\n{json.dumps(summary, indent=2, ensure_ascii=False)}")
        
except ValueError as e:
    logger.error(f"配置验证失败: {e}")
    raise
