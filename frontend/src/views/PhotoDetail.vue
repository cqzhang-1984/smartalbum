<template>
  <div class="min-h-screen bg-background">
    <!-- 顶部导航 -->
    <header class="fixed top-0 left-0 right-0 z-50 glass border-b border-white/10 safe-area-top">
      <!-- 桌面端导航 -->
      <div class="hidden md:flex items-center justify-between h-16 px-6">
        <button
          @click="goBack"
          class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
        >
          <ArrowLeft :size="24" class="text-text-secondary" />
        </button>
        
        <h1 class="text-lg font-semibold text-text-primary">照片详情</h1>
        
        <div class="flex items-center space-x-2">
          <!-- 缩放控制 -->
          <div class="flex items-center space-x-1 bg-background-secondary rounded-lg px-2 py-1">
            <button
              @click="zoomOut"
              class="p-1 hover:bg-white/10 rounded transition-colors duration-200"
              title="缩小"
            >
              <ZoomOut :size="18" class="text-text-secondary" />
            </button>
            <span class="text-sm text-text-secondary w-12 text-center">{{ Math.round(scale * 100) }}%</span>
            <button
              @click="zoomIn"
              class="p-1 hover:bg-white/10 rounded transition-colors duration-200"
              title="放大"
            >
              <ZoomIn :size="18" class="text-text-secondary" />
            </button>
            <button
              @click="resetZoom"
              class="p-1 hover:bg-white/10 rounded transition-colors duration-200"
              title="重置"
            >
              <Maximize2 :size="18" class="text-text-secondary" />
            </button>
          </div>
          
          <!-- 全屏按钮 -->
          <button
            @click="toggleFullscreen"
            class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
            :title="isFullscreen ? '退出全屏' : '全屏'"
          >
            <component :is="isFullscreen ? Minimize2 : Maximize2" :size="24" class="text-text-secondary" />
          </button>
          
          <button
            @click="toggleFavorite"
            class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
          >
            <Heart
              :size="24"
              :class="photoStore.currentPhoto?.is_favorite ? 'text-danger fill-danger' : 'text-text-secondary'"
            />
          </button>
          <button
            @click="handleDeepAnalyze"
            class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
            :title="photoStore.currentPhoto?.ai_tags?.deep_analysis ? '重新生成深度分析' : '生成AI深度分析报告'"
          >
            <Sparkles
              :size="24"
              :class="photoStore.isDeepAnalyzing ? 'text-primary animate-pulse' : 'text-text-secondary'"
            />
          </button>
          <button
            @click="deletePhoto"
            class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
          >
            <Trash2 :size="24" class="text-text-secondary" />
          </button>
        </div>
      </div>

      <!-- 移动端导航 -->
      <div class="flex md:hidden items-center justify-between h-14 px-3">
        <button
          @click="goBack"
          class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
        >
          <ArrowLeft :size="22" class="text-text-secondary" />
        </button>
        
        <h1 class="text-base font-semibold text-text-primary">照片详情</h1>
        
        <div class="flex items-center space-x-1">
          <!-- 核心操作 -->
          <button
            @click="toggleFavorite"
            class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
          >
            <Heart
              :size="22"
              :class="photoStore.currentPhoto?.is_favorite ? 'text-danger fill-danger' : 'text-text-secondary'"
            />
          </button>
          
          <!-- 更多操作菜单 -->
          <div class="relative">
            <button
              @click="showMoreMenu = !showMoreMenu"
              class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
            >
              <MoreVertical :size="22" class="text-text-secondary" />
            </button>
            
            <!-- 下拉菜单 -->
            <Transition
              enter-active-class="transition duration-200 ease-out"
              enter-from-class="opacity-0 scale-95"
              enter-to-class="opacity-100 scale-100"
              leave-active-class="transition duration-150 ease-in"
              leave-from-class="opacity-100 scale-100"
              leave-to-class="opacity-0 scale-95"
            >
              <div
                v-if="showMoreMenu"
                class="absolute right-0 top-full mt-2 w-48 glass rounded-lg border border-white/10 shadow-xl py-1 z-50"
              >
                <button
                  @click="handleDeepAnalyze; showMoreMenu = false"
                  class="w-full px-4 py-2.5 text-left text-sm text-text-primary hover:bg-white/10 flex items-center space-x-3"
                >
                  <Sparkles :size="18" :class="photoStore.isDeepAnalyzing ? 'text-primary' : 'text-text-secondary'" />
                  <span>AI深度分析</span>
                </button>
                <button
                  @click="toggleFullscreen; showMoreMenu = false"
                  class="w-full px-4 py-2.5 text-left text-sm text-text-primary hover:bg-white/10 flex items-center space-x-3"
                >
                  <Maximize2 :size="18" class="text-text-secondary" />
                  <span>{{ isFullscreen ? '退出全屏' : '全屏查看' }}</span>
                </button>
                <div class="border-t border-white/10 my-1"></div>
                <button
                  @click="deletePhoto; showMoreMenu = false"
                  class="w-full px-4 py-2.5 text-left text-sm text-danger hover:bg-white/10 flex items-center space-x-3"
                >
                  <Trash2 :size="18" />
                  <span>删除照片</span>
                </button>
              </div>
            </Transition>
            
            <!-- 遮罩层 -->
            <div
              v-if="showMoreMenu"
              class="fixed inset-0 z-40"
              @click="showMoreMenu = false"
            ></div>
          </div>
        </div>
      </div>
    </header>

    <!-- 主内容 -->
    <main class="pt-14 md:pt-20 px-3 md:px-6 pb-24 md:pb-6">
      <div v-if="photoStore.loading" class="flex items-center justify-center min-h-[60vh]">
        <div class="text-text-secondary">加载中...</div>
      </div>

      <div v-else-if="photoStore.currentPhoto" class="max-w-7xl mx-auto">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4 md:gap-6">
          <!-- 照片显示区域 -->
          <div class="lg:col-span-2" :class="{ 'fixed inset-0 z-40 bg-black pt-14 md:pt-16 px-0 md:px-4 pb-0 md:pb-4': isFullscreen }">
            <!-- 图片容器 - 支持缩放和拖拽 -->
            <div
              ref="imageContainer"
              class="relative overflow-hidden rounded-lg bg-background-secondary flex items-center justify-center touch-manipulation"
              :class="{ 'rounded-none h-screen md:h-full': isFullscreen, 'h-[50vh] md:h-[70vh]': !isFullscreen }"
              @wheel="handleWheel"
              @mousedown="startDrag"
              @mousemove="onDrag"
              @mouseup="endDrag"
              @mouseleave="endDrag"
              @touchstart="handleTouchStart"
              @touchmove="handleTouchMove"
              @touchend="handleTouchEnd"
            >
              <img
                ref="imageElement"
                :src="largePhotoUrl"
                :alt="photoStore.currentPhoto.filename"
                :style="imageStyle"
                class="transition-transform duration-100 select-none max-w-full max-h-full object-contain"
                draggable="false"
                @load="onImageLoad"
              />
              
              <!-- 缩放提示 -->
              <div v-if="showZoomHint && !isMobile" class="absolute bottom-4 left-1/2 transform -translate-x-1/2 bg-black/60 text-white text-sm px-3 py-1 rounded-full">
                滚轮缩放 | 拖拽移动
              </div>
              
              <!-- 移动端缩放提示 -->
              <div v-if="showZoomHint && isMobile" class="absolute bottom-4 left-1/2 transform -translate-x-1/2 bg-black/60 text-white text-xs px-3 py-1.5 rounded-full">
                双指缩放 | 单指拖拽
              </div>
              
              <!-- 移动端缩放控制（悬浮按钮） -->
              <div v-if="isMobile && !isFullscreen" class="absolute bottom-4 right-4 flex flex-col space-y-2">
                <button
                  @click="zoomIn"
                  class="w-10 h-10 bg-background/80 backdrop-blur rounded-full flex items-center justify-center shadow-lg"
                >
                  <ZoomIn :size="20" class="text-text-primary" />
                </button>
                <button
                  @click="resetZoom"
                  class="w-10 h-10 bg-background/80 backdrop-blur rounded-full flex items-center justify-center shadow-lg text-xs font-medium"
                >
                  {{ Math.round(scale * 100) }}%
                </button>
                <button
                  @click="zoomOut"
                  class="w-10 h-10 bg-background/80 backdrop-blur rounded-full flex items-center justify-center shadow-lg"
                >
                  <ZoomOut :size="20" class="text-text-primary" />
                </button>
              </div>
            </div>
          </div>

          <!-- 信息面板 -->
          <div v-if="!isFullscreen" class="glass rounded-lg p-4 md:p-6 h-fit">
            <!-- 评分 -->
            <div class="mb-5 md:mb-6">
              <h3 class="text-xs md:text-sm font-medium text-text-muted mb-2 md:mb-3">评分</h3>
              <div class="flex space-x-1 md:space-x-2">
                <button
                  v-for="i in 5"
                  :key="i"
                  @click="updateRating(i)"
                  class="p-1 hover:scale-110 transition-transform duration-200"
                >
                  <Star
                    :size="22"
                    class="md:w-6 md:h-6"
                    :class="i <= photoStore.currentPhoto.rating ? 'text-warning fill-warning' : 'text-text-muted'"
                  />
                </button>
              </div>
            </div>

            <!-- EXIF信息 -->
            <div class="mb-5 md:mb-6">
              <h3 class="text-xs md:text-sm font-medium text-text-muted mb-2 md:mb-3">拍摄信息</h3>
              <div class="space-y-1.5 md:space-y-2 text-xs md:text-sm">
                <div v-if="photoStore.currentPhoto.camera_model" class="flex justify-between">
                  <span class="text-text-muted">相机</span>
                  <span class="text-text-secondary truncate ml-2">{{ photoStore.currentPhoto.camera_model }}</span>
                </div>
                <div v-if="photoStore.currentPhoto.lens_model" class="flex justify-between">
                  <span class="text-text-muted">镜头</span>
                  <span class="text-text-secondary truncate ml-2">{{ photoStore.currentPhoto.lens_model }}</span>
                </div>
                <div v-if="photoStore.currentPhoto.focal_length" class="flex justify-between">
                  <span class="text-text-muted">焦距</span>
                  <span class="text-text-secondary">{{ photoStore.currentPhoto.focal_length }}mm</span>
                </div>
                <div v-if="photoStore.currentPhoto.aperture" class="flex justify-between">
                  <span class="text-text-muted">光圈</span>
                  <span class="text-text-secondary">f/{{ photoStore.currentPhoto.aperture }}</span>
                </div>
                <div v-if="photoStore.currentPhoto.shutter_speed" class="flex justify-between">
                  <span class="text-text-muted">快门</span>
                  <span class="text-text-secondary">{{ photoStore.currentPhoto.shutter_speed }}</span>
                </div>
                <div v-if="photoStore.currentPhoto.iso" class="flex justify-between">
                  <span class="text-text-muted">ISO</span>
                  <span class="text-text-secondary">{{ photoStore.currentPhoto.iso }}</span>
                </div>
                <div v-if="photoStore.currentPhoto.shot_time" class="flex justify-between">
                  <span class="text-text-muted">拍摄时间</span>
                  <span class="text-text-secondary text-xs">{{ photoStore.currentPhoto.shot_time }}</span>
                </div>
              </div>
            </div>

            <!-- AI标签 -->
            <div v-if="photoStore.currentPhoto.ai_tags" class="mb-5 md:mb-6">
              <h3 class="text-xs md:text-sm font-medium text-text-muted mb-2 md:mb-3">AI识别标签</h3>
              <div class="flex flex-wrap gap-1.5 md:gap-2">
                <span
                  v-if="photoStore.currentPhoto.ai_tags.subject_emotion"
                  class="px-2.5 py-1 md:px-3 bg-primary/20 text-primary rounded-full text-xs"
                >
                  {{ photoStore.currentPhoto.ai_tags.subject_emotion }}
                </span>
                <span
                  v-if="photoStore.currentPhoto.ai_tags.pose"
                  class="px-2.5 py-1 md:px-3 bg-primary/20 text-primary rounded-full text-xs"
                >
                  {{ photoStore.currentPhoto.ai_tags.pose }}
                </span>
                <span
                  v-if="photoStore.currentPhoto.ai_tags.clothing_style"
                  class="px-2.5 py-1 md:px-3 bg-primary/20 text-primary rounded-full text-xs"
                >
                  {{ photoStore.currentPhoto.ai_tags.clothing_style }}
                </span>
                <span
                  v-if="photoStore.currentPhoto.ai_tags.lighting"
                  class="px-2.5 py-1 md:px-3 bg-primary/20 text-primary rounded-full text-xs"
                >
                  {{ photoStore.currentPhoto.ai_tags.lighting }}
                </span>
                <span
                  v-if="photoStore.currentPhoto.ai_tags.environment"
                  class="px-2.5 py-1 md:px-3 bg-primary/20 text-primary rounded-full text-xs"
                >
                  {{ photoStore.currentPhoto.ai_tags.environment }}
                </span>
              </div>
            </div>

            <!-- AI描述 -->
            <div v-if="photoStore.currentPhoto.ai_tags?.overall_description">
              <h3 class="text-xs md:text-sm font-medium text-text-muted mb-2 md:mb-3">AI描述</h3>
              <p class="text-xs md:text-sm text-text-secondary leading-relaxed">
                {{ photoStore.currentPhoto.ai_tags.overall_description }}
              </p>
            </div>
          </div>
        </div>

        <!-- AI深度分析 - 全宽独立区块 -->
        <div v-if="!isFullscreen" class="mt-4 md:mt-6">
          <DeepAnalysis
            :report="photoStore.currentPhoto.ai_tags?.deep_analysis"
            :analysis-time="photoStore.currentPhoto.ai_tags?.deep_analysis_time"
            :is-analyzing="photoStore.isDeepAnalyzing"
            @analyze="handleDeepAnalyze"
          />
        </div>
      </div>
    </main>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { usePhotoStore } from '../stores/photoStore'
import { ArrowLeft, Heart, Trash2, Star, ZoomIn, ZoomOut, Maximize2, Minimize2, Sparkles, MoreVertical } from 'lucide-vue-next'
import { getImageUrl } from '../utils/image'
import DeepAnalysis from '../components/DeepAnalysis.vue'

const router = useRouter()
const route = useRoute()
const photoStore = usePhotoStore()

// 缩放和拖拽状态
const scale = ref(1)
const translateX = ref(0)
const translateY = ref(0)
const isDragging = ref(false)
const dragStart = ref({ x: 0, y: 0 })
const isFullscreen = ref(false)
const showZoomHint = ref(true)
const showMoreMenu = ref(false)
const isMobile = ref(false)

// 触摸相关状态
const touches = ref<TouchList | null>(null)
const lastDistance = ref(0)

const imageContainer = ref<HTMLElement | null>(null)
const imageElement = ref<HTMLImageElement | null>(null)

// 计算大图URL（优先使用后端返回的完整URL）
const largePhotoUrl = computed(() => {
  const photo = photoStore.currentPhoto
  if (!photo) return ''
  
  // 优先使用后端生成的URL（支持COS）
  if (photo.thumbnail_large_url) {
    return photo.thumbnail_large_url
  }
  if (photo.original_url) {
    return photo.original_url
  }
  // 兼容本地存储
  return getImageUrl(photo.thumbnail_large || photo.original_path)
})

// 计算图片样式
const imageStyle = computed(() => ({
  transform: `translate(${translateX.value}px, ${translateY.value}px) scale(${scale.value})`,
  cursor: isDragging.value ? 'grabbing' : scale.value > 1 ? 'grab' : 'default'
}))

// 检测是否为移动端
function checkMobile() {
  isMobile.value = window.innerWidth < 768
}

onMounted(() => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
  
  const photoId = route.params.id as string
  if (photoId) {
    photoStore.fetchPhoto(photoId)
  }
  
  // 监听键盘事件
  document.addEventListener('keydown', handleKeydown)
  
  // 3秒后隐藏缩放提示
  setTimeout(() => {
    showZoomHint.value = false
  }, 3000)
})

onUnmounted(() => {
  window.removeEventListener('resize', checkMobile)
  document.removeEventListener('keydown', handleKeydown)
  photoStore.stopPollingDeepAnalysis()
})

function onImageLoad() {
  resetZoom()
}

// 返回上一页（保持搜索状态）
function goBack() {
  // 如果有搜索状态，返回首页并恢复搜索
  if (photoStore.isSearchMode && photoStore.searchQuery) {
    router.push('/')
  } else {
    router.back()
  }
}

// 缩放功能
function zoomIn() {
  scale.value = Math.min(scale.value * 1.25, 5)
}

function zoomOut() {
  scale.value = Math.max(scale.value / 1.25, 0.5)
  if (scale.value <= 1) {
    translateX.value = 0
    translateY.value = 0
  }
}

function resetZoom() {
  scale.value = 1
  translateX.value = 0
  translateY.value = 0
}

// 滚轮缩放
function handleWheel(event: WheelEvent) {
  event.preventDefault()
  if (event.deltaY < 0) {
    zoomIn()
  } else {
    zoomOut()
  }
}

// 鼠标拖拽功能
function startDrag(event: MouseEvent) {
  if (scale.value > 1) {
    isDragging.value = true
    dragStart.value = {
      x: event.clientX - translateX.value,
      y: event.clientY - translateY.value
    }
  }
}

function onDrag(event: MouseEvent) {
  if (isDragging.value && scale.value > 1) {
    translateX.value = event.clientX - dragStart.value.x
    translateY.value = event.clientY - dragStart.value.y
  }
}

function endDrag() {
  isDragging.value = false
}

// 触摸手势支持（移动端）
function handleTouchStart(event: TouchEvent) {
  touches.value = event.touches
  
  if (event.touches.length === 1 && scale.value > 1) {
    // 单指拖拽
    isDragging.value = true
    dragStart.value = {
      x: event.touches[0].clientX - translateX.value,
      y: event.touches[0].clientY - translateY.value
    }
  } else if (event.touches.length === 2) {
    // 双指缩放开始
    lastDistance.value = getTouchDistance(event.touches)
  }
}

function handleTouchMove(event: TouchEvent) {
  event.preventDefault()
  
  if (event.touches.length === 1 && isDragging.value && scale.value > 1) {
    // 单指拖拽
    translateX.value = event.touches[0].clientX - dragStart.value.x
    translateY.value = event.touches[0].clientY - dragStart.value.y
  } else if (event.touches.length === 2) {
    // 双指缩放
    const distance = getTouchDistance(event.touches)
    const scaleChange = distance / lastDistance.value
    
    if (Math.abs(scaleChange - 1) > 0.05) {
      const newScale = Math.min(Math.max(scale.value * scaleChange, 0.5), 5)
      scale.value = newScale
      lastDistance.value = distance
      
      // 缩放到1以下时重置位置
      if (scale.value <= 1) {
        translateX.value = 0
        translateY.value = 0
      }
    }
  }
}

function handleTouchEnd() {
  isDragging.value = false
  touches.value = null
  lastDistance.value = 0
}

function getTouchDistance(touches: TouchList): number {
  const dx = touches[0].clientX - touches[1].clientX
  const dy = touches[0].clientY - touches[1].clientY
  return Math.sqrt(dx * dx + dy * dy)
}

// 全屏功能
function toggleFullscreen() {
  isFullscreen.value = !isFullscreen.value
  if (isFullscreen.value) {
    resetZoom()
  }
}

// 键盘快捷键
function handleKeydown(event: KeyboardEvent) {
  switch (event.key) {
    case 'Escape':
      if (isFullscreen.value) {
        isFullscreen.value = false
      } else if (showMoreMenu.value) {
        showMoreMenu.value = false
      } else {
        goBack()
      }
      break
    case '+':
    case '=':
      zoomIn()
      break
    case '-':
      zoomOut()
      break
    case '0':
      resetZoom()
      break
    case 'f':
    case 'F':
      toggleFullscreen()
      break
  }
}

async function updateRating(rating: number) {
  if (photoStore.currentPhoto) {
    await photoStore.updateRating(photoStore.currentPhoto.id, rating)
  }
}

async function toggleFavorite() {
  if (photoStore.currentPhoto) {
    await photoStore.toggleFavorite(photoStore.currentPhoto.id)
  }
}

async function deletePhoto() {
  if (photoStore.currentPhoto && confirm('确定要删除这张照片吗?')) {
    await photoStore.deletePhoto(photoStore.currentPhoto.id)
    router.push('/')
  }
}

async function handleDeepAnalyze() {
  if (!photoStore.currentPhoto || photoStore.isDeepAnalyzing) return
  
  const hasExisting = photoStore.currentPhoto.ai_tags?.deep_analysis
  if (hasExisting && !confirm('已有深度分析报告，是否重新生成？')) return
  
  try {
    await photoStore.deepAnalyzePhoto(photoStore.currentPhoto.id)
  } catch (e) {
    console.error('深度分析失败:', e)
    alert('深度分析失败，请重试')
  }
}
</script>