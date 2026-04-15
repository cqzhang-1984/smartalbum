from datetime import timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models.user import User
from app.services.auth_service import AuthService
from app.core.security import create_access_token, decode_token, get_password_hash
from app.config import settings

router = APIRouter()

# OAuth2 scheme
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


# ==================== 请求/响应模型 ====================

class LoginRequest(BaseModel):
    """登录请求"""
    username: str
    password: str


class LoginResponse(BaseModel):
    """登录响应"""
    access_token: str
    token_type: str = "bearer"
    username: str
    message: str = "登录成功"


class UserResponse(BaseModel):
    """用户信息响应"""
    id: str
    username: str
    is_active: bool
    is_admin: bool
    created_at: Optional[str]
    last_login_at: Optional[str]


class ChangePasswordRequest(BaseModel):
    """修改密码请求"""
    old_password: str
    new_password: str


class ChangePasswordResponse(BaseModel):
    """修改密码响应"""
    message: str


class PasswordResetResponse(BaseModel):
    """密码重置响应"""
    message: str
    default_password: str


# ==================== 依赖函数 ====================

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    获取当前登录用户
    
    Args:
        token: JWT令牌
        db: 数据库会话
        
    Returns:
        用户对象
        
    Raises:
        HTTPException: 认证失败时抛出401错误
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="无效的认证凭据",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    payload = decode_token(token)
    if payload is None:
        raise credentials_exception
    
    username: str = payload.get("sub")
    if username is None:
        raise credentials_exception
    
    user = await AuthService.get_user_by_username(db, username)
    if user is None:
        raise credentials_exception
    
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="用户已被禁用"
        )
    
    return user


async def get_current_active_user(
    current_user: User = Depends(get_current_user)
) -> User:
    """
    获取当前活跃用户（额外检查是否活跃）
    
    Args:
        current_user: 当前用户
        
    Returns:
        用户对象
    """
    if not current_user.is_active:
        raise HTTPException(status_code=400, detail="用户未激活")
    return current_user


# ==================== API 路由 ====================

@router.post("/login", response_model=LoginResponse)
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db)
):
    """
    用户登录
    
    使用表单提交：username 和 password
    """
    user = await AuthService.authenticate_user(db, form_data.username, form_data.password)
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="用户名或密码错误",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = create_access_token(data={"sub": user.username})
    
    return LoginResponse(
        access_token=access_token,
        username=user.username
    )


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_active_user)):
    """获取当前登录用户信息"""
    return UserResponse(
        id=current_user.id,
        username=current_user.username,
        is_active=current_user.is_active,
        is_admin=current_user.is_admin,
        created_at=current_user.created_at.isoformat() if current_user.created_at else None,
        last_login_at=current_user.last_login_at.isoformat() if current_user.last_login_at else None
    )


@router.post("/change-password", response_model=ChangePasswordResponse)
async def change_password(
    request: ChangePasswordRequest,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db)
):
    """修改密码"""
    success = await AuthService.change_password(
        db, current_user, request.old_password, request.new_password
    )
    
    if not success:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="旧密码错误"
        )
    
    return ChangePasswordResponse(message="密码修改成功")


@router.post("/reset-password", response_model=PasswordResetResponse)
async def reset_password(
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db)
):
    """
    重置密码为默认密码
    
    注意：仅用于忘记密码时的紧急恢复，重置后请立即修改密码
    """
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="只有管理员可以重置密码"
        )
    
    # 重置为默认密码
    current_user.hashed_password = get_password_hash(settings.DEFAULT_PASSWORD)
    await db.commit()
    
    return PasswordResetResponse(
        message="密码已重置为默认密码，请登录后立即修改",
        default_password=settings.DEFAULT_PASSWORD
    )


@router.post("/logout")
async def logout():
    """
    用户登出
    
    注意：JWT令牌无法主动失效，客户端需要清除本地存储的token
    """
    return {"message": "登出成功，请清除本地token"}


@router.get("/check")
async def check_auth(current_user: User = Depends(get_current_active_user)):
    """检查认证状态"""
    return {
        "authenticated": True,
        "username": current_user.username
    }
