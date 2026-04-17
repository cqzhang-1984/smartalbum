"""
配置验证器模块
提供配置项的验证、转换和安全检查功能
"""
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union
from enum import Enum
from dataclasses import dataclass


class ValidationError(Exception):
    """配置验证错误"""
    pass


class ConfigValidationError(Exception):
    """配置验证失败错误，包含多个验证错误"""
    
    def __init__(self, errors: List[str]):
        self.errors = errors
        super().__init__(f"配置验证失败 ({len(errors)} 个错误):\n" + "\n".join(f"  - {e}" for e in errors))


@dataclass
class ValidationResult:
    """验证结果"""
    is_valid: bool
    value: Any
    errors: List[str]
    warnings: List[str]


class Validator:
    """配置验证器基类"""
    
    def __init__(self):
        self.errors: List[str] = []
        self.warnings: List[str] = []
    
    def validate(self, value: Any) -> ValidationResult:
        """执行验证，子类必须实现"""
        raise NotImplementedError
    
    def clear(self):
        """清除验证状态"""
        self.errors = []
        self.warnings = []


class StringValidator(Validator):
    """字符串验证器"""
    
    def __init__(
        self,
        min_length: Optional[int] = None,
        max_length: Optional[int] = None,
        pattern: Optional[str] = None,
        allowed_values: Optional[List[str]] = None,
        allow_empty: bool = False
    ):
        super().__init__()
        self.min_length = min_length
        self.max_length = max_length
        self.pattern = re.compile(pattern) if pattern else None
        self.allowed_values = allowed_values
        self.allow_empty = allow_empty
    
    def validate(self, value: Any) -> ValidationResult:
        self.clear()
        
        if value is None:
            if not self.allow_empty:
                self.errors.append("值不能为空")
            return ValidationResult(len(self.errors) == 0, value, self.errors, self.warnings)
        
        str_value = str(value)
        
        # 空值检查
        if not str_value and not self.allow_empty:
            self.errors.append("字符串不能为空")
            return ValidationResult(False, str_value, self.errors, self.warnings)
        
        # 长度检查
        if self.min_length is not None and len(str_value) < self.min_length:
            self.errors.append(f"字符串长度 {len(str_value)} 小于最小长度 {self.min_length}")
        
        if self.max_length is not None and len(str_value) > self.max_length:
            self.errors.append(f"字符串长度 {len(str_value)} 超过最大长度 {self.max_length}")
        
        # 正则匹配
        if self.pattern and str_value:
            if not self.pattern.match(str_value):
                self.errors.append(f"字符串格式不匹配模式: {self.pattern.pattern}")
        
        # 枚举值检查
        if self.allowed_values and str_value not in self.allowed_values:
            self.errors.append(f"值 '{str_value}' 不在允许列表中: {self.allowed_values}")
        
        return ValidationResult(len(self.errors) == 0, str_value, self.errors, self.warnings)


class IntegerValidator(Validator):
    """整数验证器"""
    
    def __init__(
        self,
        min_value: Optional[int] = None,
        max_value: Optional[int] = None,
        allow_none: bool = False
    ):
        super().__init__()
        self.min_value = min_value
        self.max_value = max_value
        self.allow_none = allow_none
    
    def validate(self, value: Any) -> ValidationResult:
        self.clear()
        
        if value is None:
            if not self.allow_none:
                self.errors.append("值不能为空")
            return ValidationResult(len(self.errors) == 0, value, self.errors, self.warnings)
        
        try:
            int_value = int(value)
        except (ValueError, TypeError):
            self.errors.append(f"无法将值 '{value}' 转换为整数")
            return ValidationResult(False, value, self.errors, self.warnings)
        
        # 范围检查
        if self.min_value is not None and int_value < self.min_value:
            self.errors.append(f"值 {int_value} 小于最小值 {self.min_value}")
        
        if self.max_value is not None and int_value > self.max_value:
            self.errors.append(f"值 {int_value} 超过最大值 {self.max_value}")
        
        return ValidationResult(len(self.errors) == 0, int_value, self.errors, self.warnings)


class FloatValidator(Validator):
    """浮点数验证器"""
    
    def __init__(
        self,
        min_value: Optional[float] = None,
        max_value: Optional[float] = None,
        allow_none: bool = False
    ):
        super().__init__()
        self.min_value = min_value
        self.max_value = max_value
        self.allow_none = allow_none
    
    def validate(self, value: Any) -> ValidationResult:
        self.clear()
        
        if value is None:
            if not self.allow_none:
                self.errors.append("值不能为空")
            return ValidationResult(len(self.errors) == 0, value, self.errors, self.warnings)
        
        try:
            float_value = float(value)
        except (ValueError, TypeError):
            self.errors.append(f"无法将值 '{value}' 转换为浮点数")
            return ValidationResult(False, value, self.errors, self.warnings)
        
        # 范围检查
        if self.min_value is not None and float_value < self.min_value:
            self.errors.append(f"值 {float_value} 小于最小值 {self.min_value}")
        
        if self.max_value is not None and float_value > self.max_value:
            self.errors.append(f"值 {float_value} 超过最大值 {self.max_value}")
        
        return ValidationResult(len(self.errors) == 0, float_value, self.errors, self.warnings)


class BooleanValidator(Validator):
    """布尔值验证器"""
    
    TRUE_VALUES = {'true', '1', 'yes', 'on', 'enabled'}
    FALSE_VALUES = {'false', '0', 'no', 'off', 'disabled'}
    
    def validate(self, value: Any) -> ValidationResult:
        self.clear()
        
        if value is None:
            return ValidationResult(True, False, [], ["布尔值默认为 False"])
        
        if isinstance(value, bool):
            return ValidationResult(True, value, [], [])
        
        str_value = str(value).lower()
        
        if str_value in self.TRUE_VALUES:
            return ValidationResult(True, True, [], [])
        elif str_value in self.FALSE_VALUES:
            return ValidationResult(True, False, [], [])
        else:
            self.warnings.append(f"无法识别的布尔值 '{value}'，使用默认值 False")
            return ValidationResult(True, False, [], self.warnings)


class PathValidator(Validator):
    """路径验证器"""
    
    def __init__(
        self,
        must_exist: bool = False,
        must_be_file: bool = False,
        must_be_dir: bool = False,
        allow_none: bool = False
    ):
        super().__init__()
        self.must_exist = must_exist
        self.must_be_file = must_be_file
        self.must_be_dir = must_be_dir
        self.allow_none = allow_none
    
    def validate(self, value: Any) -> ValidationResult:
        self.clear()
        
        if value is None:
            if not self.allow_none:
                self.errors.append("路径不能为空")
            return ValidationResult(len(self.errors) == 0, value, self.errors, self.warnings)
        
        path = Path(value)
        
        # 检查路径是否有效
        try:
            path.resolve()
        except (OSError, ValueError) as e:
            self.errors.append(f"无效的路径: {value} ({e})")
            return ValidationResult(False, path, self.errors, self.warnings)
        
        # 存在性检查
        if self.must_exist and not path.exists():
            self.errors.append(f"路径不存在: {path}")
        
        # 类型检查
        if self.must_be_file and path.exists() and not path.is_file():
            self.errors.append(f"路径不是文件: {path}")
        
        if self.must_be_dir and path.exists() and not path.is_dir():
            self.errors.append(f"路径不是目录: {path}")
        
        return ValidationResult(len(self.errors) == 0, path, self.errors, self.warnings)


class URLValidator(Validator):
    """URL 验证器"""
    
    URL_PATTERN = re.compile(
        r'^https?://'  # http:// or https://
        r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'  # domain
        r'localhost|'  # localhost
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # or ip
        r'(?::\d+)?'  # optional port
        r'(?:/?|[/?]\S+)$', re.IGNORECASE
    )
    
    def __init__(self, allow_relative: bool = False, schemes: Optional[List[str]] = None):
        super().__init__()
        self.allow_relative = allow_relative
        self.schemes = schemes or ['http', 'https']
    
    def validate(self, value: Any) -> ValidationResult:
        self.clear()
        
        if value is None or value == '':
            self.errors.append("URL 不能为空")
            return ValidationResult(False, value, self.errors, self.warnings)
        
        url = str(value)
        
        # 允许相对路径（以 / 开头）
        if self.allow_relative and url.startswith('/'):
            return ValidationResult(True, url, [], [])
        
        # 检查协议
        if '://' in url:
            scheme = url.split('://')[0].lower()
            if scheme not in self.schemes:
                self.errors.append(f"不支持的 URL 协议: {scheme}，允许: {self.schemes}")
                return ValidationResult(False, url, self.errors, self.warnings)
        
        # 正则验证
        if not self.URL_PATTERN.match(url):
            self.errors.append(f"无效的 URL 格式: {url}")
        
        return ValidationResult(len(self.errors) == 0, url, self.errors, self.warnings)


class ConfigSchema:
    """配置模式定义"""
    
    def __init__(self):
        self.validators: Dict[str, Validator] = {}
        self.required_fields: set = set()
        self.defaults: Dict[str, Any] = {}
    
    def add_field(
        self,
        name: str,
        validator: Validator,
        required: bool = False,
        default: Any = None
    ):
        """添加配置字段"""
        self.validators[name] = validator
        if required:
            self.required_fields.add(name)
        if default is not None:
            self.defaults[name] = default
    
    def validate(self, config: Dict[str, Any]) -> Tuple[Dict[str, Any], List[str], List[str]]:
        """
        验证配置字典
        
        Returns:
            (validated_config, errors, warnings)
        """
        errors = []
        warnings = []
        validated = {}
        
        # 检查必填项
        for field in self.required_fields:
            if field not in config or config[field] is None:
                errors.append(f"缺少必填配置项: {field}")
        
        # 验证每个字段
        for name, validator in self.validators.items():
            value = config.get(name, self.defaults.get(name))
            
            if value is None and name not in self.required_fields:
                continue
            
            result = validator.validate(value)
            
            if result.errors:
                errors.extend([f"{name}: {e}" for e in result.errors])
            if result.warnings:
                warnings.extend([f"{name}: {w}" for w in result.warnings])
            
            if result.is_valid:
                validated[name] = result.value
        
        return validated, errors, warnings


class SmartAlbumConfigValidator:
    """SmartAlbum 专用配置验证器"""
    
    def __init__(self):
        self.schema = ConfigSchema()
        self._init_schema()
    
    def _init_schema(self):
        """初始化 SmartAlbum 配置模式"""
        
        # 基础配置
        self.schema.add_field(
            'APP_NAME',
            StringValidator(min_length=1, max_length=50),
            required=True,
            default='SmartAlbum'
        )
        self.schema.add_field(
            'APP_VERSION',
            StringValidator(pattern=r'^\d+\.\d+\.\d+$'),
            default='1.0.0'
        )
        self.schema.add_field(
            'DEBUG',
            BooleanValidator(),
            default=False
        )
        self.schema.add_field(
            'ENVIRONMENT',
            StringValidator(allowed_values=['development', 'staging', 'production']),
            default='development'
        )
        
        # 数据库配置
        self.schema.add_field(
            'DATABASE_URL',
            StringValidator(min_length=10),
            required=True
        )
        
        # 存储配置
        self.schema.add_field(
            'UPLOAD_DIR',
            PathValidator(must_be_dir=False),
            default='./storage/uploads'
        )
        self.schema.add_field(
            'THUMBNAIL_DIR',
            PathValidator(must_be_dir=False),
            default='./storage/thumbnails'
        )
        
        # AI 配置
        self.schema.add_field(
            'AI_API_KEY',
            StringValidator(min_length=10, allow_empty=True),
            allow_none=True
        )
        self.schema.add_field(
            'AI_API_BASE',
            URLValidator(allow_relative=False),
            default='https://api.openai.com/v1'
        )
        self.schema.add_field(
            'AI_MODEL_ID',
            StringValidator(min_length=1),
            default='gpt-4o'
        )
        
        # 缩略图配置
        self.schema.add_field(
            'THUMBNAIL_SMALL_SIZE',
            StringValidator(pattern=r'^\(\d+,\s*\d+\)$'),
            default='(300, 300)'
        )
        self.schema.add_field(
            'THUMBNAIL_QUALITY',
            IntegerValidator(min_value=1, max_value=100),
            default=85
        )
        
        # 安全配置
        self.schema.add_field(
            'SECRET_KEY',
            StringValidator(min_length=32),
            required=True
        )
        self.schema.add_field(
            'MAX_UPLOAD_SIZE',
            IntegerValidator(min_value=1, max_value=500),
            default=100
        )
        self.schema.add_field(
            'ALLOWED_IMAGE_TYPES',
            StringValidator(),
            default='jpg,jpeg,png,gif,webp,heic,heif'
        )
        
        # 并发配置
        self.schema.add_field(
            'AI_WORKERS',
            IntegerValidator(min_value=1, max_value=20),
            default=3
        )
        self.schema.add_field(
            'MAX_CONCURRENT_UPLOADS',
            IntegerValidator(min_value=1, max_value=20),
            default=5
        )
    
    def validate(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """
        验证配置并返回验证后的配置字典
        
        Raises:
            ConfigValidationError: 验证失败时抛出
        """
        validated, errors, warnings = self.schema.validate(config)
        
        if errors:
            raise ConfigValidationError(errors)
        
        if warnings:
            import logging
            logger = logging.getLogger(__name__)
            for warning in warnings:
                logger.warning(f"配置警告: {warning}")
        
        return validated


# 全局验证器实例
config_validator = SmartAlbumConfigValidator()


def validate_config(config: Dict[str, Any]) -> Dict[str, Any]:
    """便捷的验证函数"""
    return config_validator.validate(config)
