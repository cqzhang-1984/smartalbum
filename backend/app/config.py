from pydantic_settings import BaseSettings
from typing import Optional
import os


# 读取环境变量
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development").lower()
IS_PRODUCTION: bool = ENVIRONMENT == "production"


class Settings(BaseSettings):
    """应用配置"""
    
    # 应用基础配置
    APP_NAME: str = "SmartAlbum"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    
    # 运行环境
    ENVIRONMENT: str = ENVIRONMENT
    IS_PRODUCTION: bool = IS_PRODUCTION
    
    # JWT密钥（用于认证，必须从环境变量设置，生产环境要求至少32位）
    SECRET_KEY: str = os.getenv("SECRET_KEY", "")
    
    # 默认用户配置（生产环境必须通过环境变量设置强密码）
    DEFAULT_USERNAME: str = os.getenv("DEFAULT_USERNAME", "admin")
    DEFAULT_PASSWORD: str = os.getenv("DEFAULT_PASSWORD", "")
    
    # CORS配置
    CORS_ORIGINS: str = "http://localhost:8888,http://localhost:3000"
    
    # 数据库配置
    DATABASE_URL: str = "sqlite+aiosqlite:///./data/smartalbum.db"
    
    # Redis配置 - 根据环境自动选择数据库
    # 开发环境使用 DB 11，生产环境使用 DB 1
    REDIS_DB: int = 1 if IS_PRODUCTION else 11
    REDIS_URL: str = f"redis://localhost:6379/{REDIS_DB}"
    
    # 存储路径配置
    STORAGE_PATH: str = "./storage"
    ORIGINALS_PATH: str = "./storage/originals"
    THUMBNAILS_PATH: str = "./storage/thumbnails"
    THUMBNAIL_SMALL_PATH: str = "./storage/thumbnails/small"
    THUMBNAIL_MEDIUM_PATH: str = "./storage/thumbnails/medium"
    THUMBNAIL_LARGE_PATH: str = "./storage/thumbnails/large"
    
    # 数据库文件路径
    DATABASE_PATH: str = "./data/smartalbum.db"
    CHROMA_PATH: str = "./data/chroma"
    
    # 缩略图尺寸配置
    THUMBNAIL_SMALL_SIZE: tuple = (150, 150)
    THUMBNAIL_MEDIUM_SIZE: tuple = (400, 400)
    THUMBNAIL_LARGE_SIZE: tuple = (1920, 1080)
    
    # AI模型配置（符合OpenAI规范）
    AI_MODEL_NAME: str = "GPT-4o"  # 模型显示名称
    AI_MODEL_ID: str = "gpt-4o"    # 模型ID（调用时使用）
    AI_API_KEY: Optional[str] = None  # API密钥
    AI_API_BASE: str = "https://api.openai.com/v1"  # API基础URL
    AI_API_PATH: str = "/chat/completions"  # API路径
    
    # Embedding模型配置（符合OpenAI规范）
    EMBEDDING_MODEL_NAME: str = "text-embedding-3-small"  # 模型显示名称
    EMBEDDING_MODEL_ID: str = "text-embedding-3-small"    # 模型ID
    EMBEDDING_API_KEY: Optional[str] = None  # API密钥（为空时使用AI_API_KEY）
    EMBEDDING_API_BASE: str = "https://api.openai.com/v1"  # API基础URL
    EMBEDDING_API_PATH: str = "/embeddings"  # API路径
    
    # 兼容旧配置（向后兼容）
    AI_MODEL_PROVIDER: str = "openai"
    OPENAI_API_KEY: Optional[str] = None
    OPENAI_MODEL: str = "gpt-4o"
    DOUBAO_API_KEY: Optional[str] = None
    DOUBAO_MODEL: str = "doubao-seed-2-0-mini-260215"
    DOUBAO_API_BASE: str = "https://ark.cn-beijing.volces.com/api/v3"
    DOUBAO_API_PATH: str = "/responses"
    
    # 文件上传配置
    MAX_UPLOAD_SIZE: int = 50 * 1024 * 1024  # 50MB
    ALLOWED_EXTENSIONS: set = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
    
    # 腾讯云COS存储配置
    COS_ENABLED: bool = False
    COS_SECRET_ID: Optional[str] = None
    COS_SECRET_KEY: Optional[str] = None
    COS_BUCKET: Optional[str] = None
    COS_REGION: str = "ap-beijing"
    COS_CDN_DOMAIN: Optional[str] = None  # CDN加速域名（可选）
    COS_PREFIX: str = f"{ENVIRONMENT}/"  # 环境目录前缀：development/ 或 production/
    
    # 人脸识别配置
    FACE_MATCH_THRESHOLD: float = 0.6  # 人脸匹配阈值（越小越严格，范围0-1）
    FACE_MIN_SIZE: int = 50  # 最小人脸检测尺寸（像素）
    FACE_DETECTION_MODEL: str = "hog"  # 检测模型：hog（快速，CPU）或 cnn（准确，需GPU）
    
    # 文生图配置（火山引擎豆包）
    # 火山引擎 AK/SK（用于文生图 API 认证）
    VOLCENGINE_ACCESS_KEY: Optional[str] = None
    VOLCENGINE_SECRET_KEY: Optional[str] = None
    
    # 文生图模型配置（豆包方舟平台）
    IMAGE_GEN_MODEL_NAME: Optional[str] = None  # 模型显示名称（为空则使用AI_MODEL_NAME）
    IMAGE_GEN_MODEL_ID: Optional[str] = None  # 模型ID（为空则使用AI_MODEL_ID）
    IMAGE_GEN_API_KEY: Optional[str] = None  # API密钥（为空则使用AI_API_KEY）
    IMAGE_GEN_API_BASE: Optional[str] = None  # API基础URL（为空则使用AI_API_BASE）
    IMAGE_GEN_API_PATH: str = "/contents/generations/tasks"  # API路径
    IMAGE_GEN_DEFAULT_FORMAT: str = "png"  # 默认输出格式
    IMAGE_GEN_WATERMARK: bool = False  # 是否添加水印
    
    # 是否只使用环境变量配置的AI模型（豆包多模态API）
    IMAGE_GEN_USE_ENV_MODEL: bool = True  # 为True时，仅使用AI_MODEL_NAME/AI_MODEL_ID作为文生图模型
    
    # AI生成图片存储路径
    AI_GENERATED_PATH: str = "./storage/ai_generated"
    
    # 可用的文生图模型列表
    IMAGE_GEN_MODELS: dict = {
        "high_aes_general_v1.3": {"name": "高美感通用 V1.3", "description": "高质量写实风格，适合人像、风景"},
        "high_aes_general_v2.0": {"name": "高美感通用 V2.0", "description": "最新版本，更强的细节表现"},
        "anime_style_v1.0": {"name": "动漫风格", "description": "日系动漫风格，适合二次元创作"},
        "watercolor_style_v1.0": {"name": "水彩风格", "description": "艺术水彩画风格"},
        "oil_painting_style_v1.0": {"name": "油画风格", "description": "古典油画艺术风格"},
    }
    
    # 图片尺寸预设（API格式: WIDTHxHEIGHT, 2k, 3k）
    # 注意：API要求至少3686400像素，以下尺寸均满足要求
    IMAGE_GEN_SIZES: dict = {
        "1:1": {"name": "正方形 2048×2048", "width": 2048, "height": 2048, "description": "头像、社交媒体"},
        "16:9": {"name": "横屏宽屏 2560×1440", "width": 2560, "height": 1440, "description": "视频封面、横屏壁纸"},
        "9:16": {"name": "竖屏手机 1440×2560", "width": 1440, "height": 2560, "description": "手机锁屏、短视频封面"},
        "3:4": {"name": "竖屏标准 1920×2560", "width": 1920, "height": 2560, "description": "手机壁纸、人像照"},
        "4:3": {"name": "横屏标准 2560×1920", "width": 2560, "height": 1920, "description": "电脑壁纸、展示图"},
        "2K": {"name": "2K高清 2048×2048", "width": 2048, "height": 2048, "description": "高质量图片"},
        "4K": {"name": "3K高清 3072×3072", "width": 3072, "height": 3072, "description": "超高分辨率"},
    }
    
    class Config:
        # 使用绝对路径查找.env文件
        _backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        env_file = os.path.join(_backend_dir, ".env")
        case_sensitive = True
    
    def get_ai_api_key(self) -> Optional[str]:
        """获取AI API密钥"""
        return self.AI_API_KEY or self.OPENAI_API_KEY or self.DOUBAO_API_KEY
    
    def get_embedding_api_key(self) -> Optional[str]:
        """获取Embedding API密钥"""
        return self.EMBEDDING_API_KEY or self.AI_API_KEY or self.OPENAI_API_KEY
    
    def get_image_gen_model_name(self) -> str:
        """获取文生图模型名称"""
        return self.IMAGE_GEN_MODEL_NAME or self.AI_MODEL_NAME
    
    def get_image_gen_model_id(self) -> str:
        """获取文生图模型ID"""
        # 如果配置了使用环境变量中的模型，优先使用 AI_MODEL_ID
        if self.IMAGE_GEN_USE_ENV_MODEL:
            return self.IMAGE_GEN_MODEL_ID or self.AI_MODEL_ID or self.IMAGE_GEN_DEFAULT_MODEL
        return self.IMAGE_GEN_MODEL_ID or self.IMAGE_GEN_DEFAULT_MODEL
    
    def get_volcengine_credentials(self) -> tuple:
        """获取火山引擎 AK/SK"""
        return (self.VOLCENGINE_ACCESS_KEY, self.VOLCENGINE_SECRET_KEY)
    
    def get_available_image_sizes(self) -> dict:
        """获取可用的图片尺寸列表"""
        return self.IMAGE_GEN_SIZES
    
    def get_available_image_models(self) -> dict:
        """获取可用的文生图模型列表"""
        # 如果配置了只使用环境变量中的模型，则只返回该模型
        if self.IMAGE_GEN_USE_ENV_MODEL:
            model_name = self.get_image_gen_model_name()
            model_id = self.get_image_gen_model_id()
            return {
                model_id: {
                    "name": model_name,
                    "description": "环境变量配置的模型"
                }
            }
        return self.IMAGE_GEN_MODELS
    
    def validate_security_config(self) -> None:
        """验证安全配置，确保生产环境密钥安全"""
        if self.IS_PRODUCTION:
            if not self.SECRET_KEY:
                raise ValueError(
                    "生产环境必须设置 SECRET_KEY 环境变量。"
                    "请运行: python -c \"import secrets; print(secrets.token_hex(32))\" 生成密钥"
                )
            if len(self.SECRET_KEY) < 32:
                raise ValueError(
                    f"生产环境 SECRET_KEY 长度必须至少32位，当前长度: {len(self.SECRET_KEY)}"
                )


# 创建全局配置实例
settings = Settings()

# 启动时验证安全配置
settings.validate_security_config()
