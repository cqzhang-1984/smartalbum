<template>
  <div class="min-h-screen bg-background">
    <!-- 顶部导航栏 -->
    <header class="fixed top-0 left-0 right-0 z-50 glass border-b border-white/10 safe-area-top">
      <div class="flex items-center justify-between h-14 md:h-16 px-4 md:px-6">
        <button
          @click="router.back()"
          class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
        >
          <ArrowLeft :size="22" class="text-text-secondary md:w-6 md:h-6" />
        </button>
        
        <h1 class="text-base md:text-lg font-semibold text-text-primary">系统设置</h1>
        
        <div class="w-10"></div>
      </div>
    </header>

    <!-- 主内容区 -->
    <main class="pt-[60px] md:pt-20 px-4 md:px-6 pb-24 md:pb-6 max-w-4xl mx-auto">
      <!-- 账户安全 -->
      <section class="glass rounded-lg p-4 md:p-6 mb-4 md:mb-6">
        <h2 class="text-lg md:text-xl font-semibold text-text-primary mb-3 md:mb-4 flex items-center">
          <User :size="20" class="mr-2 md:w-6 md:h-6" />
          账户安全
        </h2>
        
        <div class="space-y-3 md:space-y-4">
          <!-- 当前用户信息 -->
          <div class="flex items-center justify-between p-3 md:p-4 bg-background-tertiary rounded-lg">
            <div class="flex items-center min-w-0">
              <div class="w-9 h-9 md:w-10 md:h-10 rounded-full bg-primary/20 flex items-center justify-center mr-2.5 md:mr-3 flex-shrink-0">
                <User :size="18" class="text-primary md:w-5 md:h-5" />
              </div>
              <div class="min-w-0">
                <p class="text-text-primary font-medium text-sm md:text-base truncate">{{ authStore.username }}</p>
                <p class="text-xs md:text-sm text-text-muted">管理员账户</p>
              </div>
            </div>
            <button
              @click="logout"
              class="px-3 py-1.5 md:px-4 md:py-2 bg-danger/20 text-danger hover:bg-danger/30 rounded-lg transition-colors duration-200 flex items-center text-sm md:text-base flex-shrink-0"
            >
              <LogOut :size="14" class="mr-1.5 md:mr-2 md:w-4 md:h-4" />
              <span class="hidden sm:inline">退出登录</span>
              <span class="sm:hidden">退出</span>
            </button>
          </div>
          
          <!-- 修改密码表单 -->
          <div class="border-t border-white/10 pt-3 md:pt-4 mt-3 md:mt-4">
            <h3 class="text-base md:text-lg font-medium text-text-primary mb-3 md:mb-4 flex items-center">
              <Lock :size="16" class="mr-2 md:w-[18px] md:h-[18px]" />
              修改密码
            </h3>
            
            <div class="space-y-3">
              <div>
                <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">当前密码</label>
                <input
                  v-model="passwordForm.oldPassword"
                  type="password"
                  class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
                  placeholder="输入当前密码"
                />
              </div>
              
              <div>
                <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">新密码</label>
                <input
                  v-model="passwordForm.newPassword"
                  type="password"
                  class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
                  placeholder="输入新密码（至少6位）"
                />
              </div>
              
              <div>
                <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">确认新密码</label>
                <input
                  v-model="passwordForm.confirmPassword"
                  type="password"
                  class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
                  placeholder="再次输入新密码"
                />
              </div>
              
              <!-- 错误/成功提示 -->
              <div v-if="passwordError" class="p-2.5 md:p-3 bg-danger/10 border border-danger/30 rounded-lg">
                <p class="text-danger text-xs md:text-sm">{{ passwordError }}</p>
              </div>
              <div v-if="passwordSuccess" class="p-2.5 md:p-3 bg-success/10 border border-success/30 rounded-lg">
                <p class="text-success text-xs md:text-sm">{{ passwordSuccess }}</p>
              </div>
              
              <button
                @click="changePassword"
                :disabled="isChangingPassword"
                class="w-full px-4 py-2 md:py-2.5 bg-primary hover:bg-primary-light disabled:opacity-50 rounded-lg transition-colors duration-200 text-sm md:text-base"
              >
                {{ isChangingPassword ? '修改中...' : '修改密码' }}
              </button>
            </div>
          </div>
        </div>
      </section>

      <!-- AI模型配置 -->
      <section class="glass rounded-lg p-4 md:p-6 mb-4 md:mb-6">
        <h2 class="text-lg md:text-xl font-semibold text-text-primary mb-3 md:mb-4 flex items-center">
          <Brain :size="20" class="mr-2 md:w-6 md:h-6" />
          AI多模态模型配置
        </h2>
        
        <div class="space-y-3 md:space-y-4">
          <div>
            <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">模型名称</label>
            <input
              v-model="settings.ai_model_name"
              type="text"
              class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
              placeholder="如：GPT-4o、豆包等"
            />
          </div>
          
          <div>
            <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">模型ID</label>
            <input
              v-model="settings.ai_model_id"
              type="text"
              class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
              placeholder="如：gpt-4o、doubao-seed-2-0-mini-260215"
            />
          </div>
          
          <div>
            <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">API URL</label>
            <input
              v-model="settings.ai_api_base"
              type="text"
              class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
              placeholder="如：https://api.openai.com/v1"
            />
          </div>
          
          <div>
            <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">API密钥</label>
            <input
              v-model="settings.ai_api_key"
              type="password"
              class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
              placeholder="输入您的API密钥"
            />
          </div>
        </div>
      </section>

      <!-- Embedding模型配置 -->
      <section class="glass rounded-lg p-4 md:p-6 mb-4 md:mb-6">
        <h2 class="text-lg md:text-xl font-semibold text-text-primary mb-3 md:mb-4 flex items-center">
          <Layers :size="20" class="mr-2 md:w-6 md:h-6" />
          向量化模型配置
        </h2>
        
        <div class="space-y-3 md:space-y-4">
          <div>
            <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">模型名称</label>
            <input
              v-model="settings.embedding_model_name"
              type="text"
              class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
              placeholder="如：text-embedding-3-small"
            />
          </div>
          
          <div>
            <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">模型ID</label>
            <input
              v-model="settings.embedding_model_id"
              type="text"
              class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
              placeholder="如：text-embedding-3-small"
            />
          </div>
          
          <div>
            <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">API URL</label>
            <input
              v-model="settings.embedding_api_base"
              type="text"
              class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
              placeholder="如：https://api.openai.com/v1"
            />
          </div>
          
          <div>
            <label class="block text-xs md:text-sm font-medium text-text-muted mb-1.5 md:mb-2">API密钥（留空则使用AI模型密钥）</label>
            <input
              v-model="settings.embedding_api_key"
              type="password"
              class="w-full px-3 py-2 md:px-4 md:py-2.5 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary text-sm md:text-base"
              placeholder="可选，留空使用AI模型密钥"
            />
          </div>
        </div>
      </section>

      <!-- 存储管理 -->
      <section class="glass rounded-lg p-4 md:p-6 mb-4 md:mb-6">
        <h2 class="text-lg md:text-xl font-semibold text-text-primary mb-3 md:mb-4 flex items-center">
          <HardDrive :size="20" class="mr-2 md:w-6 md:h-6" />
          存储管理
        </h2>
        
        <div class="space-y-3 md:space-y-4">
          <div class="flex items-center justify-between p-3 md:p-4 bg-background-tertiary rounded-lg">
            <div class="min-w-0">
              <p class="text-text-primary font-medium text-sm md:text-base">存储空间使用</p>
              <p class="text-xs md:text-sm text-text-muted mt-0.5 md:mt-1">已使用 {{ formatSize(storage.used) }} / {{ formatSize(storage.total) }}</p>
            </div>
            <div class="text-right flex-shrink-0">
              <p class="text-xl md:text-2xl font-semibold text-primary">{{ storage.percentage }}%</p>
            </div>
          </div>
          
          <div class="flex flex-col sm:flex-row space-y-2 sm:space-y-0 sm:space-x-3">
            <button
              @click="clearCache"
              class="flex-1 px-4 py-2 md:py-2.5 bg-background-tertiary hover:bg-background-secondary rounded-lg transition-colors duration-200 text-sm md:text-base"
            >
              清理缓存
            </button>
            <button
              @click="exportData"
              class="flex-1 px-4 py-2 md:py-2.5 bg-background-tertiary hover:bg-background-secondary rounded-lg transition-colors duration-200 text-sm md:text-base"
            >
              导出数据
            </button>
          </div>
        </div>
      </section>

      <!-- 日志管理 -->
      <section class="glass rounded-lg p-4 md:p-6 mb-4 md:mb-6">
        <h2 class="text-lg md:text-xl font-semibold text-text-primary mb-3 md:mb-4 flex items-center">
          <FileText :size="20" class="mr-2 md:w-6 md:h-6" />
          日志管理
        </h2>
        
        <div class="space-y-3 md:space-y-4">
          <div class="flex items-center justify-between p-3 md:p-4 bg-background-tertiary rounded-lg">
            <div class="min-w-0">
              <p class="text-text-primary font-medium text-sm md:text-base">日志统计</p>
              <p class="text-xs md:text-sm text-text-muted mt-0.5 md:mt-1">
                总计: {{ logStats.total }} 条 | 
                错误: {{ logStats.error }} | 
                警告: {{ logStats.warning }}
              </p>
            </div>
          </div>
          
          <div class="flex flex-col sm:flex-row space-y-2 sm:space-y-0 sm:space-x-3">
            <button
              @click="viewLogs"
              class="flex-1 px-4 py-2 md:py-2.5 bg-background-tertiary hover:bg-background-secondary rounded-lg transition-colors duration-200 text-sm md:text-base"
            >
              查看日志
            </button>
            <button
              @click="clearLogs"
              class="flex-1 px-4 py-2 md:py-2.5 bg-danger/20 text-danger hover:bg-danger/30 rounded-lg transition-colors duration-200 text-sm md:text-base"
            >
              清理旧日志
            </button>
          </div>
        </div>
      </section>

      <!-- 保存按钮 -->
      <div class="flex justify-end">
        <button
          @click="saveSettings"
          class="w-full sm:w-auto px-6 py-2.5 md:py-3 bg-primary hover:bg-primary-light rounded-lg transition-colors duration-200 text-sm md:text-base"
        >
          保存设置
        </button>
      </div>
    </main>

    <!-- 移动端底部导航 -->
    <MobileNav />
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, Brain, HardDrive, FileText, Layers, Lock, LogOut, User } from 'lucide-vue-next'
import { useAuthStore } from '../stores/authStore'
import MobileNav from '../components/MobileNav.vue'

const router = useRouter()
const authStore = useAuthStore()

// 密码修改相关
const passwordForm = ref({
  oldPassword: '',
  newPassword: '',
  confirmPassword: ''
})
const passwordError = ref('')
const passwordSuccess = ref('')
const isChangingPassword = ref(false)

const settings = ref({
  ai_model_name: '',
  ai_model_id: '',
  ai_api_base: '',
  ai_api_key: '',
  embedding_model_name: '',
  embedding_model_id: '',
  embedding_api_base: '',
  embedding_api_key: ''
})

const storage = ref({
  used: 1024 * 1024 * 500,
  total: 1024 * 1024 * 1024 * 100,
  percentage: 0.5
})

const logStats = ref({
  total: 0,
  info: 0,
  warning: 0,
  error: 0,
  debug: 0
})

onMounted(async () => {
  await loadSettings()
  await loadLogStats()
})

async function loadSettings() {
  try {
    const response = await fetch('/api/ai/config')
    if (response.ok) {
      const data = await response.json()
      settings.value = { ...settings.value, ...data }
    }
  } catch (error) {
    console.error('Failed to load settings:', error)
  }
}

async function loadLogStats() {
  try {
    const response = await fetch('/api/logs/stats')
    if (response.ok) {
      logStats.value = await response.json()
    }
  } catch (error) {
    console.error('Failed to load log stats:', error)
  }
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
  return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB'
}

function clearCache() {
  console.log('Clearing cache...')
}

function exportData() {
  console.log('Exporting data...')
}

function viewLogs() {
  router.push('/logs')
}

async function clearLogs() {
  if (confirm('确定要清理7天前的日志吗？')) {
    try {
      const response = await fetch('/api/logs/clear?before_days=7', { method: 'DELETE' })
      if (response.ok) {
        await loadLogStats()
        alert('日志清理成功')
      }
    } catch (error) {
      console.error('Failed to clear logs:', error)
    }
  }
}

async function saveSettings() {
  try {
    const response = await fetch('/api/ai/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(settings.value)
    })
    if (response.ok) {
      alert('设置保存成功')
    }
  } catch (error) {
    console.error('Failed to save settings:', error)
  }
}

// 密码修改
async function changePassword() {
  passwordError.value = ''
  passwordSuccess.value = ''
  
  // 验证
  if (!passwordForm.value.oldPassword || !passwordForm.value.newPassword) {
    passwordError.value = '请填写所有密码字段'
    return
  }
  
  if (passwordForm.value.newPassword.length < 6) {
    passwordError.value = '新密码长度不能少于6位'
    return
  }
  
  if (passwordForm.value.newPassword !== passwordForm.value.confirmPassword) {
    passwordError.value = '两次输入的新密码不一致'
    return
  }
  
  isChangingPassword.value = true
  
  try {
    const result = await authStore.changePassword(
      passwordForm.value.oldPassword,
      passwordForm.value.newPassword
    )
    
    if (result.success) {
      passwordSuccess.value = result.message
      // 清空表单
      passwordForm.value = { oldPassword: '', newPassword: '', confirmPassword: '' }
    } else {
      passwordError.value = result.message
    }
  } catch (error) {
    passwordError.value = '修改密码失败，请稍后重试'
  } finally {
    isChangingPassword.value = false
  }
}

// 退出登录
function logout() {
  if (confirm('确定要退出登录吗？')) {
    authStore.logout()
    router.push('/login')
  }
}
</script>