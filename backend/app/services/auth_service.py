from datetime import datetime
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.user import User
from app.core.security import verify_password, get_password_hash
from app.config import settings


class AuthService:
    """认证服务"""
    
    @staticmethod
    async def authenticate_user(db: AsyncSession, username: str, password: str) -> Optional[User]:
        """
        验证用户登录
        
        Args:
            db: 数据库会话
            username: 用户名
            password: 明文密码
            
        Returns:
            验证成功返回用户对象，失败返回None
        """
        result = await db.execute(select(User).where(User.username == username))
        user = result.scalar_one_or_none()
        
        if not user:
            return None
        
        if not verify_password(password, user.hashed_password):
            return None
        
        # 更新最后登录时间
        user.last_login_at = datetime.utcnow()
        await db.commit()
        
        return user
    
    @staticmethod
    async def change_password(db: AsyncSession, user: User, old_password: str, new_password: str) -> bool:
        """
        修改用户密码
        
        Args:
            db: 数据库会话
            user: 用户对象
            old_password: 旧密码
            new_password: 新密码
            
        Returns:
            修改成功返回True，失败返回False
        """
        # 验证旧密码
        if not verify_password(old_password, user.hashed_password):
            return False
        
        # 更新密码
        user.hashed_password = get_password_hash(new_password)
        await db.commit()
        
        return True
    
    @staticmethod
    async def get_user_by_username(db: AsyncSession, username: str) -> Optional[User]:
        """
        根据用户名获取用户
        
        Args:
            db: 数据库会话
            username: 用户名
            
        Returns:
            用户对象或None
        """
        result = await db.execute(select(User).where(User.username == username))
        return result.scalar_one_or_none()
    
    @staticmethod
    async def init_default_user(db: AsyncSession) -> Optional[User]:
        """
        初始化默认用户（如果不存在）
        
        Args:
            db: 数据库会话
            
        Returns:
            用户对象或None（如果未配置默认密码）
        """
        result = await db.execute(select(User).where(User.username == settings.DEFAULT_USERNAME))
        user = result.scalar_one_or_none()
        
        if not user:
            # 检查是否配置了默认密码
            if not settings.DEFAULT_PASSWORD:
                if settings.IS_PRODUCTION:
                    print(f"[警告] 未设置 DEFAULT_PASSWORD 环境变量，跳过创建默认用户")
                    return None
                else:
                    # 开发环境生成随机密码
                    import secrets
                    temp_password = secrets.token_urlsafe(12)
                    print(f"[开发环境] 默认用户密码未设置，已生成随机密码: {temp_password}")
                    password_to_use = temp_password
            else:
                password_to_use = settings.DEFAULT_PASSWORD
                # 生产环境检查密码强度
                if settings.IS_PRODUCTION:
                    if len(password_to_use) < 8:
                        raise ValueError("生产环境 DEFAULT_PASSWORD 长度必须至少8位")
            
            # 创建默认用户
            user = User(
                username=settings.DEFAULT_USERNAME,
                hashed_password=get_password_hash(password_to_use),
                is_active=True,
                is_admin=True
            )
            db.add(user)
            await db.commit()
            await db.refresh(user)
            print(f"默认用户已创建: {settings.DEFAULT_USERNAME}")
        
        return user
