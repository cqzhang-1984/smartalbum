"""
AI服务 - 多模态识别和向量化（豆包API）
"""
import os
import base64
import httpx
import json
import io
from typing import Dict, Optional, List
from datetime import datetime
from app.config import settings
from app.services.logger_service import logger_service
from PIL import Image

# 豆包SDK
try:
    from volcenginesdkarkruntime import Ark, AsyncArk
    DOUBAO_SDK_AVAILABLE = True
except ImportError:
    DOUBAO_SDK_AVAILABLE = False
    logger_service.warning("volcenginesdkarkruntime 未安装，将使用HTTP方式调用")


class AIService:
    """AI服务类 - 豆包多模态API"""

    # 深度分析专业prompt
    DEEP_ANALYSIS_PROMPT = """你是一名世界顶级的人像摄影师、视觉美学评论家与影像技术专家。请对这张人像摄影作品进行极其专业、深入的全面分析。

请严格按照以下**8个模块**的结构输出分析报告，使用**Markdown格式**，每个模块用二级标题（##）分隔。请控制总篇幅在2000-3000字之间，语言精炼专业。

---

## 一、基本信息与风格定位
- **摄影风格**：判断照片属于哪种摄影风格（如：日系清新、欧美时尚、法式复古、暗黑哥特、纪实人文、棚拍商业、街拍等），并简要说明判断依据。
- **拍摄类型**：人像写真、时尚大片、证件照、情绪人像、概念创意、旅拍等。
- **整体气质**：用2-3个精准的形容词概括照片传达的气质（如：慵懒清冷、热烈奔放、温柔恬静、忧郁深沉等）。

## 二、构图与机位分析
- **构图方式**：识别构图技法（三分法、黄金分割、居中对称、对角线构图、框架构图、引导线构图、留白构图等），说明主体在画面中的位置安排。
- **机位与视角**：判断拍摄角度（平视、俯拍、仰拍、鸟瞰等）和拍摄距离（特写/脸部、半身、七分身、全身、远景等），分析机位选择对画面表达的影响。
- **画面层次**：分析前景、中景、背景的层次关系，是否有景深分离效果。

## 三、光影分析
- **光源类型**：自然光（日光、窗光、逆光、侧光等）还是人造光（闪光灯、持续光、柔光箱等），或混合光源。
- **光影特征**：识别具体光影模式（如伦勃朗光、蝴蝶光、环形光、分割光、边缘光/轮廓光等），光质（硬光/柔光），光比。
- **光影氛围**：分析光影营造的视觉氛围和情绪效果（如：高调明亮、低调神秘、戏剧性明暗对比等）。

## 四、相机参数推测
- 根据画面特征推测关键拍摄参数：
  - **等效焦距**：根据畸变和视角推测焦距范围（如24mm广角、50mm标准、85mm人像、135mm压缩等）。
  - **光圈**：根据景深和虚化程度推测光圈值（如f/1.4、f/2.8、f/5.6等）。
  - **快门速度**：根据动态模糊或冻结程度推测（如1/2000s冻结、1/60s略有模糊等）。
  - **ISO**：根据画质噪点水平推测ISO范围。
  - **白平衡**：根据画面色调偏差推测白平衡设置倾向。
- 注：如果无法准确推测，请给出合理范围并说明推测依据。

## 五、色彩与调色分析
- **主色调**：识别画面的主要色彩（如暖调/冷调、低饱和/高饱和），列出3-5个主要色彩。
- **色调风格**：判断调色风格（如：胶片色、日系低对比、电影感青橙色调、复古褪色、黑白等），分析色调与画面情绪的配合。
- **色彩搭配**：分析色彩搭配是否和谐，是否运用了互补色、类似色、单色等配色方案。
- **肤色表现**：评价肤色调色处理是否自然、是否有特殊色调倾向。

## 六、模特表现与造型
- **表情与情绪**：分析模特的面部表情和传达的情绪，眼神的朝向和力度，嘴部的微表情等。
- **姿态与肢体**：分析身体姿态（站姿、坐姿、躺姿、动态姿势等），手部动作，头部角度等。
- **妆造与穿搭**：分析妆容风格（自然妆、浓妆、特效妆等）、发型处理、服装搭配、配饰运用等。
- **整体表现力**：综合评价模特在画面中的表现力和感染力。

## 七、场景与道具
- **拍摄场景**：描述拍摄环境（室内/户外、具体场景类型），环境对主体的衬托作用。
- **道具运用**：如有道具（花束、帽子、乐器、食物等），分析道具在画面中的作用和意义。
- **环境氛围**：分析场景环境与人物气质、画面风格的协调性。

## 八、综合评价与优化建议
- **综合评分**：给出1-10分的综合评分，从以下维度分别打分：
  - 构图：X/10
  - 光影：X/10
  - 色彩：X/10
  - 模特表现：X/10
  - 整体氛围：X/10
- **核心亮点**：列出2-3个这张照片最突出的优点。
- **改进建议**：如果需要提升，给出2-3条专业、可操作的改进建议（涉及构图调整、光影优化、后期调色方向等）。
- **适合用途**：建议这张照片适合用于什么场景（如：社交媒体头像、写真集、时尚杂志、商业广告等）。

---

注意事项：
1. 只输出Markdown格式的分析报告，不要包含任何开场白或结束语。
2. 每个模块的分析要具体、专业、有据可依，避免空泛描述。
3. 如果某些信息无法从画面中判断，请明确标注"无法判断"并给出合理推测。
4. 语言风格：专业但不晦涩，优雅但不浮夸。"""
    
    def __init__(self):
        self.model_name = settings.AI_MODEL_NAME
        self.model_id = settings.AI_MODEL_ID
        self.api_key = settings.get_ai_api_key()
        self.api_base = settings.AI_API_BASE
        self.api_path = settings.AI_API_PATH
        logger_service.info(f"AI服务初始化: {self.model_name} ({self.model_id})")
        
        # 初始化豆包客户端
        if DOUBAO_SDK_AVAILABLE:
            self.async_client = AsyncArk(
                base_url=self.api_base,
                api_key=self.api_key
            )
        else:
            self.async_client = None
    
    def encode_image_to_base64(self, image_path: str, max_size_mb: float = 8.0, max_pixels: int = 35000000) -> str:
        """
        将图片编码为base64，自动压缩以符合API限制
        
        Args:
            image_path: 图片路径
            max_size_mb: 最大文件大小限制（MiB），默认8MB（API限制10MB，留有余量）
            max_pixels: 最大像素数限制，默认3500万（API限制3600万，留有余量）
        
        Returns:
            base64编码的图片字符串
        """
        max_bytes = int(max_size_mb * 1024 * 1024)
        
        # 打开图片
        img = Image.open(image_path)
        
        # 转换为 RGB 模式（去除 alpha 通道）
        if img.mode in ('RGBA', 'P', 'LA'):
            img = img.convert('RGB')
        
        original_pixels = img.width * img.height
        original_size = os.path.getsize(image_path)
        
        # 计算需要的尺寸缩放比例（优先处理像素限制）
        pixel_scale = 1.0
        if original_pixels > max_pixels:
            pixel_scale = (max_pixels / original_pixels) ** 0.5  # 开平方得到边长缩放比例
            logger_service.info(f"像素超限 ({original_pixels:,} > {max_pixels:,})，缩放比例: {pixel_scale:.2%}")
        
        # 如果需要缩放尺寸，先缩放
        if pixel_scale < 1.0:
            new_width = int(img.width * pixel_scale)
            new_height = int(img.height * pixel_scale)
            img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # 检查是否需要进一步压缩（文件大小）
        quality = 85
        scale = 1.0
        output = io.BytesIO()
        
        # 先保存一次检查大小
        img.save(output, format='JPEG', quality=quality, optimize=True)
        
        # 逐步降低质量直到满足大小限制
        while quality >= 30 and output.tell() > max_bytes:
            quality -= 5
            output.seek(0)
            output.truncate()
            img.save(output, format='JPEG', quality=quality, optimize=True)
        
        # 如果质量降低还不够，继续缩小尺寸
        if output.tell() > max_bytes:
            scale = 0.9
            while scale >= 0.1 and output.tell() > max_bytes:
                output.seek(0)
                output.truncate()
                new_width = int(img.width * scale)
                new_height = int(img.height * scale)
                resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
                resized.save(output, format='JPEG', quality=quality, optimize=True)
                scale -= 0.1
        
        output.seek(0)
        final_pixels = img.width * img.height * (scale if scale < 1.0 else 1.0)
        compressed_size = output.tell() / 1024 / 1024
        logger_service.info(f"图片压缩完成: {compressed_size:.1f} MiB, 像素: {int(final_pixels):,}, 质量={quality}%, 尺寸缩放={scale:.0%}")
        
        return base64.b64encode(output.read()).decode('utf-8')
    
    async def analyze_image(self, image_path: str, image_url: str = None) -> Dict:
        """
        分析图像，提取结构化标签
        
        Args:
            image_path: 本地图片路径
            image_url: 图片URL（可选，如COS签名URL）
        
        Returns:
            {
                'subject_emotion': str,
                'pose': str,
                'clothing_style': str,
                'lighting': str,
                'environment': str,
                'overall_description': str,
                'aesthetic_score': float
            }
        """
        try:
            system_prompt = """你是一名世界顶级的人像摄影师、评论家与视觉美学专家，精通摄影史、光影构图学、时尚穿搭以及人物心理学。请分析这张照片，并输出JSON格式的分析结果。
请包含以下字段：
- subject_emotion: 主体情绪（如：慵懒、清冷、热烈、忧郁、恬静等）
- pose: 姿态（如：躺姿、站姿、坐姿、回眸、抱膝等）
- clothing_style: 穿搭风格（如：JK、纯欲、法式复古、暗黑、甜美等）
- lighting: 光影特征（如：伦勃朗光、逆光、高调、暗调、侧光等）
- environment: 环境场景（如：室内、户外、窗边、海边等）
- overall_description: 一段详细的画面描述文字（100-200字）
- aesthetic_score: 美学评分（1-10分，考虑构图、光影、情绪表达等）

只输出JSON，不要包含其他文字。"""
            
            # 准备图片URL（优先使用本地文件压缩，避免URL指向大文件超限）
            # 本地文件存在时，使用压缩后的base64（确保不超过API限制）
            # 只有本地文件不存在时，才使用传入的URL（如COS签名URL）
            if image_path and os.path.exists(image_path):
                image_base64 = self.encode_image_to_base64(image_path)
                img_url = f"data:image/jpeg;base64,{image_base64}"
                logger_service.info(f"使用本地文件（已压缩）: {image_path}")
            elif image_url:
                img_url = image_url
                logger_service.warning(f"本地文件不存在，使用URL（可能超限）: {image_url[:50]}...")
            else:
                raise ValueError("必须提供 image_path 或 image_url")
            
            logger_service.info(f"调用豆包AI API: {self.model_id}")
            
            if self.async_client:
                # 使用豆包SDK
                response = await self.async_client.responses.create(
                    model=self.model_id,
                    input=[
                        {
                            "role": "system",
                            "content": [
                                {
                                    "type": "input_text",
                                    "text": system_prompt
                                }
                            ]
                        },
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "input_image",
                                    "image_url": img_url
                                },
                                {
                                    "type": "input_text",
                                    "text": "请分析这张照片"
                                }
                            ]
                        }
                    ]
                )
                # 正确提取Response对象中的文本内容
                if hasattr(response, 'output_text') and response.output_text:
                    result_text = response.output_text
                elif hasattr(response, 'output') and response.output:
                    # 从output列表中提取文本
                    for item in response.output:
                        if hasattr(item, 'content') and item.content:
                            for content in item.content:
                                if hasattr(content, 'text') and content.text:
                                    result_text = content.text
                                    break
                            else:
                                continue
                            break
                    else:
                        # 如果没有找到text，尝试其他方式
                        result_text = str(response.output) if response.output else ""
                else:
                    result_text = ""
            else:
                # 使用HTTP方式（兼容格式）
                result_text = await self._call_via_http(img_url, system_prompt)
            
            # 解析响应
            try:
                if '```json' in result_text:
                    result_text = result_text.split('```json')[1].split('```')[0]
                elif '```' in result_text:
                    result_text = result_text.split('```')[1].split('```')[0]
                
                parsed = json.loads(result_text.strip())
                logger_service.info(f"AI分析完成: {image_path}")
                return self._validate_result(parsed)
            except json.JSONDecodeError:
                logger_service.error(f"JSON解析失败: {result_text[:200]}")
                return self._get_default_result()
                
        except Exception as e:
            logger_service.error(f"AI分析失败: {e}")
            import traceback
            logger_service.error(traceback.format_exc())
            return self._get_default_result()
    
    async def deep_analyze_image(self, image_path: str, image_url: str = None) -> Dict:
        """
        深度分析图像，返回Markdown格式的专业摄影分析报告
        
        Args:
            image_path: 本地图片路径
            image_url: 图片URL（可选，如COS签名URL）
        
        Returns:
            {
                'deep_analysis': str,  # Markdown格式的分析报告
                'deep_analysis_time': str  # 分析时间 ISO格式
            }
        """
        try:
            # 准备图片URL
            if image_path and os.path.exists(image_path):
                image_base64 = self.encode_image_to_base64(image_path)
                img_url = f"data:image/jpeg;base64,{image_base64}"
                logger_service.info(f"深度分析 - 使用本地文件（已压缩）: {image_path}")
            elif image_url:
                img_url = image_url
                logger_service.info(f"深度分析 - 使用URL: {image_url[:50]}...")
            else:
                raise ValueError("必须提供 image_path 或 image_url")
            
            logger_service.info(f"调用豆包AI API（深度分析）: {self.model_id}")
            
            if self.async_client:
                response = await self.async_client.responses.create(
                    model=self.model_id,
                    input=[
                        {
                            "role": "system",
                            "content": [
                                {
                                    "type": "input_text",
                                    "text": self.DEEP_ANALYSIS_PROMPT
                                }
                            ]
                        },
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "input_image",
                                    "image_url": img_url
                                },
                                {
                                    "type": "input_text",
                                    "text": "请对这张人像照片进行专业深度分析"
                                }
                            ]
                        }
                    ]
                )
                result_text = ""
                if hasattr(response, 'output_text') and response.output_text:
                    result_text = response.output_text
                elif hasattr(response, 'output') and response.output:
                    for item in response.output:
                        if hasattr(item, 'content') and item.content:
                            for content in item.content:
                                if hasattr(content, 'text') and content.text:
                                    result_text = content.text
                                    break
                            else:
                                continue
                            break
                    else:
                        result_text = str(response.output) if response.output else ""
                else:
                    result_text = ""
            else:
                result_text = await self._call_via_http(img_url, self.DEEP_ANALYSIS_PROMPT, timeout=300.0)
            
            if not result_text:
                logger_service.error("深度分析返回空结果")
                return {'deep_analysis': None, 'deep_analysis_time': None}
            
            # 清理可能的Markdown代码块包裹
            result_text = result_text.strip()
            if result_text.startswith('```markdown'):
                result_text = result_text[len('```markdown'):].strip()
            if result_text.startswith('```'):
                result_text = result_text[3:].strip()
            if result_text.endswith('```'):
                result_text = result_text[:-3].strip()
            
            analysis_time = datetime.now().isoformat()
            logger_service.info(f"AI深度分析完成: {image_path}, 报告长度: {len(result_text)} 字符")
            
            return {
                'deep_analysis': result_text,
                'deep_analysis_time': analysis_time
            }
            
        except Exception as e:
            logger_service.error(f"AI深度分析失败: {e}")
            import traceback
            logger_service.error(traceback.format_exc())
            return {'deep_analysis': None, 'deep_analysis_time': None}

    async def _call_via_http(self, image_url: str, system_prompt: str, timeout: float = 120.0) -> str:
        """通过HTTP方式调用豆包API"""
        url = f"{self.api_base}{self.api_path}"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        # 豆包 responses API 格式
        payload = {
            "model": self.model_id,
            "input": [
                {
                    "role": "system",
                    "content": [
                        {
                            "type": "input_text",
                            "text": system_prompt
                        }
                    ]
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_image",
                            "image_url": image_url
                        },
                        {
                            "type": "input_text",
                            "text": "请分析这张照片"
                        }
                    ]
                }
            ]
        }
        
        async with httpx.AsyncClient(timeout=timeout, proxy=None) as client:
            response = await client.post(url, json=payload, headers=headers)
            if response.status_code != 200:
                logger_service.error(f"API调用失败: {response.status_code} - {response.text}")
                response.raise_for_status()
            result = response.json()
        
        logger_service.info(f"API响应: {json.dumps(result, ensure_ascii=False)[:2000]}...")
        
        # 解析豆包 responses API 响应格式
        # 格式: {"output": [{"type": "reasoning", ...}, {"type": "message", "content": [{"text": "..."}]}]}
        if "output" in result:
            for item in result["output"]:
                # 处理 message 类型的输出（最终结果）
                if item.get("type") == "message" and "content" in item:
                    for content in item["content"]:
                        if content.get("type") == "output_text":
                            return content.get("text", "")
                        elif "text" in content:
                            return content["text"]
                # 处理 reasoning 类型的输出（推理过程）
                elif item.get("type") == "reasoning" and "summary" in item:
                    # reasoning 包含推理过程，跳过，继续找 message
                    continue
                # 尝试直接获取 content 中的 text
                if "content" in item:
                    if isinstance(item["content"], str):
                        return item["content"]
                    for content in item["content"]:
                        if "text" in content:
                            return content["text"]
        
        # 兼容其他格式
        if "output_text" in result:
            return result["output_text"]
        elif "choices" in result:
            return result["choices"][0].get("message", {}).get("content", "")
        else:
            logger_service.error(f"无法解析响应格式: {result}")
            return ""
    
    def _validate_result(self, result: Dict) -> Dict:
        """验证并补全结果字段"""
        required_fields = [
            'subject_emotion', 'pose', 'clothing_style',
            'lighting', 'environment', 'overall_description',
            'aesthetic_score'
        ]
        for field in required_fields:
            if field not in result:
                result[field] = None
        return result
    
    def _get_default_result(self) -> Dict:
        """返回默认结果"""
        return {
            'subject_emotion': None,
            'pose': None,
            'clothing_style': None,
            'lighting': None,
            'environment': None,
            'overall_description': None,
            'aesthetic_score': None
        }


class EmbeddingService:
    """文本向量化服务"""
    
    def __init__(self):
        self.model_name = settings.EMBEDDING_MODEL_NAME
        self.model_id = settings.EMBEDDING_MODEL_ID
        self.api_key = settings.get_embedding_api_key()
        self.api_base = settings.EMBEDDING_API_BASE
        self.api_path = settings.EMBEDDING_API_PATH
        logger_service.info(f"Embedding服务初始化: {self.model_name} ({self.model_id})")
    
    async def generate_embedding(self, text: str) -> List[float]:
        """
        生成文本的向量嵌入
        
        Args:
            text: 待向量化的文本
            
        Returns:
            向量列表
        """
        try:
            # 构建API请求
            url = f"{self.api_base}{self.api_path}"
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            payload = {
                "model": self.model_id,
                "input": text
            }
            
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(url, json=payload, headers=headers)
                response.raise_for_status()
                result = response.json()
            
            embedding = result.get("data", [{}])[0].get("embedding", [])
            return embedding
            
        except Exception as e:
            logger_service.error(f"生成向量失败: {e}")
            return []
    
    async def generate_embeddings_batch(self, texts: List[str]) -> List[List[float]]:
        """
        批量生成向量嵌入
        
        Args:
            texts: 文本列表
            
        Returns:
            向量列表的列表
        """
        try:
            url = f"{self.api_base}{self.api_path}"
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            payload = {
                "model": self.model_id,
                "input": texts
            }
            
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(url, json=payload, headers=headers)
                response.raise_for_status()
                result = response.json()
            
            embeddings = [item.get("embedding", []) for item in result.get("data", [])]
            return embeddings
            
        except Exception as e:
            logger_service.error(f"批量生成向量失败: {e}")
            return []


# 创建全局实例
ai_service = AIService()
embedding_service = EmbeddingService()
