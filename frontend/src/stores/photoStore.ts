import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { Photo } from '../types/photo'
import { photoApi, type PhotoFilters } from '../api/photo'

export const usePhotoStore = defineStore('photo', () => {
  // State
  const photos = ref<Photo[]>([])
  const currentPhoto = ref<Photo | null>(null)
  const loading = ref(false)
  const error = ref<string | null>(null)
  const totalPhotos = ref(0)
  const currentPage = ref(1)
  const pageSize = ref(20)
  const currentFilters = ref<PhotoFilters>({})
  const isSearchMode = ref(false)
  const searchQuery = ref('')

  // 批量选择状态
  const selectedPhotoIds = ref<Set<string>>(new Set())
  const isSelectionMode = ref(false)

  // 深度分析状态
  const isDeepAnalyzing = ref(false)

  // Getters
  const hasMore = computed(() => photos.value.length < totalPhotos.value)
  const selectedCount = computed(() => selectedPhotoIds.value.size)

  // Actions
  async function fetchPhotos(page: number = 1, filters?: PhotoFilters) {
    loading.value = true
    error.value = null

    if (filters) {
      currentFilters.value = filters
    }

    try {
      const response = await photoApi.getPhotos(page, pageSize.value, currentFilters.value)

      photos.value = response.photos

      totalPhotos.value = response.total
      currentPage.value = page
      isSearchMode.value = false
      searchQuery.value = ''
    } catch (e) {
      error.value = e instanceof Error ? e.message : '加载照片失败'
      console.error('Failed to fetch photos:', e)
    } finally {
      loading.value = false
    }
  }

  async function searchPhotos(query: string, page: number = 1) {
    if (!query.trim()) {
      fetchPhotos(1, {})
      return
    }

    loading.value = true
    error.value = null

    try {
      const response = await photoApi.searchPhotos(query, page, pageSize.value)

      photos.value = response.photos

      totalPhotos.value = response.total
      currentPage.value = page
      isSearchMode.value = true
      searchQuery.value = query
    } catch (e) {
      error.value = e instanceof Error ? e.message : '搜索失败'
      console.error('Failed to search photos:', e)
    } finally {
      loading.value = false
    }
  }

  async function loadMore() {
    if (isSearchMode.value && searchQuery.value) {
      await searchPhotos(searchQuery.value, currentPage.value + 1)
    } else {
      await fetchPhotos(currentPage.value + 1)
    }
  }

  async function fetchPhoto(id: string) {
    loading.value = true
    error.value = null
    
    try {
      currentPhoto.value = await photoApi.getPhoto(id)
    } catch (e) {
      error.value = e instanceof Error ? e.message : '加载照片详情失败'
      console.error('Failed to fetch photo:', e)
    } finally {
      loading.value = false
    }
  }

  async function updateRating(photoId: string, rating: number) {
    try {
      await photoApi.updateRating(photoId, rating)
      
      const photo = photos.value.find(p => p.id === photoId)
      if (photo) {
        photo.rating = rating
      }
      
      if (currentPhoto.value?.id === photoId) {
        currentPhoto.value.rating = rating
      }
    } catch (e) {
      console.error('Failed to update rating:', e)
    }
  }

  async function toggleFavorite(photoId: string) {
    try {
      await photoApi.toggleFavorite(photoId)
      
      const photo = photos.value.find(p => p.id === photoId)
      if (photo) {
        photo.is_favorite = !photo.is_favorite
      }
      
      if (currentPhoto.value?.id === photoId) {
        currentPhoto.value.is_favorite = !currentPhoto.value.is_favorite
      }
    } catch (e) {
      console.error('Failed to toggle favorite:', e)
    }
  }

  async function deletePhoto(photoId: string) {
    try {
      await photoApi.deletePhoto(photoId)
      photos.value = photos.value.filter(p => p.id !== photoId)
      if (currentPhoto.value?.id === photoId) {
        currentPhoto.value = null
      }
      totalPhotos.value = Math.max(0, totalPhotos.value - 1)
    } catch (e) {
      console.error('Failed to delete photo:', e)
    }
  }

  function clearFilters() {
    currentFilters.value = {}
    isSearchMode.value = false
    searchQuery.value = ''
    fetchPhotos(1)
  }

  function clearPhotos() {
    photos.value = []
    currentPhoto.value = null
    totalPhotos.value = 0
    currentPage.value = 1
    currentFilters.value = {}
    isSearchMode.value = false
    searchQuery.value = ''
  }

  // 批量选择方法
  function toggleSelectionMode() {
    isSelectionMode.value = !isSelectionMode.value
    if (!isSelectionMode.value) {
      clearSelection()
    }
  }

  function togglePhotoSelection(photoId: string) {
    if (selectedPhotoIds.value.has(photoId)) {
      selectedPhotoIds.value.delete(photoId)
    } else {
      selectedPhotoIds.value.add(photoId)
    }
  }

  function selectAllPhotos() {
    photos.value.forEach(photo => {
      selectedPhotoIds.value.add(photo.id)
    })
  }

  function clearSelection() {
    selectedPhotoIds.value.clear()
  }

  async function deleteSelectedPhotos() {
    if (selectedPhotoIds.value.size === 0) return

    const idsToDelete = Array.from(selectedPhotoIds.value)
    try {
      const result = await photoApi.deletePhotosBatch(idsToDelete)

      // 从列表中移除已删除的照片
      photos.value = photos.value.filter(p => !result.success_ids.includes(p.id))
      totalPhotos.value = Math.max(0, totalPhotos.value - result.success_ids.length)

      // 清空选择
      clearSelection()
      isSelectionMode.value = false

      return result
    } catch (e) {
      console.error('Failed to delete selected photos:', e)
      throw e
    }
  }


  let deepAnalysisTimer: ReturnType<typeof setInterval> | null = null

  async function deepAnalyzePhoto(photoId: string) {
    isDeepAnalyzing.value = true
    try {
      // 触发异步任务，立即返回
      await photoApi.deepAnalyzePhoto(photoId)

      // 开始轮询任务状态
      startPollingDeepAnalysis(photoId)
    } catch (e) {
      console.error('Failed to start deep analysis:', e)
      isDeepAnalyzing.value = false
      throw e
    }
  }

  function startPollingDeepAnalysis(photoId: string) {
    // 清除已有轮询
    if (deepAnalysisTimer) {
      clearInterval(deepAnalysisTimer)
      deepAnalysisTimer = null
    }

    deepAnalysisTimer = setInterval(async () => {
      try {
        const result = await photoApi.getDeepAnalysisStatus(photoId)

        if (result.status === 'completed' && result.deep_analysis) {
          // 分析完成，更新当前照片数据
          if (currentPhoto.value?.id === photoId) {
            // 确保响应式更新 - 创建新对象
            const existingTags = currentPhoto.value.ai_tags || {}
            currentPhoto.value.ai_tags = {
              ...existingTags,
              deep_analysis: result.deep_analysis,
              deep_analysis_time: result.deep_analysis_time
            }
            console.log('[DeepAnalysis] 分析完成，数据已更新:', {
              hasReport: !!result.deep_analysis,
              reportLength: result.deep_analysis?.length,
              time: result.deep_analysis_time
            })
          }
          isDeepAnalyzing.value = false

          // 停止轮询
          if (deepAnalysisTimer) {
            clearInterval(deepAnalysisTimer)
            deepAnalysisTimer = null
          }
        }
      } catch (e) {
        console.error('Failed to poll deep analysis status:', e)
        // 轮询失败不停止，继续尝试
      }
    }, 5000) // 每5秒轮询一次
  }

  function stopPollingDeepAnalysis() {
    if (deepAnalysisTimer) {
      clearInterval(deepAnalysisTimer)
      deepAnalysisTimer = null
    }
    isDeepAnalyzing.value = false
  }

  return {
    photos,
    currentPhoto,
    loading,
    error,
    totalPhotos,
    currentPage,
    pageSize,
    hasMore,
    currentFilters,
    isSearchMode,
    searchQuery,
    // 批量选择状态
    selectedPhotoIds,
    isSelectionMode,
    selectedCount,
    // 深度分析状态
    isDeepAnalyzing,
    // 方法
    fetchPhotos,
    searchPhotos,
    loadMore,
    fetchPhoto,
    updateRating,
    toggleFavorite,
    deletePhoto,
    clearFilters,
    clearPhotos,
    // 批量选择方法
    toggleSelectionMode,
    togglePhotoSelection,
    selectAllPhotos,
    clearSelection,
    deleteSelectedPhotos,
    // 深度分析方法
    deepAnalyzePhoto,
    stopPollingDeepAnalysis
  }
})
