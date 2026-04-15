"""
日志管理服务
"""
import os
import json
import logging
from datetime import datetime
from typing import List, Dict, Optional
from app.config import settings


class LoggerService:
    """日志服务类"""
    
    def __init__(self):
        self.log_dir = os.path.join(os.path.dirname(settings.DATABASE_PATH), "logs")
        os.makedirs(self.log_dir, exist_ok=True)
        self.log_file = os.path.join(self.log_dir, "smartalbum.log")
        self._setup_logging()
    
    def _setup_logging(self):
        """配置日志"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(self.log_file, encoding='utf-8'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger("SmartAlbum")
    
    def info(self, message: str, extra: Optional[Dict] = None):
        """记录信息日志"""
        self.logger.info(message, extra=extra or {})
        self._write_log_entry("INFO", message, extra)
    
    def warning(self, message: str, extra: Optional[Dict] = None):
        """记录警告日志"""
        self.logger.warning(message, extra=extra or {})
        self._write_log_entry("WARNING", message, extra)
    
    def error(self, message: str, extra: Optional[Dict] = None):
        """记录错误日志"""
        self.logger.error(message, extra=extra or {})
        self._write_log_entry("ERROR", message, extra)
    
    def debug(self, message: str, extra: Optional[Dict] = None):
        """记录调试日志"""
        self.logger.debug(message, extra=extra or {})
        self._write_log_entry("DEBUG", message, extra)
    
    def _write_log_entry(self, level: str, message: str, extra: Optional[Dict] = None):
        """写入日志条目到JSON文件"""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "level": level,
            "message": message,
            "extra": extra or {}
        }
        
        json_log_file = os.path.join(self.log_dir, "smartalbum.json")
        try:
            with open(json_log_file, 'a', encoding='utf-8') as f:
                f.write(json.dumps(entry, ensure_ascii=False) + '\n')
        except Exception as e:
            print(f"写入日志失败: {e}")
    
    def get_logs(
        self,
        level: Optional[str] = None,
        limit: int = 100,
        offset: int = 0
    ) -> List[Dict]:
        """获取日志列表"""
        json_log_file = os.path.join(self.log_dir, "smartalbum.json")
        
        if not os.path.exists(json_log_file):
            return []
        
        logs = []
        try:
            with open(json_log_file, 'r', encoding='utf-8') as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        if level is None or entry.get('level') == level:
                            logs.append(entry)
                    except json.JSONDecodeError:
                        continue
        except Exception as e:
            print(f"读取日志失败: {e}")
        
        # 按时间倒序
        logs.sort(key=lambda x: x['timestamp'], reverse=True)
        
        return logs[offset:offset + limit]
    
    def get_log_stats(self) -> Dict:
        """获取日志统计"""
        json_log_file = os.path.join(self.log_dir, "smartalbum.json")
        
        if not os.path.exists(json_log_file):
            return {
                "total": 0,
                "info": 0,
                "warning": 0,
                "error": 0,
                "debug": 0
            }
        
        stats = {"total": 0, "info": 0, "warning": 0, "error": 0, "debug": 0}
        
        try:
            with open(json_log_file, 'r', encoding='utf-8') as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        stats["total"] += 1
                        level = entry.get('level', 'INFO').lower()
                        if level in stats:
                            stats[level] += 1
                    except json.JSONDecodeError:
                        continue
        except Exception:
            pass
        
        return stats
    
    def clear_logs(self, before_days: int = 7) -> int:
        """清理旧日志"""
        json_log_file = os.path.join(self.log_dir, "smartalbum.json")
        
        if not os.path.exists(json_log_file):
            return 0
        
        cutoff = datetime.now().timestamp() - (before_days * 24 * 60 * 60)
        kept_logs = []
        removed = 0
        
        try:
            with open(json_log_file, 'r', encoding='utf-8') as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        log_time = datetime.fromisoformat(entry['timestamp']).timestamp()
                        if log_time >= cutoff:
                            kept_logs.append(line)
                        else:
                            removed += 1
                    except (json.JSONDecodeError, KeyError, ValueError):
                        continue
            
            with open(json_log_file, 'w', encoding='utf-8') as f:
                f.writelines(kept_logs)
        except Exception as e:
            print(f"清理日志失败: {e}")
        
        return removed


# 创建全局实例
logger_service = LoggerService()
