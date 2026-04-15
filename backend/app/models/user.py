from sqlalchemy import Column, String, DateTime, Boolean
from datetime import datetime
import uuid
from app.database import Base


def generate_uuid():
    """生成UUID"""
    return str(uuid.uuid4())


class User(Base):
    """用户模型 - 单用户系统"""
    __tablename__ = "users"
    
    id = Column(String(36), primary_key=True, default=generate_uuid)
    username = Column(String(50), unique=True, nullable=False, index=True)
    hashed_password = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    is_admin = Column(Boolean, default=True, nullable=False)  # 单用户系统，默认为管理员
    
    # 时间戳
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    last_login_at = Column(DateTime, nullable=True)
    
    def __repr__(self):
        return f"<User(id={self.id}, username={self.username})>"
