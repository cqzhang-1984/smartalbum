<template>
  <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 p-4">
    <div class="w-full max-w-md">
      <!-- Logo 区域 -->
      <div class="text-center mb-6 md:mb-8">
        <div class="w-14 h-14 md:w-16 md:h-16 mx-auto mb-3 md:mb-4 rounded-2xl bg-gradient-to-br from-pink-500 to-purple-600 flex items-center justify-center shadow-lg shadow-pink-500/20">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-7 h-7 md:w-8 md:h-8 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
        </div>
        <h1 class="text-xl md:text-2xl font-bold text-white mb-1.5 md:mb-2">SmartAlbum</h1>
        <p class="text-slate-400 text-xs md:text-sm">智能相册管理系统</p>
      </div>

      <!-- 登录表单 -->
      <div class="glass rounded-2xl p-5 md:p-8 shadow-2xl">
        <h2 class="text-lg md:text-xl font-semibold text-white mb-5 md:mb-6 text-center">用户登录</h2>
        
        <form @submit.prevent="handleLogin" class="space-y-4 md:space-y-5">
          <!-- 用户名 -->
          <div>
            <label class="block text-xs md:text-sm font-medium text-slate-300 mb-1.5 md:mb-2">用户名</label>
            <div class="relative">
              <span class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">
                <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4 md:w-5 md:h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                </svg>
              </span>
              <input
                v-model="form.username"
                type="text"
                placeholder="请输入用户名"
                class="w-full pl-9 md:pl-10 pr-4 py-2.5 md:py-3 bg-slate-800/50 border border-slate-700 rounded-xl text-white text-sm md:text-base placeholder-slate-500 focus:outline-none focus:border-pink-500 focus:ring-1 focus:ring-pink-500 transition-colors"
                required
              />
            </div>
          </div>

          <!-- 密码 -->
          <div>
            <label class="block text-xs md:text-sm font-medium text-slate-300 mb-1.5 md:mb-2">密码</label>
            <div class="relative">
              <span class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">
                <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4 md:w-5 md:h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </span>
              <input
                v-model="form.password"
                :type="showPassword ? 'text' : 'password'"
                placeholder="请输入密码"
                class="w-full pl-9 md:pl-10 pr-11 md:pr-12 py-2.5 md:py-3 bg-slate-800/50 border border-slate-700 rounded-xl text-white text-sm md:text-base placeholder-slate-500 focus:outline-none focus:border-pink-500 focus:ring-1 focus:ring-pink-500 transition-colors"
                required
              />
              <button
                type="button"
                @click="showPassword = !showPassword"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-300 transition-colors p-1"
              >
                <svg v-if="showPassword" xmlns="http://www.w3.org/2000/svg" class="w-4 h-4 md:w-5 md:h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                </svg>
                <svg v-else xmlns="http://www.w3.org/2000/svg" class="w-4 h-4 md:w-5 md:h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
                </svg>
              </button>
            </div>
          </div>

          <!-- 错误信息 -->
          <div v-if="error" class="p-2.5 md:p-3 bg-red-500/10 border border-red-500/30 rounded-xl">
            <p class="text-red-400 text-xs md:text-sm flex items-center">
              <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4 mr-2 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span class="break-all">{{ error }}</span>
            </p>
          </div>

          <!-- 登录按钮 -->
          <button
            type="submit"
            :disabled="loading"
            class="w-full py-2.5 md:py-3 px-4 bg-gradient-to-r from-pink-500 to-purple-600 hover:from-pink-600 hover:to-purple-700 text-white text-sm md:text-base font-medium rounded-xl shadow-lg shadow-pink-500/25 transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center"
          >
            <svg v-if="loading" class="animate-spin -ml-1 mr-2 h-4 w-4 md:h-5 md:w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            {{ loading ? '登录中...' : '登 录' }}
          </button>
        </form>

        <!-- 安全提示 -->
        <div class="mt-5 md:mt-6 p-3 md:p-4 bg-slate-800/50 rounded-xl">
          <p class="text-slate-400 text-xs text-center">
            请使用管理员分配的账号密码登录
          </p>
          <p class="text-slate-500 text-xs text-center mt-1">
            首次登录后请尽快修改默认密码
          </p>
        </div>
      </div>

      <!-- 底部版权 -->
      <p class="text-center text-slate-500 text-xs mt-6 md:mt-8">
        © 2024 SmartAlbum. All rights reserved.
      </p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/authStore'

const router = useRouter()
const authStore = useAuthStore()

const form = reactive({
  username: '',
  password: ''
})

const loading = ref(false)
const error = ref('')
const showPassword = ref(false)

async function handleLogin() {
  loading.value = true
  error.value = ''
  
  try {
    const success = await authStore.login(form.username, form.password)
    if (success) {
      router.push('/')
    } else {
      error.value = authStore.error || '登录失败'
    }
  } catch (err: any) {
    error.value = err.message || '登录失败，请稍后重试'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.glass {
  background-color: rgba(30, 41, 59, 0.7);
  backdrop-filter: blur(12px);
  border: 1px solid rgba(255, 255, 255, 0.08);
}
</style>
