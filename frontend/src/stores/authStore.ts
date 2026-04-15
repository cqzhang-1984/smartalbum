import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authApi, type UserInfo } from '../api/auth'

export const useAuthStore = defineStore('auth', () => {
  // State
  const token = ref<string>(localStorage.getItem('access_token') || '')
  const user = ref<UserInfo | null>(null)
  const isLoading = ref(false)
  const error = ref<string | null>(null)

  // Getters
  const isAuthenticated = computed(() => !!token.value && !!user.value)
  const username = computed(() => user.value?.username || '')

  // Actions
  async function login(username: string, password: string): Promise<boolean> {
    isLoading.value = true
    error.value = null

    try {
      const response = await authApi.login({ username, password })
      token.value = response.access_token
      localStorage.setItem('access_token', response.access_token)
      
      // 获取用户信息
      await fetchUserInfo()
      return true
    } catch (err: any) {
      error.value = err.response?.data?.detail || '登录失败'
      return false
    } finally {
      isLoading.value = false
    }
  }

  async function fetchUserInfo(): Promise<boolean> {
    if (!token.value) return false

    try {
      const userInfo = await authApi.getMe()
      user.value = userInfo
      return true
    } catch (err) {
      // 获取用户信息失败，清除 token
      logout()
      return false
    }
  }

  async function checkAuth(): Promise<boolean> {
    if (!token.value) return false

    try {
      await authApi.checkAuth()
      // 如果还没有用户信息，获取一次
      if (!user.value) {
        await fetchUserInfo()
      }
      return true
    } catch (err) {
      logout()
      return false
    }
  }

  function logout() {
    token.value = ''
    user.value = null
    localStorage.removeItem('access_token')
  }

  async function changePassword(oldPassword: string, newPassword: string): Promise<{ success: boolean; message: string }> {
    try {
      const response = await authApi.changePassword({
        old_password: oldPassword,
        new_password: newPassword
      })
      return { success: true, message: response.message }
    } catch (err: any) {
      return { 
        success: false, 
        message: err.response?.data?.detail || '修改密码失败' 
      }
    }
  }

  return {
    token,
    user,
    isLoading,
    error,
    isAuthenticated,
    username,
    login,
    fetchUserInfo,
    checkAuth,
    logout,
    changePassword
  }
})
