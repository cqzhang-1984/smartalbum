<template>
  <div class="min-h-screen bg-background">
    <!-- 顶部导航栏 -->
    <header class="fixed top-0 left-0 right-0 z-50 glass border-b border-white/10">
      <div class="flex items-center justify-between h-16 px-6">
        <div class="flex items-center space-x-4">
          <router-link to="/" class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200">
            <ArrowLeft :size="24" class="text-text-secondary" />
          </router-link>
          <h1 class="text-2xl font-semibold text-text-primary">智能相册</h1>
        </div>
        
        <button
          @click="showCreateModal = true"
          class="px-4 py-2 bg-primary hover:bg-primary-light rounded-lg transition-colors duration-200 flex items-center space-x-2"
        >
          <Plus :size="20" />
          <span>创建相册</span>
        </button>
      </div>
    </header>

    <!-- 主内容区 -->
    <main class="pt-20 px-6">
      <!-- 加载状态 -->
      <div v-if="albumStore.loading && albumStore.albums.length === 0" class="flex items-center justify-center min-h-[60vh]">
        <div class="text-center">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto mb-4"></div>
          <p class="text-text-secondary">加载中...</p>
        </div>
      </div>

      <!-- 空状态 -->
      <div v-else-if="albumStore.albums.length === 0" class="flex flex-col items-center justify-center min-h-[60vh]">
        <FolderOpen :size="80" class="text-text-muted mb-6" />
        <h2 class="text-2xl font-semibold text-text-primary mb-2">还没有相册</h2>
        <p class="text-text-secondary mb-6">创建您的第一个相册来整理照片</p>
        <button
          @click="showCreateModal = true"
          class="px-6 py-3 bg-primary hover:bg-primary-light rounded-lg transition-colors duration-200"
        >
          创建第一个相册
        </button>
      </div>

      <!-- 相册网格 -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        <div
          v-for="album in albumStore.albums"
          :key="album.id"
          class="glass rounded-lg overflow-hidden cursor-pointer hover:bg-white/5 transition-colors duration-200 group"
          @click="openAlbum(album.id)"
        >
          <!-- 相册封面 -->
          <div class="aspect-square bg-background-secondary relative">
            <img
              v-if="album.cover"
              :src="album.cover"
              :alt="album.name"
              class="w-full h-full object-cover"
            />
            <div v-else class="w-full h-full flex items-center justify-center">
              <Image :size="48" class="text-text-muted" />
            </div>
            
            <!-- 删除按钮 -->
            <button
              @click.stop="confirmDeleteAlbum(album.id, album.name)"
              class="absolute top-2 right-2 p-2 bg-black/60 hover:bg-danger rounded-lg transition-all duration-200"
              title="删除相册"
            >
              <Trash2 :size="16" class="text-white" />
            </button>
          </div>
          
          <!-- 相册信息 -->
          <div class="p-4">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-lg font-semibold text-text-primary truncate">{{ album.name }}</h3>
              <Sparkles v-if="album.is_smart" :size="16" class="text-primary" />
            </div>
            <p class="text-sm text-text-muted">{{ album.photo_count }} 张照片</p>
          </div>
        </div>
      </div>
    </main>

    <!-- 创建相册弹窗 -->
    <div
      v-if="showCreateModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/80"
      @click="showCreateModal = false"
    >
      <div
        class="bg-background-secondary rounded-xl p-8 max-w-md w-full mx-4"
        @click.stop
      >
        <h2 class="text-2xl font-semibold text-text-primary mb-6">创建相册</h2>
        
        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-text-muted mb-2">相册名称 *</label>
            <input
              v-model="newAlbum.name"
              type="text"
              class="w-full px-4 py-2 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary"
              placeholder="输入相册名称"
            />
          </div>
          
          <div>
            <label class="block text-sm font-medium text-text-muted mb-2">描述</label>
            <textarea
              v-model="newAlbum.description"
              rows="3"
              class="w-full px-4 py-2 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary resize-none"
              placeholder="添加描述（可选）"
            />
          </div>
          
          <div class="flex items-center">
            <input
              v-model="newAlbum.is_smart"
              type="checkbox"
              id="smart-album"
              class="w-4 h-4 rounded border-white/10 bg-background-tertiary text-primary focus:ring-primary"
            />
            <label for="smart-album" class="ml-2 text-sm text-text-secondary">
              智能相册（根据规则自动添加照片）
            </label>
          </div>

          <!-- 智能相册规则设置 -->
          <div v-if="newAlbum.is_smart" class="space-y-3 pt-2 border-t border-white/10">
            <div class="flex items-center justify-between">
              <label class="text-sm font-medium text-text-muted">匹配规则</label>
              <button
                @click="addRule"
                type="button"
                class="text-xs px-2 py-1 bg-primary/20 hover:bg-primary/30 text-primary rounded transition-colors"
              >
                + 添加规则
              </button>
            </div>

            <div v-if="newAlbum.rules.length === 0" class="text-sm text-text-muted text-center py-4">
              点击"添加规则"设置匹配条件
            </div>

            <div v-for="(rule, index) in newAlbum.rules" :key="index" class="flex items-center gap-2 text-sm">
              <select
                v-model="rule.field"
                class="flex-1 px-2 py-1.5 bg-background-tertiary border border-white/10 rounded text-text-primary text-xs"
              >
                <option value="">选择字段</option>
                <option value="ai_tags.subject_emotion">情绪</option>
                <option value="ai_tags.scene_type">场景</option>
                <option value="ai_tags.style_tags">风格</option>
                <option value="camera_model">相机型号</option>
                <option value="lens_model">镜头型号</option>
                <option value="rating">评分</option>
                <option value="is_favorite">是否收藏</option>
              </select>

              <select
                v-model="rule.operator"
                class="w-24 px-2 py-1.5 bg-background-tertiary border border-white/10 rounded text-text-primary text-xs"
              >
                <option value="equals">等于</option>
                <option value="contains">包含</option>
                <option value="not_equals">不等于</option>
                <option value="greater_than">大于</option>
                <option value="less_than">小于</option>
              </select>

              <input
                v-model="rule.value"
                type="text"
                placeholder="值"
                class="flex-1 px-2 py-1.5 bg-background-tertiary border border-white/10 rounded text-text-primary text-xs"
              />

              <button
                @click="removeRule(index)"
                type="button"
                class="p-1 text-text-muted hover:text-danger transition-colors"
              >
                ×
              </button>
            </div>

            <p class="text-xs text-text-muted">
              多条规则为"且"关系，需全部满足
            </p>
          </div>
        </div>
        
        <div class="flex justify-end mt-6 space-x-3">
          <button
            @click="showCreateModal = false"
            class="px-4 py-2 bg-background-tertiary hover:bg-background-secondary rounded-lg transition-colors duration-200"
          >
            取消
          </button>
          <button
            @click="handleCreateAlbum"
            :disabled="!newAlbum.name.trim() || albumStore.loading"
            class="px-4 py-2 bg-primary hover:bg-primary-light rounded-lg transition-colors duration-200 disabled:opacity-50"
          >
            创建
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAlbumStore } from '../stores/albumStore'
import { Plus, FolderOpen, Image, Sparkles, ArrowLeft, Trash2 } from 'lucide-vue-next'

const router = useRouter()
const albumStore = useAlbumStore()

const showCreateModal = ref(false)

const newAlbum = ref({
  name: '',
  description: '',
  is_smart: false,
  rules: [] as Array<{ field: string; operator: string; value: string }>
})

function addRule() {
  newAlbum.value.rules.push({
    field: '',
    operator: 'equals',
    value: ''
  })
}

function removeRule(index: number) {
  newAlbum.value.rules.splice(index, 1)
}

onMounted(() => {
  albumStore.fetchAlbums()
})

function openAlbum(albumId: string) {
  router.push(`/albums/${albumId}`)
}

async function handleCreateAlbum() {
  if (!newAlbum.value.name.trim()) return

  // 过滤掉无效规则
  const validRules = newAlbum.value.rules.filter(r => r.field && r.value)

  const albumId = await albumStore.createAlbum({
    name: newAlbum.value.name.trim(),
    description: newAlbum.value.description || undefined,
    is_smart: newAlbum.value.is_smart,
    rules: newAlbum.value.is_smart && validRules.length > 0 ? validRules : undefined
  })

  if (albumId) {
    showCreateModal.value = false
    newAlbum.value = {
      name: '',
      description: '',
      is_smart: false,
      rules: []
    }
  }
}

async function confirmDeleteAlbum(albumId: string, albumName: string) {
  if (confirm(`确定要删除相册"${albumName}"吗？相册内的照片不会被删除。`)) {
    await albumStore.deleteAlbum(albumId)
  }
}
</script>
