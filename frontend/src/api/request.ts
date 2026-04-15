import axios from 'axios'
import { useAuthStore } from '../stores/authStore'

// 创建 axios 实例
const request = axios.create({
  baseURL: '/api',
  timeout: 30000,
})

// 请求拦截器 - 添加 token
request.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('access_token')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// 响应拦截器 - 处理 401 错误
request.interceptors.response.use(
  (response) => {
    return response
  },
  (error) => {
    if (error.response?.status === 401) {
      // Token 过期或无效，清除登录状态并跳转到登录页
      localStorage.removeItem('access_token')
      const authStore = useAuthStore()
      authStore.logout()
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

export default request
