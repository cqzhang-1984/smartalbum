"""
EXIF信息解析服务
"""
import piexif
from datetime import datetime
from typing import Optional, Dict
from PIL import Image


class EXIFService:
    """EXIF解析服务类"""
    
    @staticmethod
    def extract_exif(image_path: str) -> Dict:
        """
        提取EXIF信息
        返回: {
            'shot_time': datetime,
            'camera_model': str,
            'lens_model': str,
            'focal_length': float,
            'aperture': float,
            'shutter_speed': str,
            'iso': int
        }
        """
        exif_data = {}
        
        try:
            # 尝试使用piexif读取
            try:
                exif_dict = piexif.load(image_path)
                if exif_dict:
                    exif_data = EXIFService._parse_piexif(exif_dict)
            except:
                # 如果piexif失败，尝试使用PIL
                with Image.open(image_path) as img:
                    if hasattr(img, '_getexif'):
                        exif_info = img._getexif()
                        if exif_info:
                            exif_data = EXIFService._parse_pil_exif(exif_info)
        
        except Exception as e:
            print(f"提取EXIF信息失败: {e}")
        
        return exif_data
    
    @staticmethod
    def _parse_piexif(exif_dict: dict) -> Dict:
        """解析piexif格式的EXIF数据"""
        exif_data = {}
        
        # 0th IFD (主图像属性)
        zeroth = exif_dict.get('0th', {})
        
        # 相机型号
        if piexif.ImageIFD.Model in zeroth:
            exif_data['camera_model'] = zeroth[piexif.ImageIFD.Model].decode('utf-8', errors='ignore')
        
        # 镜头型号
        if piexif.ImageIFD.LensModel in zeroth:
            exif_data['lens_model'] = zeroth[piexif.ImageIFD.LensModel].decode('utf-8', errors='ignore')
        
        # Exif IFD
        exif = exif_dict.get('Exif', {})
        
        # 拍摄时间
        if piexif.ExifIFD.DateTimeOriginal in exif:
            date_str = exif[piexif.ExifIFD.DateTimeOriginal].decode('utf-8', errors='ignore')
            exif_data['shot_time'] = EXIFService._parse_datetime(date_str)
        
        # 光圈
        if piexif.ExifIFD.FNumber in exif:
            fnumber = exif[piexif.ExifIFD.FNumber]
            exif_data['aperture'] = fnumber[0] / fnumber[1] if isinstance(fnumber, tuple) else fnumber
        
        # 快门速度
        if piexif.ExifIFD.ExposureTime in exif:
            exposure = exif[piexif.ExifIFD.ExposureTime]
            if isinstance(exposure, tuple):
                if exposure[1] >= exposure[0]:
                    exif_data['shutter_speed'] = f"1/{int(exposure[1] / exposure[0])}"
                else:
                    exif_data['shutter_speed'] = f"{exposure[0] / exposure[1]:.1f}s"
            else:
                exif_data['shutter_speed'] = f"{exposure}s"
        
        # ISO
        if piexif.ExifIFD.ISOSpeedRatings in exif:
            exif_data['iso'] = exif[piexif.ExifIFD.ISOSpeedRatings]
        
        # 焦距
        if piexif.ExifIFD.FocalLength in exif:
            focal = exif[piexif.ExifIFD.FocalLength]
            exif_data['focal_length'] = focal[0] / focal[1] if isinstance(focal, tuple) else focal
        
        return exif_data
    
    @staticmethod
    def _parse_pil_exif(exif_info: dict) -> Dict:
        """解析PIL格式的EXIF数据"""
        from PIL.ExifTags import TAGS
        
        exif_data = {}
        
        for tag_id, value in exif_info.items():
            tag = TAGS.get(tag_id, tag_id)
            
            if tag == 'DateTimeOriginal':
                exif_data['shot_time'] = EXIFService._parse_datetime(str(value))
            elif tag == 'Model':
                exif_data['camera_model'] = str(value)
            elif tag == 'LensModel':
                exif_data['lens_model'] = str(value)
            elif tag == 'FocalLength':
                if isinstance(value, tuple):
                    exif_data['focal_length'] = value[0] / value[1]
                else:
                    exif_data['focal_length'] = float(value)
            elif tag == 'FNumber':
                if isinstance(value, tuple):
                    exif_data['aperture'] = value[0] / value[1]
                else:
                    exif_data['aperture'] = float(value)
            elif tag == 'ExposureTime':
                if isinstance(value, tuple):
                    if value[1] >= value[0]:
                        exif_data['shutter_speed'] = f"1/{int(value[1] / value[0])}"
                    else:
                        exif_data['shutter_speed'] = f"{value[0] / value[1]:.1f}s"
                else:
                    exif_data['shutter_speed'] = str(value)
            elif tag == 'ISOSpeedRatings':
                exif_data['iso'] = int(value)
        
        return exif_data
    
    @staticmethod
    def _parse_datetime(date_str: str) -> Optional[datetime]:
        """解析日期时间字符串"""
        try:
            # 常见格式: "2024:01:15 14:30:25"
            return datetime.strptime(date_str, "%Y:%m:%d %H:%M:%S")
        except:
            try:
                # 尝试其他格式
                return datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
            except:
                return None
    
    @staticmethod
    def get_camera_info(image_path: str) -> Optional[str]:
        """获取相机信息（简化版）"""
        exif_data = EXIFService.extract_exif(image_path)
        if exif_data.get('camera_model'):
            return exif_data['camera_model']
        return None
