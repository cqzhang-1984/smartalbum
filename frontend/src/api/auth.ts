import request from './request'

export interface LoginRequest {
  username: string
  password: string
}

export interface LoginResponse {
  access_token: string
  token_type: string
  username: string
  message: string
}

export interface UserInfo {
  id: string
  username: string
  is_active: boolean
  is_admin: boolean
  created_at: string | null
  last_login_at: string | null
}

export interface ChangePasswordRequest {
  old_password: string
  new_password: string
}

export const authApi = {
  async login(data: LoginRequest): Promise<LoginResponse> {
    // 使用 form-data 格式提交
    const formData = new URLSearchParams()
    formData.append('username', data.username)
    formData.append('password', data.password)
    
    const response = await request.post('/auth/login', formData, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      }
    })
    return response.data
  },

  async getMe(): Promise<UserInfo> {
    const response = await request.get('/auth/me')
    return response.data
  },

  async changePassword(data: ChangePasswordRequest): Promise<{ message: string }> {
    const response = await request.post('/auth/change-password', data)
    return response.data
  },

  async checkAuth(): Promise<{ authenticated: boolean; username: string }> {
    const response = await request.get('/auth/check')
    return response.data
  },

  async logout(): Promise<{ message: string }> {
    const response = await request.post('/auth/logout')
    return response.data
  }
}
