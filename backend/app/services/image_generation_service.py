"""
AI图片生成服务 - 火山引擎豆包方舟平台图片生成API
API端点: https://ark.cn-beijing.volces.com/api/v3/images/generations
"""
import os
import httpx
import uuid
import base64
import asyncio
from typing import Dict, Optional, List, Tuple
from app.config import settings
from app.services.logger_service import logger_service


class ImageGenerationService:
    """图片生成服务类 - 火山引擎豆包方舟平台"""
    
    # 豆包支持的尺寸预设（API格式：WIDTHxHEIGHT, 2k, 3k）
    # 注意：API要求至少3686400像素，以下尺寸均满足要求
    SIZE_PRESETS = {
        "1:1": "2048x2048",     # 4,194,304 像素
        "2K": "2048x2048",      # 4,194,304 像素
        "4K": "3072x3072",      # 9,437,184 像素
        "16:9": "2560x1440",    # 3,686,400 像素
        "9:16": "1440x2560",    # 3,686,400 像素
        "3:4": "1920x2560",     # 4,915,200 像素
        "4:3": "2560x1920",     # 4,915,200 像素
    }
    
    def __init__(self):
        # 使用方舟平台的 API Key（与对话模型相同）
        self.api_key = settings.IMAGE_GEN_API_KEY or settings.AI_API_KEY
        self.api_base = settings.IMAGE_GEN_API_BASE or settings.AI_API_BASE
        self.api_path = settings.IMAGE_GEN_API_PATH or "/images/generations"
        
        # 图片生成使用同一个模型
        self.default_model = settings.IMAGE_GEN_MODEL_ID or settings.AI_MODEL_ID
        self.default_format = settings.IMAGE_GEN_DEFAULT_FORMAT
        self.watermark = settings.IMAGE_GEN_WATERMARK
        self.storage_path = settings.AI_GENERATED_PATH
        
        # 从配置获取模型和尺寸列表
        self.available_models = settings.get_available_image_models()
        self.available_sizes = settings.get_available_image_sizes()
        
        logger_service.info(f"图片生成服务初始化: 模型={self.default_model}, 端点={self.api_base}{self.api_path}")
        
        # 确保存储目录存在
        os.makedirs(self.storage_path, exist_ok=True)
    
    @property
    def api_url(self) -> str:
        """完整API URL"""
        return f"{self.api_base}{self.api_path}"
    
    def get_headers(self) -> Dict[str, str]:
        """获取请求头"""
        return {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.api_key}"
        }
    
    def get_available_models(self) -> List[Dict]:
        """获取可用的模型列表"""
        models = []
        for model_id, model_info in self.available_models.items():
            models.append({
                "id": model_id,
                "name": model_info.get("name", model_id),
                "description": model_info.get("description", ""),
                "is_default": model_id == self.default_model
            })
        return models
    
    def get_available_sizes(self) -> List[Dict]:
        """获取可用的尺寸列表"""
        sizes = []
        for ratio, size_info in self.available_sizes.items():
            sizes.append({
                "id": ratio,
                "ratio": ratio,
                "name": size_info.get("name", ratio),
                "width": size_info.get("width", 1024),
                "height": size_info.get("height", 1024),
                "description": size_info.get("description", "")
            })
        return sizes
    
    def _convert_size_param(self, size_ratio: Optional[str] = None,
                            width: Optional[int] = None,
                            height: Optional[int] = None) -> str:
        """
        将尺寸参数转换为豆包API支持的格式

        豆包API支持的格式: "WIDTHxHEIGHT", "2k", "3k"
        要求至少 3686400 像素
        """
        # 如果直接是预设值
        if size_ratio and size_ratio in self.SIZE_PRESETS:
            return self.SIZE_PRESETS[size_ratio]

        # 如果是 WIDTHxHEIGHT 格式，直接返回
        if size_ratio and "x" in size_ratio.lower():
            return size_ratio

        # 如果提供了具体宽高，转换为 WIDTHxHEIGHT
        if width and height:
            pixels = width * height
            if pixels >= 3686400:
                return f"{width}x{height}"
            else:
                # 按比例放大到满足最低像素要求
                scale = (3686400 / pixels) ** 0.5
                new_width = int(width * scale)
                new_height = int(height * scale)
                return f"{new_width}x{new_height}"

        # 默认返回 2048x2048（满足API最低像素要求）
        return "2048x2048"
    
    async def generate_image(
        self,
        prompt: str,
        negative_prompt: Optional[str] = None,
        model_id: Optional[str] = None,
        size_ratio: Optional[str] = None,
        width: Optional[int] = None,
        height: Optional[int] = None,
        output_format: Optional[str] = None,
        seed: Optional[int] = None,
        **kwargs
    ) -> Dict:
        """
        文生图生成
        
        Args:
            prompt: 正向提示词
            negative_prompt: 负向提示词（豆包 API 暂不支持）
            model_id: 模型ID（默认使用 doubao-seed-2-0-mini-260215）
            size_ratio: 尺寸比例（如 "1:1", "16:9", "2K"）
            width: 宽度（会转换为比例）
            height: 高度（会转换为比例）
            output_format: 输出格式（png/jpg/webp）
            seed: 随机种子
            
        Returns:
            {
                'success': bool,
                'image_url': str,
                'local_path': str,
                'model': str,
                'size': str,
                'usage': dict,
                'error': str
            }
        """
        if not self.api_key:
            return {
                'success': False,
                'error': 'API Key 未配置'
            }
        
        try:
            model = model_id or self.default_model
            fmt = output_format or self.default_format
            
            # 转换尺寸参数
            size_param = self._convert_size_param(size_ratio, width, height)
            
            # 构建请求体 - /images/generations API格式
            request_body = {
                "model": model,
                "prompt": prompt,
                "size": size_param,
                "response_format": "url",
                "sequential_image_generation": "disabled",
                "stream": False,
                "watermark": self.watermark
            }
            
            if seed is not None:
                request_body["seed"] = seed
            
            logger_service.info(f"调用豆包图片生成API: model={model}, size={size_param}")
            logger_service.debug(f"请求参数: {request_body}")
            
            # 发送请求
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    self.api_url,
                    headers=self.get_headers(),
                    json=request_body
                )
                
                if response.status_code != 200:
                    error_detail = response.text
                    logger_service.error(f"图片生成API错误 [{response.status_code}]: {error_detail}")
                    return {
                        'success': False,
                        'error': f'API错误: {response.status_code}',
                        'detail': error_detail
                    }
                
                result = response.json()
            
            # 解析响应
            if result and "data" in result and result["data"]:
                image_data = result["data"][0]
                image_url = image_data.get("url")
                image_size = image_data.get("size", "")
                
                # 解析实际尺寸
                actual_width, actual_height = self._parse_image_size(image_size)
                
                if image_url:
                    local_path = await self._download_image(image_url, fmt)
                    
                    logger_service.info(f"图片生成成功: {image_size}")
                    
                    return {
                        'success': True,
                        'image_url': image_url,
                        'local_path': local_path,
                        'model': result.get("model", model),
                        'width': actual_width,
                        'height': actual_height,
                        'size': image_size,
                        'size_ratio': size_ratio or size_param,
                        'usage': result.get("usage", {}),
                        'generation_params': {
                            'prompt': prompt,
                            'negative_prompt': negative_prompt,
                            'seed': seed,
                            'output_format': fmt
                        }
                    }
            
            error_msg = "响应数据为空"
            logger_service.error(f"文生图响应错误: {error_msg}")
            return {
                'success': False,
                'error': error_msg,
                'detail': str(result)
            }
                
        except Exception as e:
            logger_service.error(f"图片生成失败: {e}")
            import traceback
            logger_service.error(traceback.format_exc())
            return {
                'success': False,
                'error': str(e)
            }
    
    def _parse_image_size(self, size_str: str) -> Tuple[int, int]:
        """解析图片尺寸字符串 (如 '3104x1312')"""
        try:
            if "x" in size_str:
                parts = size_str.split("x")
                return int(parts[0]), int(parts[1])
        except:
            pass
        return 0, 0
    
    async def generate_from_photo(
        self,
        photo_path: str,
        prompt: str,
        negative_prompt: Optional[str] = None,
        model_id: Optional[str] = None,
        strength: float = 0.7,
        size_ratio: Optional[str] = None,
        output_format: Optional[str] = None,
        **kwargs
    ) -> Dict:
        """
        图生图 - 基于现有照片生成新图片
        
        注意：豆包 API 的图生图功能需要查看具体文档支持情况
        """
        if not self.api_key:
            return {
                'success': False,
                'error': 'API Key 未配置'
            }
        
        try:
            model = model_id or self.default_model
            fmt = output_format or self.default_format
            
            # 读取源图片并编码为 base64
            with open(photo_path, 'rb') as f:
                image_base64 = base64.b64encode(f.read()).decode('utf-8')
            
            # 转换尺寸参数
            size_param = self._convert_size_param(size_ratio)
            
            logger_service.info(f"调用豆包图生图API: model={model}")
            
            # 构建请求体 - 图生图使用 prompt + image 字段
            request_body = {
                "model": model,
                "prompt": prompt,
                "image": f"data:image/jpeg;base64,{image_base64}",
                "size": size_param,
                "output_format": fmt,
                "watermark": self.watermark,
                "strength": strength
            }
            
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    self.api_url,
                    headers=self.get_headers(),
                    json=request_body
                )
                
                if response.status_code != 200:
                    error_detail = response.text
                    logger_service.error(f"图生图API错误 [{response.status_code}]: {error_detail}")
                    return {
                        'success': False,
                        'error': f'API错误: {response.status_code}',
                        'detail': error_detail
                    }
                
                result = response.json()
            
            if result and "data" in result and result["data"]:
                image_data = result["data"][0]
                image_url = image_data.get("url")
                image_size = image_data.get("size", "")
                actual_width, actual_height = self._parse_image_size(image_size)
                
                if image_url:
                    local_path = await self._download_image(image_url, fmt)
                    
                    logger_service.info(f"图生图成功: {image_size}")
                    
                    return {
                        'success': True,
                        'image_url': image_url,
                        'local_path': local_path,
                        'model': result.get("model", model),
                        'width': actual_width,
                        'height': actual_height,
                        'size': image_size,
                        'size_ratio': size_ratio,
                        'source_photo_path': photo_path,
                        'generation_params': {
                            'prompt': prompt,
                            'negative_prompt': negative_prompt,
                            'strength': strength,
                            'output_format': fmt
                        }
                    }
            
            error_msg = "响应数据为空"
            logger_service.error(f"图生图响应错误: {error_msg}")
            return {
                'success': False,
                'error': error_msg,
                'detail': str(result)
            }
                
        except Exception as e:
            logger_service.error(f"图生图失败: {e}")
            import traceback
            logger_service.error(traceback.format_exc())
            return {
                'success': False,
                'error': str(e)
            }
    
    async def _download_image(self, url: str, fmt: str = "png") -> Optional[str]:
        """下载图片到本地存储"""
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.get(url)
                response.raise_for_status()
                
                filename = f"{uuid.uuid4().hex}.{fmt}"
                local_path = os.path.join(self.storage_path, filename)
                
                with open(local_path, 'wb') as f:
                    f.write(response.content)
                
                logger_service.info(f"图片已下载: {local_path}")
                return local_path
                
        except Exception as e:
            logger_service.error(f"下载图片失败: {e}")
            return None
    
    async def _save_base64_image(self, image_base64: str, fmt: str = "png") -> Optional[str]:
        """保存 base64 图片到本地"""
        try:
            image_data = base64.b64decode(image_base64)
            filename = f"{uuid.uuid4().hex}.{fmt}"
            local_path = os.path.join(self.storage_path, filename)
            
            with open(local_path, 'wb') as f:
                f.write(image_data)
            
            logger_service.info(f"图片已保存: {local_path}")
            return local_path
            
        except Exception as e:
            logger_service.error(f"保存图片失败: {e}")
            return None
    
    def get_current_config(self) -> Dict:
        """获取当前配置"""
        return {
            "default_model": self.default_model,
            "default_format": self.default_format,
            "watermark": self.watermark,
            "api_base": self.api_base,
            "api_path": self.api_path,
            "api_url": self.api_url,
            "has_api_key": bool(self.api_key),
            "storage_path": self.storage_path
        }


# 创建全局实例
image_generation_service = ImageGenerationService()
