"""
人脸检测与聚类服务
使用 face_recognition 库实现人脸识别和聚类功能
"""
import face_recognition
import numpy as np
from typing import List, Dict, Optional, Tuple
from pathlib import Path
from PIL import Image
import logging

logger = logging.getLogger(__name__)


class FaceService:
    """人脸服务类"""
    
    def __init__(
        self, 
        match_threshold: float = 0.6,
        min_face_size: int = 50,
        detection_model: str = 'hog'
    ):
        """
        初始化人脸服务
        
        Args:
            match_threshold: 人脸匹配阈值，默认0.6（越小越严格）
            min_face_size: 最小人脸检测尺寸（像素）
            detection_model: 检测模型，'hog'（快速CPU）或 'cnn'（准确GPU）
        """
        self.match_threshold = match_threshold
        self.min_face_size = min_face_size
        self.detection_model = detection_model
    
    def detect_faces(self, image_path: str) -> Dict:
        """
        检测图片中的人脸
        
        Args:
            image_path: 图片路径
            
        Returns:
            Dict: {
                'faces_detected': int,  # 检测到的人脸数量
                'face_locations': List[Tuple],  # 人脸位置 [(top, right, bottom, left), ...]
                'face_encodings': List[np.ndarray],  # 人脸特征向量
                'face_count': int
            }
        """
        try:
            # 加载图片
            image = face_recognition.load_image_file(image_path)
            
            # 检测人脸位置
            face_locations = face_recognition.face_locations(
                image, 
                model=self.detection_model
            )
            
            # 过滤太小的人脸（可能是误检）
            valid_locations = []
            for loc in face_locations:
                top, right, bottom, left = loc
                width = right - left
                height = bottom - top
                if width >= self.min_face_size and height >= self.min_face_size:
                    valid_locations.append(loc)
            
            # 提取人脸特征编码
            if valid_locations:
                face_encodings = face_recognition.face_encodings(
                    image, 
                    valid_locations
                )
            else:
                face_encodings = []
            
            logger.info(f"人脸检测完成: {image_path}, 检测到 {len(valid_locations)} 张人脸")
            
            return {
                'faces_detected': len(valid_locations),
                'face_locations': valid_locations,
                'face_encodings': face_encodings,
                'face_count': len(valid_locations)
            }
            
        except Exception as e:
            logger.error(f"人脸检测失败: {image_path}, 错误: {e}")
            return {
                'faces_detected': 0,
                'face_locations': [],
                'face_encodings': [],
                'face_count': 0,
                'error': str(e)
            }
    
    def compare_faces(
        self, 
        face_encoding: np.ndarray, 
        known_encodings: List[np.ndarray],
        tolerance: Optional[float] = None
    ) -> Tuple[bool, int]:
        """
        比较人脸特征与已知人脸
        
        Args:
            face_encoding: 待匹配的人脸特征
            known_encodings: 已知人脸特征列表
            tolerance: 匹配阈值（可选，默认使用实例阈值）
            
        Returns:
            Tuple[bool, int]: (是否匹配, 匹配的索引) 如果不匹配，索引为-1
        """
        if tolerance is None:
            tolerance = self.match_threshold
        
        if not known_encodings:
            return False, -1
        
        # 计算距离
        distances = face_recognition.face_distance(known_encodings, face_encoding)
        
        # 找到最小距离
        min_distance_idx = np.argmin(distances)
        min_distance = distances[min_distance_idx]
        
        if min_distance <= tolerance:
            return True, min_distance_idx
        
        return False, -1
    
    def find_best_match(
        self,
        face_encoding: np.ndarray,
        known_clusters: List[Dict]
    ) -> Tuple[bool, Optional[str], float]:
        """
        从已有聚类中找到最佳匹配
        
        Args:
            face_encoding: 待匹配的人脸特征
            known_clusters: 已知聚类列表，每个聚类包含 {'id': str, 'encoding': np.ndarray}
            
        Returns:
            Tuple[bool, Optional[str], float]: (是否匹配, 匹配的聚类ID, 距离)
        """
        if not known_clusters:
            return False, None, 1.0
        
        # 提取所有聚类的特征编码
        cluster_encodings = [c['encoding'] for c in known_clusters]
        distances = face_recognition.face_distance(cluster_encodings, face_encoding)
        
        min_distance_idx = np.argmin(distances)
        min_distance = distances[min_distance_idx]
        
        if min_distance <= self.match_threshold:
            return True, known_clusters[min_distance_idx]['id'], min_distance
        
        return False, None, min_distance
    
    @staticmethod
    def encoding_to_list(encoding: np.ndarray) -> List[float]:
        """将numpy数组编码转换为列表（用于JSON存储）"""
        return encoding.tolist()
    
    @staticmethod
    def list_to_encoding(encoding_list: List[float]) -> np.ndarray:
        """将列表转换回numpy数组编码"""
        return np.array(encoding_list)
    
    @staticmethod
    def compute_average_encoding(encodings: List[np.ndarray]) -> np.ndarray:
        """
        计算多个人脸特征的平均值（用于聚类代表特征）
        
        Args:
            encodings: 人脸特征列表
            
        Returns:
            np.ndarray: 平均特征向量
        """
        if not encodings:
            raise ValueError("编码列表不能为空")
        
        return np.mean(encodings, axis=0)
    
    def cluster_faces(
        self,
        all_face_data: List[Dict]
    ) -> Dict[str, List[str]]:
        """
        对所有人脸进行聚类
        
        Args:
            all_face_data: 所有人脸数据列表，每项包含 {'photo_id': str, 'encodings': List[np.ndarray]}
            
        Returns:
            Dict[str, List[str]]: 聚类结果 {cluster_id: [photo_id1, photo_id2, ...]}
        """
        # 存储每个聚类的代表特征和照片ID
        clusters: Dict[str, Dict] = {}  # {cluster_id: {'encoding': np.ndarray, 'photo_ids': List[str]}}
        cluster_counter = 0
        
        for photo_data in all_face_data:
            photo_id = photo_data['photo_id']
            encodings = photo_data['encodings']
            
            if not encodings:
                continue
            
            # 对照片中的每个人脸进行处理
            for encoding in encodings:
                matched = False
                
                # 尝试匹配已有聚类
                for cluster_id, cluster_data in clusters.items():
                    distance = face_recognition.face_distance(
                        [cluster_data['encoding']], 
                        encoding
                    )[0]
                    
                    if distance <= self.match_threshold:
                        # 匹配成功，添加到聚类
                        if photo_id not in cluster_data['photo_ids']:
                            cluster_data['photo_ids'].append(photo_id)
                            # 更新聚类中心特征
                            cluster_data['encoding'] = self.compute_average_encoding(
                                [cluster_data['encoding'], encoding]
                            )
                        matched = True
                        break
                
                if not matched:
                    # 创建新聚类
                    cluster_id = f"cluster_{cluster_counter}"
                    clusters[cluster_id] = {
                        'encoding': encoding,
                        'photo_ids': [photo_id]
                    }
                    cluster_counter += 1
        
        # 转换结果格式
        result = {}
        for cluster_id, cluster_data in clusters.items():
            result[cluster_id] = cluster_data['photo_ids']
        
        return result


# 延迟初始化，避免循环导入
_face_service_instance = None

def get_face_service():
    """获取人脸服务实例（延迟初始化）"""
    global _face_service_instance
    if _face_service_instance is None:
        from app.config import settings
        _face_service_instance = FaceService(
            match_threshold=settings.FACE_MATCH_THRESHOLD,
            min_face_size=settings.FACE_MIN_SIZE,
            detection_model=settings.FACE_DETECTION_MODEL
        )
    return _face_service_instance


# 全局人脸服务实例（兼容旧代码）
face_service = None

def _init_face_service():
    """初始化人脸服务"""
    global face_service
    face_service = get_face_service()

# 模块加载时初始化
try:
    _init_face_service()
except Exception as e:
    logger.warning(f"人脸服务初始化延迟: {e}")
    # 创建默认实例
    face_service = FaceService()
