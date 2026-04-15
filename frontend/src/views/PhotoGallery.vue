<template>
  <div class="min-h-screen bg-background flex">
    <!-- 桌面端：左侧筛选面板 -->
    <aside v-if="showFilters" class="hidden md:block fixed left-0 top-16 bottom-0 w-64 glass border-r border-white/10 overflow-y-auto z-40">
      <div class="p-4">
        <FilterPanel
          :key="filterPanelKey"
          :cameras="cameras"
          :available-years="availableYears"
          @filter="handleFilter"
        />
      </div>
    </aside>

    <!-- 移动端：筛选面板抽屉 -->
    <Transition
      enter-active-class="transition duration-300 ease-out"
      enter-from-class="translate-y-full"
      enter-to-class="translate-y-0"
      leave-active-class="transition duration-200 ease-in"
      leave-from-class="translate-y-0"
      leave-to-class="translate-y-full"
    >
      <div
        v-if="showFilters && isMobile"
        class="fixed inset-x-0 bottom-0 z-50 glass rounded-t-2xl border-t border-white/10 md:hidden"
        style="max-height: 70vh;"
      >
        <!-- 拖拽把手 -->
        <div 
          class="flex justify-center pt-3 pb-2 cursor-pointer"
          @click="showFilters = false"
        >
          <div class="w-10 h-1 bg-white/20 rounded-full"></div>
        </div>
        <div class="p-4 overflow-y-auto" style="max-height: calc(70vh - 40px);">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-text-primary">筛选</h3>
            <button 
              @click="showFilters = false"
              class="p-2 hover:bg-white/10 rounded-lg"
            >
              <X :size="20" class="text-text-secondary" />
            </button>
          </div>
          <FilterPanel
            :key="filterPanelKey"
            :cameras="cameras"
            :available-years="availableYears"
            @filter="handleFilterMobile"
          />
        </div>
      </div>
    </Transition>

    <!-- 遮罩层 -->
    <Transition
      enter-active-class="transition-opacity duration-300"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-200"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="showFilters && isMobile"
        class="fixed inset-0 bg-black/50 z-40 md:hidden"
        @click="showFilters = false"
      ></div>
    </Transition>

    <!-- 主内容区 -->
    <div class="flex-1" :class="{ 'md:ml-64': showFilters && !isMobile }">
      <!-- 顶部导航栏 -->
      <header class="fixed top-0 left-0 right-0 z-30 glass border-b border-white/10 safe-area-top">
        <!-- 桌面端导航 -->
        <div class="hidden md:flex items-center justify-between h-16 px-6">
          <div class="flex items-center space-x-4">
            <button
              @click="showFilters = !showFilters"
              class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
            >
              <SlidersHorizontal :size="24" class="text-text-secondary" />
            </button>
            
            <h1 class="text-2xl font-semibold text-text-primary">SmartAlbum</h1>
          </div>
          
          <div class="flex-1 max-w-2xl mx-8">
            <SearchBar
              :show-a-i-hint="true"
              @search="handleSearch"
              @clear="clearSearch"
            />
          </div>
          
          <div class="flex items-center space-x-4">
            <!-- 选择模式按钮 -->
            <button
              v-if="photoStore.photos.length > 0"
              @click="photoStore.toggleSelectionMode()"
              :class="[
                'px-4 py-2 rounded-lg transition-colors duration-200 flex items-center space-x-2',
                photoStore.isSelectionMode 
                  ? 'bg-primary text-white' 
                  : 'hover:bg-white/10 text-text-secondary'
              ]"
            >
              <CheckSquare :size="20" />
              <span>{{ photoStore.isSelectionMode ? '取消' : '选择' }}</span>
            </button>
            
            <router-link
              to="/albums"
              class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
            >
              <FolderOpen :size="24" class="text-text-secondary" />
            </router-link>
            
            <router-link
              to="/ai-creation"
              class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
              title="AI创作"
            >
              <Sparkles :size="24" class="text-text-secondary" />
            </router-link>
            
            <button
              @click="showUploadModal = true"
              class="px-4 py-2 bg-primary hover:bg-primary-light rounded-lg transition-colors duration-200 flex items-center space-x-2"
            >
              <Upload :size="20" />
              <span>上传照片</span>
            </button>
            
            <router-link
              to="/settings"
              class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
            >
              <Settings :size="24" class="text-text-secondary" />
            </router-link>
          </div>
        </div>

        <!-- 移动端导航 -->
        <div class="flex md:hidden items-center justify-between h-14 px-3">
          <div class="flex items-center space-x-2">
            <button
              @click="showFilters = !showFilters"
              class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
            >
              <SlidersHorizontal :size="22" class="text-text-secondary" />
            </button>
            
            <h1 class="text-lg font-semibold text-text-primary">SmartAlbum</h1>
          </div>
          
          <!-- 移动端搜索框（展开状态） -->
          <div v-if="showMobileSearch" class="flex-1 mx-2">
            <div class="relative">
              <input
                v-model="mobileSearchQuery"
                type="text"
                placeholder="搜索照片..."
                class="w-full pl-9 pr-8 py-2 bg-background-tertiary rounded-lg text-sm text-text-primary placeholder-text-muted focus:outline-none focus:ring-1 focus:ring-primary"
                @keyup.enter="handleMobileSearch"
              />
              <Search class="absolute left-2.5 top-1/2 -translate-y-1/2 text-text-muted" :size="16" />
              <button
                @click="closeMobileSearch"
                class="absolute right-2 top-1/2 -translate-y-1/2 text-text-muted"
              >
                <X :size="16" />
              </button>
            </div>
          </div>
          
          <!-- 移动端右侧按钮 -->
          <div v-else class="flex items-center space-x-1">
            <button
              v-if="photoStore.photos.length > 0"
              @click="photoStore.toggleSelectionMode()"
              :class="[
                'p-2 rounded-lg transition-colors duration-200',
                photoStore.isSelectionMode 
                  ? 'bg-primary text-white' 
                  : 'hover:bg-white/10 text-text-secondary'
              ]"
            >
              <CheckSquare :size="20" />
            </button>
            
            <button
              @click="showMobileSearch = true"
              class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
            >
              <Search :size="22" class="text-text-secondary" />
            </button>
          </div>
        </div>
      </header>

      <!-- 主内容 -->
      <main class="pt-[60px] md:pt-20 px-3 md:px-6 pb-20 md:pb-6">
        <!-- 加载状态 -->
        <div v-if="photoStore.loading && photoStore.photos.length === 0" class="flex items-center justify-center min-h-[60vh]">
          <div class="text-center">
            <div class="animate-spin rounded-full h-10 w-10 md:h-12 md:w-12 border-b-2 border-primary mx-auto mb-4"></div>
            <p class="text-text-secondary text-sm md:text-base">加载中...</p>
          </div>
        </div>

        <!-- 错误状态 -->
        <div v-else-if="photoStore.error" class="flex items-center justify-center min-h-[60vh]">
          <div class="text-center px-4">
            <AlertCircle :size="40" class="text-danger mx-auto mb-4 md:w-12 md:h-12" />
            <p class="text-text-primary mb-2">加载失败</p>
            <p class="text-text-muted text-sm mb-4">{{ photoStore.error }}</p>
            <button
              @click="retryLoad"
              class="px-4 py-2 bg-primary hover:bg-primary-light rounded-lg transition-colors duration-200"
            >
              重试
            </button>
          </div>
        </div>

        <!-- 空状态 -->
        <div v-else-if="photoStore.photos.length === 0" class="flex flex-col items-center justify-center min-h-[60vh] px-4">
          <Image :size="60" class="text-text-muted mb-4 md:w-20 md:h-20 md:mb-6" />
          <h2 class="text-xl md:text-2xl font-semibold text-text-primary mb-2">还没有照片</h2>
          <p class="text-text-secondary mb-4 md:mb-6 text-sm md:text-base">点击下方按钮开始上传您的照片</p>
          <button
            @click="showUploadModal = true"
            class="px-5 py-2.5 md:px-6 md:py-3 bg-primary hover:bg-primary-light rounded-lg transition-colors duration-200 flex items-center space-x-2"
          >
            <Upload :size="18" class="md:w-5 md:h-5" />
            <span class="text-sm md:text-base">上传第一张照片</span>
          </button>
        </div>

        <!-- 照片网格 -->
        <div v-else>
          <div class="mb-3 md:mb-4 flex items-center justify-between">
            <p class="text-text-secondary text-xs md:text-sm">
              共 {{ photoStore.totalPhotos }} 张照片
            </p>
            <!-- 移动端筛选标签（如果有） -->
            <div v-if="hasActiveFilters" class="flex items-center space-x-2">
              <button
                @click="clearFilters"
                class="text-xs text-primary hover:text-primary-light"
              >
                清除筛选
              </button>
            </div>
          </div>
          
          <!-- 响应式网格：移动端2列，小屏3列，中屏4列，大屏6列，超大屏8列 -->
          <div class="grid grid-cols-2 xs:grid-cols-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-8 gap-2 md:gap-4">
            <PhotoCard
              v-for="photo in photoStore.photos"
              :key="photo.id"
              :photo="photo"
              :selectable="photoStore.isSelectionMode"
              :selected="photoStore.selectedPhotoIds.has(photo.id)"
              @click="handlePhotoClick(photo.id)"
              @toggle-selection="photoStore.togglePhotoSelection"
              @delete="handleDeletePhoto"
            />
          </div>

          <!-- 批量操作工具栏（移动端适配） -->
          <div 
            v-if="photoStore.isSelectionMode && photoStore.selectedCount > 0"
            class="fixed bottom-[72px] md:bottom-0 left-0 right-0 glass border-t border-white/10 p-3 md:p-4 z-40"
          >
            <div class="max-w-7xl mx-auto flex items-center justify-between">
              <div class="flex items-center space-x-2 md:space-x-4 overflow-x-auto no-scrollbar">
                <span class="text-text-primary text-sm md:text-base whitespace-nowrap">
                  已选择 {{ photoStore.selectedCount }} 张
                </span>
                <button
                  @click="photoStore.selectAllPhotos()"
                  class="px-2.5 py-1 md:px-3 md:py-1.5 text-xs md:text-sm bg-white/10 hover:bg-white/20 rounded-lg transition-colors duration-200 whitespace-nowrap"
                >
                  全选
                </button>
                <button
                  @click="photoStore.clearSelection()"
                  class="px-2.5 py-1 md:px-3 md:py-1.5 text-xs md:text-sm bg-white/10 hover:bg-white/20 rounded-lg transition-colors duration-200 whitespace-nowrap"
                >
                  取消
                </button>
              </div>
              <button
                @click="confirmBatchDelete"
                class="px-3 py-1.5 md:px-4 md:py-2 bg-danger hover:bg-red-600 rounded-lg transition-colors duration-200 flex items-center space-x-1 md:space-x-2"
              >
                <Trash2 :size="18" class="md:w-5 md:h-5" />
                <span class="text-sm md:text-base">删除</span>
              </button>
            </div>
          </div>

          <!-- 分页 -->
          <div v-if="totalPages > 1" class="flex justify-center items-center py-6 md:py-8 gap-1 md:gap-2">
            <button
              @click="goToPage(photoStore.currentPage - 1)"
              :disabled="photoStore.currentPage === 1"
              class="p-1.5 md:p-2 hover:bg-white/10 rounded-lg transition-colors duration-200 disabled:opacity-30 disabled:cursor-not-allowed"
            >
              <ChevronLeft :size="18" class="text-text-secondary md:w-5 md:h-5" />
            </button>

            <!-- 移动端简化分页 -->
            <div class="hidden md:flex items-center gap-1">
              <template v-for="(page, index) in pageNumbers" :key="index">
                <span v-if="page === -1 || page === -2" class="px-2 text-text-muted">...</span>
                <button
                  v-else
                  @click="goToPage(page)"
                  :class="[
                    'px-3 py-1 rounded-lg transition-colors duration-200 min-w-[36px]',
                    page === photoStore.currentPage
                      ? 'bg-primary text-white'
                      : 'hover:bg-white/10 text-text-secondary'
                  ]"
                >
                  {{ page }}
                </button>
              </template>
            </div>

            <!-- 移动端分页显示 -->
            <span class="md:hidden px-3 py-1 text-text-secondary text-sm">
              {{ photoStore.currentPage }} / {{ totalPages }}
            </span>

            <button
              @click="goToPage(photoStore.currentPage + 1)"
              :disabled="photoStore.currentPage === totalPages"
              class="p-1.5 md:p-2 hover:bg-white/10 rounded-lg transition-colors duration-200 disabled:opacity-30 disabled:cursor-not-allowed"
            >
              <ChevronRight :size="18" class="text-text-secondary md:w-5 md:h-5" />
            </button>
          </div>
        </div>
      </main>
    </div>

    <!-- 移动端底部导航 -->
    <MobileNav @upload="showUploadModal = true" />

    <!-- 上传弹窗 -->
    <div
      v-if="showUploadModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
      @click="showUploadModal = false"
    >
      <div
        class="bg-background-secondary rounded-xl p-5 md:p-8 w-full max-w-md"
        @click.stop
      >
        <h2 class="text-xl md:text-2xl font-semibold text-text-primary mb-4 md:mb-6">上传照片</h2>
        
        <div
          class="border-2 border-dashed border-text-muted rounded-lg p-6 md:p-8 text-center cursor-pointer hover:border-primary transition-colors duration-200"
          :class="{ 'border-primary bg-primary/10': isDragging }"
          @click="triggerFileInput"
          @dragover.prevent="isDragging = true"
          @dragleave="isDragging = false"
          @drop.prevent="handleDrop"
        >
          <Upload :size="40" class="text-text-muted mx-auto mb-3 md:mb-4 md:w-12 md:h-12" />
          <p class="text-text-secondary mb-2 text-sm md:text-base">拖拽照片到此处或点击选择</p>
          <p class="text-text-muted text-xs md:text-sm">支持 JPG, PNG, WEBP, HEIC 格式</p>
          <p class="text-text-muted text-xs md:text-sm mt-1">单张最大 50MB</p>
        </div>
        
        <input
          ref="fileInput"
          type="file"
          multiple
          accept="image/jpeg,image/png,image/webp,image/heic"
          class="hidden"
          @change="handleFileSelect"
        />
        
        <!-- 上传进度 -->
        <div v-if="uploading" class="mt-4">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm text-text-secondary">上传中...</span>
            <span class="text-sm text-text-muted">{{ uploadProgress }}%</span>
          </div>
          <div class="w-full bg-background-tertiary rounded-full h-2">
            <div
              class="bg-primary h-2 rounded-full transition-all duration-200"
              :style="{ width: `${uploadProgress}%` }"
            ></div>
          </div>
        </div>
        
        <div class="flex justify-end mt-5 md:mt-6 space-x-3">
          <button
            @click="showUploadModal = false"
            class="px-4 py-2 bg-background-tertiary hover:bg-background-secondary rounded-lg transition-colors duration-200 text-sm md:text-base"
            :disabled="uploading"
          >
            取消
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { usePhotoStore } from '../stores/photoStore'
import type { PhotoFilters } from '../api/photo'
import PhotoCard from '../components/PhotoCard.vue'
import FilterPanel from '../components/FilterPanel.vue'
import SearchBar from '../components/SearchBar.vue'
import MobileNav from '../components/MobileNav.vue'
import {
  Upload,
  Settings,
  Image,
  SlidersHorizontal,
  FolderOpen,
  AlertCircle,
  ChevronLeft,
  ChevronRight,
  Sparkles,
  CheckSquare,
  Trash2,
  Search,
  X
} from 'lucide-vue-next'

const router = useRouter()
const photoStore = usePhotoStore()

const showFilters = ref(false)
const showUploadModal = ref(false)
const fileInput = ref<HTMLInputElement | null>(null)
const uploading = ref(false)
const uploadProgress = ref(0)
const isDragging = ref(false)
const filterPanelKey = ref(0) // 用于强制重新渲染 FilterPanel

// 移动端相关状态
const isMobile = ref(false)
const showMobileSearch = ref(false)
const mobileSearchQuery = ref('')

const cameras = ref([
  { model: 'Canon EOS R5', count: 0 },
  { model: 'Nikon Z8', count: 0 },
  { model: 'Sony A7IV', count: 0 }
])

const availableYears = computed(() => {
  const currentYear = new Date().getFullYear()
  return Array.from({ length: 5 }, (_, i) => currentYear - i)
})

const totalPages = computed(() => Math.ceil(photoStore.totalPhotos / photoStore.pageSize))
const pageNumbers = computed(() => {
  const pages: number[] = []
  const current = photoStore.currentPage
  const total = totalPages.value

  if (total <= 7) {
    for (let i = 1; i <= total; i++) pages.push(i)
  } else {
    if (current <= 4) {
      pages.push(1, 2, 3, 4, 5)
      if (total > 5) pages.push(-1, total)
    } else if (current >= total - 3) {
      pages.push(1, -1)
      for (let i = total - 4; i <= total; i++) pages.push(i)
    } else {
      pages.push(1, -1, current - 1, current, current + 1, -2, total)
    }
  }
  return pages
})

const hasActiveFilters = computed(() => {
  return Object.keys(photoStore.currentFilters).length > 0
})

// 检测是否为移动端
function checkMobile() {
  isMobile.value = window.innerWidth < 768
}

onMounted(() => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
  
  // 只在没有数据时才加载（从详情页返回时会保持状态）
  if (photoStore.photos.length === 0) {
    if (photoStore.isSearchMode && photoStore.searchQuery) {
      photoStore.searchPhotos(photoStore.searchQuery, photoStore.currentPage)
    } else {
      photoStore.fetchPhotos(photoStore.currentPage)
    }
  }
  loadCameras()
})

async function loadCameras() {
  try {
    const response = await fetch('/api/photos/cameras/list')
    if (response.ok) {
      cameras.value = await response.json()
    }
  } catch (error) {
    console.error('Failed to load cameras:', error)
  }
}

function openPhoto(photoId: string) {
  if (!photoStore.isSelectionMode) {
    router.push(`/photo/${photoId}`)
  }
}

function handlePhotoClick(photoId: string) {
  if (photoStore.isSelectionMode) {
    photoStore.togglePhotoSelection(photoId)
  } else {
    router.push(`/photo/${photoId}`)
  }
}

async function confirmBatchDelete() {
  if (photoStore.selectedCount === 0) return
  
  if (confirm(`确定要删除选中的 ${photoStore.selectedCount} 张照片吗？此操作不可撤销。`)) {
    try {
      await photoStore.deleteSelectedPhotos()
    } catch (error) {
      console.error('批量删除失败:', error)
    }
  }
}

function loadMore() {
  goToPage(photoStore.currentPage + 1)
}

function goToPage(page: number) {
  if (page < 1 || page > totalPages.value) return
  if (photoStore.isSearchMode && photoStore.searchQuery) {
    photoStore.searchPhotos(photoStore.searchQuery, page)
  } else {
    photoStore.fetchPhotos(page)
  }
  window.scrollTo({ top: 0, behavior: 'smooth' })
}

function retryLoad() {
  photoStore.fetchPhotos(1)
}

function handleFilter(filters: any) {
  const photoFilters: PhotoFilters = {}
  
  // 处理年份筛选（多选，取第一个值）
  if (filters.years && filters.years.length > 0) {
    photoFilters.year = filters.years[0]
  }
  
  // 处理相机筛选（多选，取第一个值）
  if (filters.cameras && filters.cameras.length > 0) {
    photoFilters.camera = filters.cameras[0]
  }
  
  // 处理评分筛选（多选，取最小值作为最低评分要求）
  if (filters.ratings && filters.ratings.length > 0) {
    photoFilters.min_rating = Math.min(...filters.ratings)
  }
  
  // 处理收藏筛选
  if (filters.favoritesOnly) {
    photoFilters.is_favorite = true
  }
  
  photoStore.fetchPhotos(1, photoFilters)
}

function handleFilterMobile(filters: any) {
  handleFilter(filters)
  showFilters.value = false
}

function clearFilters() {
  photoStore.clearFilters()
  filterPanelKey.value++ // 强制重新渲染 FilterPanel 以重置状态
}

function handleSearch(query: string) {
  if (query.trim()) {
    photoStore.searchPhotos(query, 1)
  } else {
    clearSearch()
  }
}

function handleMobileSearch() {
  if (mobileSearchQuery.value.trim()) {
    photoStore.searchPhotos(mobileSearchQuery.value, 1)
    showMobileSearch.value = false
  }
}

function closeMobileSearch() {
  showMobileSearch.value = false
  mobileSearchQuery.value = ''
  if (photoStore.isSearchMode) {
    clearSearch()
  }
}

function clearSearch() {
  photoStore.fetchPhotos(1)
}

async function handleDeletePhoto(photoId: string) {
  await photoStore.deletePhoto(photoId)
}

function triggerFileInput() {
  fileInput.value?.click()
}

function handleFileSelect(event: Event) {
  const target = event.target as HTMLInputElement
  const files = target.files
  if (files) {
    uploadFiles(files)
  }
}

function handleDrop(event: DragEvent) {
  isDragging.value = false
  const files = event.dataTransfer?.files
  if (files) {
    uploadFiles(files)
  }
}

async function uploadFiles(files: FileList) {
  uploading.value = true
  uploadProgress.value = 0
  
  const formData = new FormData()
  for (let i = 0; i < files.length; i++) {
    formData.append('files', files[i])
  }
  
  try {
    const xhr = new XMLHttpRequest()
    
    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) {
        uploadProgress.value = Math.round((e.loaded / e.total) * 100)
      }
    })
    
    xhr.addEventListener('load', () => {
      if (xhr.status === 200) {
        showUploadModal.value = false
        photoStore.fetchPhotos(1)
      }
      uploading.value = false
    })
    
    xhr.addEventListener('error', () => {
      console.error('Upload failed')
      uploading.value = false
    })
    
    xhr.open('POST', '/api/upload/')
    xhr.send(formData)
  } catch (error) {
    console.error('Upload failed:', error)
    uploading.value = false
  }
}
</script>