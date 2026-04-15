"""
腾讯云COS存储服务
"""
import os
import uuid
import tempfile
from typing import Optional, Tuple, Dict
from qcloud_cos import CosConfig
from qcloud_cos import CosS3Client
from app.config import settings
from app.services.logger_service import logger_service


class COSService:
    """腾讯云COS存储服务"""
    
    def __init__(self):
        self.enabled = settings.COS_ENABLED
        self.bucket = settings.COS_BUCKET
        self.region = settings.COS_REGION
        self.cdn_domain = settings.COS_CDN_DOMAIN
        
        if self.enabled and settings.COS_SECRET_ID and settings.COS_SECRET_KEY:
            config = CosConfig(
                Region=self.region,
                SecretId=settings.COS_SECRET_ID,
                SecretKey=settings.COS_SECRET_KEY
            )
            self.client = CosS3Client(config)
            logger_service.info(f"COS服务初始化: bucket={self.bucket}, region={self.region}")
        else:
            self.client = None
            logger_service.info("COS服务未启用，使用本地存储")
    
    def is_enabled(self) -> bool:
        """检查COS是否启用"""
        return self.enabled and self.client is not None
    
    def _get_object_key(self, relative_path: str) -> str:
        """
        获取COS对象键（自动添加环境前缀）
        
        Args:
            relative_path: 相对路径（如 originals/xxx.jpg）
            
        Returns:
            COS对象键（带环境前缀，如 development/originals/xxx.jpg）
        """
        # 移除开头的斜杠和storage/
        key = relative_path.lstrip('/')
        if key.startswith('storage/'):
            key = key[8:]
        
        # 添加环境前缀（如果配置且不是已包含）
        prefix = settings.COS_PREFIX
        if prefix and not key.startswith(prefix):
            key = f"{prefix}{key}"
        
        return key
    
    def upload_file(self, local_path: str, relative_path: str) -> Tuple[bool, str]:
        """
        上传文件到COS
        
        Args:
            local_path: 本地文件路径
            relative_path: 存储的相对路径
            
        Returns:
            (是否成功, COS路径或错误信息)
        """
        if not self.is_enabled():
            return False, "COS not enabled"
        
        try:
            key = self._get_object_key(relative_path)
            
            with open(local_path, 'rb') as fp:
                self.client.put_object(
                    Bucket=self.bucket,
                    Body=fp,
                    Key=key,
                    EnableMD5=False
                )
            
            logger_service.info(f"COS上传成功: {key}")
            return True, key
            
        except Exception as e:
            logger_service.error(f"COS上传失败: {e}")
            return False, str(e)
    
    def upload_bytes(self, data: bytes, relative_path: str, content_type: str = 'image/jpeg') -> Tuple[bool, str]:
        """
        上传字节数据到COS
        
        Args:
            data: 文件字节数据
            relative_path: 存储的相对路径
            content_type: 内容类型
            
        Returns:
            (是否成功, COS路径或错误信息)
        """
        if not self.is_enabled():
            return False, "COS not enabled"
        
        try:
            key = self._get_object_key(relative_path)
            
            self.client.put_object(
                Bucket=self.bucket,
                Body=data,
                Key=key,
                ContentType=content_type,
                EnableMD5=False
            )
            
            logger_service.info(f"COS上传成功: {key}")
            return True, key
            
        except Exception as e:
            logger_service.error(f"COS上传失败: {e}")
            return False, str(e)
    
    def download_file(self, key: str, local_path: str) -> Tuple[bool, str]:
        """
        从COS下载文件
        
        Args:
            key: COS对象键（相对路径，如 originals/xxx.jpg）
            local_path: 本地保存路径
            
        Returns:
            (是否成功, 错误信息)
        """
        if not self.is_enabled():
            return False, "COS not enabled"
        
        try:
            # 自动添加环境前缀
            cos_key = self._get_object_key(key)
            
            response = self.client.get_object(
                Bucket=self.bucket,
                Key=cos_key
            )
            
            # 确保目录存在
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            
            # 使用流式读取并分块写入，确保完整下载
            with open(local_path, 'wb') as fp:
                chunk_size = 1024 * 1024  # 1MB chunks
                body = response['Body']
                while True:
                    chunk = body.read(chunk_size)
                    if not chunk:
                        break
                    fp.write(chunk)
            
            return True, ""
            
        except Exception as e:
            logger_service.error(f"COS下载失败: {e}")
            return False, str(e)
    
    def delete_file(self, relative_path: str) -> Tuple[bool, str]:
        """
        删除COS文件
        
        Args:
            relative_path: 存储的相对路径
            
        Returns:
            (是否成功, 错误信息)
        """
        if not self.is_enabled():
            return True, ""  # 本地存储由其他逻辑处理
        
        try:
            key = self._get_object_key(relative_path)
            
            self.client.delete_object(
                Bucket=self.bucket,
                Key=key
            )
            
            logger_service.info(f"COS删除成功: {key}")
            return True, ""
            
        except Exception as e:
            logger_service.error(f"COS删除失败: {e}")
            return False, str(e)
    
    def get_url(self, relative_path: str, expires: int = 3600) -> str:
        """
        获取文件访问URL
        
        Args:
            relative_path: 存储的相对路径
            expires: 签名URL有效期（秒），仅对私有读桶有效
            
        Returns:
            文件访问URL
        """
        if not self.is_enabled():
            # 本地存储返回相对路径
            return f"/storage/{relative_path}"
        
        key = self._get_object_key(relative_path)
        
        # 如果配置了CDN域名，使用CDN
        if self.cdn_domain:
            return f"https://{self.cdn_domain}/{key}"
        
        # 生成签名URL（适用于私有读桶）
        try:
            url = self.client.get_presigned_url(
                Method='GET',
                Bucket=self.bucket,
                Key=key,
                Expired=expires
            )
            return url
        except Exception as e:
            logger_service.error(f"生成签名URL失败: {e}")
            # 返回默认URL格式
            return f"https://{self.bucket}.cos.{self.region}.myqcloud.com/{key}"
    
    def get_public_url(self, relative_path: str) -> str:
        """
        获取公开读文件的URL（不带签名）
        
        Args:
            relative_path: 存储的相对路径
            
        Returns:
            公开访问URL
        """
        if not self.is_enabled():
            return f"/storage/{relative_path}"
        
        key = self._get_object_key(relative_path)
        
        if self.cdn_domain:
            return f"https://{self.cdn_domain}/{key}"
        
        return f"https://{self.bucket}.cos.{self.region}.myqcloud.com/{key}"


# 创建全局实例
cos_service = COSService()
