import request from './request'
import type { Photo, PhotoListResponse } from '../types/photo'

export interface PhotoFilters {
  camera?: string
  min_rating?: number
  is_favorite?: boolean
  year?: number
  month?: number
  shot_start_date?: string
  shot_end_date?: string
}

export interface SearchResult {
  photos: Photo[]
  total: number
  query: string
}

export const photoApi = {
  async getPhotos(page: number = 1, pageSize: number = 20, filters?: PhotoFilters): Promise<PhotoListResponse> {
    const params: Record<string, any> = { page, page_size: pageSize }
    
    if (filters) {
      if (filters.camera) params.camera = filters.camera
      if (filters.min_rating !== undefined) params.min_rating = filters.min_rating
      if (filters.is_favorite !== undefined) params.is_favorite = filters.is_favorite
      if (filters.year) params.year = filters.year
      if (filters.month) params.month = filters.month
      if (filters.shot_start_date) params.shot_start_date = filters.shot_start_date
      if (filters.shot_end_date) params.shot_end_date = filters.shot_end_date
    }
    
    const response = await request.get('/photos/', { params })
    return response.data
  },

  async getPhoto(id: string): Promise<Photo> {
    const response = await request.get(`/photos/${id}`)
    const data = response.data
    
    // 调试：检查 ai_tags 格式
    console.log('[API getPhoto] ai_tags:', {
      hasAiTags: !!data.ai_tags,
      type: typeof data.ai_tags,
      hasDeepAnalysis: data.ai_tags ? !!data.ai_tags.deep_analysis : false,
      deepAnalysisType: data.ai_tags ? typeof data.ai_tags.deep_analysis : null
    })
    
    // 如果 ai_tags 是字符串，尝试解析
    if (data.ai_tags && typeof data.ai_tags === 'string') {
      try {
        data.ai_tags = JSON.parse(data.ai_tags)
      } catch (e) {
        console.error('[API] Failed to parse ai_tags:', e)
      }
    }
    
    return data
  },

  async updateRating(photoId: string, rating: number): Promise<void> {
    await request.patch(`/photos/${photoId}/rating`, null, {
      params: { rating }
    })
  },

  async toggleFavorite(photoId: string): Promise<void> {
    await request.patch(`/photos/${photoId}/favorite`)
  },

  async deletePhoto(photoId: string): Promise<void> {
    await request.delete(`/photos/${photoId}`)
  },

  async deletePhotosBatch(photoIds: string[]): Promise<{ deleted_count: number; success_ids: string[]; failed_ids: string[] }> {
    const response = await request.post('/photos/batch-delete', { photo_ids: photoIds })
    return response.data
  },

  async searchPhotos(query: string, page: number = 1, pageSize: number = 20): Promise<SearchResult> {
    const response = await request.get('/search/', {
      params: { q: query, limit: pageSize }
    })
    // 后端返回格式不同，需要转换
    const data = response.data
    return {
      photos: data.results || [],
      total: data.total || 0,
      query: data.query || query
    }
  },

  async deepAnalyzePhoto(photoId: string): Promise<{ task_id: string; status: string }> {
    const response = await request.post(`/ai/deep-analyze/${photoId}`)
    return response.data
  },

  async getDeepAnalysisStatus(photoId: string): Promise<{ status: string; deep_analysis?: string; deep_analysis_time?: string }> {
    const response = await request.get(`/ai/deep-analyze/${photoId}/status`)
    return response.data
  }
}
