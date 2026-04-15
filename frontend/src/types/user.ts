/**
 * 用户相关类型定义
 */

// 用户信息
export interface User {
  id: string
  username: string
  is_admin: boolean
  is_active: boolean
  last_login_at?: string
  created_at: string
}

// 登录请求
export interface LoginRequest {
  username: string
  password: string
}

// 登录响应
export interface LoginResponse {
  access_token: string
  token_type: string
  user: User
}

// 修改密码请求
export interface ChangePasswordRequest {
  old_password: string
  new_password: string
}

// 系统状态
export interface SystemStatus {
  version: string
  environment: string
  database_connected: boolean
  redis_connected: boolean
  cos_enabled: boolean
  total_photos: number
  storage_used: number
}
