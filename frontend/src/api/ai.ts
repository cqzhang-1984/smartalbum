import request from './request'

// 类型定义
export interface ImageGenModel {
  id: string
  name: string
  description: string
  is_default?: boolean
}

export interface ImageGenSize {
  id: string
  ratio: string
  name: string
  width: number
  height: number
  description: string
}

export interface ImageGenConfig {
  default_model: string
  default_format: string
  watermark: boolean
  api_base: string
  has_credentials: boolean
}

export interface ImageGenModelsResponse {
  models: ImageGenModel[]
  sizes: ImageGenSize[]
  current: ImageGenConfig
}

export interface GenerateImageRequest {
  prompt: string
  negative_prompt?: string
  model_id?: string
  size_ratio?: string
  width?: number
  height?: number
  output_format?: string
  seed?: number
  save_to_album?: boolean
  title?: string
  source_photo_id?: string
}

export interface GenerateFromPhotoRequest {
  prompt: string
  negative_prompt?: string
  model_id?: string
  size_ratio?: string
  strength?: number
  output_format?: string
  save_to_album?: boolean
  title?: string
}

export interface GeneratedImage {
  id: string
  prompt: string
  negative_prompt?: string
  title?: string
  model_id: string
  model_name?: string
  width?: number
  height?: number
  size_ratio?: string
  size_display?: string
  image_url?: string
  local_path?: string
  is_saved: boolean
  saved_photo_id?: string
  source_photo_id?: string
  created_at: string
}

export interface GenerateImageResponse {
  success: boolean
  id: string
  image_url?: string
  local_path?: string
  model?: string
  width?: number
  height?: number
  size_ratio?: string
  is_saved: boolean
  saved_photo_id?: string
  created_at: string
}

export interface HistoryResponse {
  images: GeneratedImage[]
  pagination: {
    page: number
    page_size: number
    total: number
    total_pages: number
  }
}

// API 方法
export const aiApi = {
  /**
   * 获取可用的文生图模型和尺寸
   */
  async getModels(): Promise<ImageGenModelsResponse> {
    const response = await request.get('/ai/image-gen/models')
    return response.data
  },

  /**
   * 文生图生成
   */
  async generateImage(request: GenerateImageRequest): Promise<GenerateImageResponse> {
    const response = await request.post('/ai/image-gen/generate', request)
    return response.data
  },

  /**
   * 基于照片生成（图生图）
   */
  async generateFromPhoto(photoId: string, request: GenerateFromPhotoRequest): Promise<GenerateImageResponse> {
    const response = await request.post(`/ai/image-gen/generate-from-photo/${photoId}`, request)
    return response.data
  },

  /**
   * 获取生成历史
   */
  async getHistory(page: number = 1, pageSize: number = 20, savedOnly: boolean = false): Promise<HistoryResponse> {
    const response = await request.get('/ai/image-gen/history', {
      params: { page, page_size: pageSize, saved_only: savedOnly }
    })
    return response.data
  },

  /**
   * 保存生成图片到相册
   */
  async saveToAlbum(imageId: string, title?: string): Promise<{ message: string; photo_id: string }> {
    const response = await request.post(`/ai/image-gen/${imageId}/save`, null, {
      params: { title }
    })
    return response.data
  },

  /**
   * 删除生成记录
   */
  async deleteGeneratedImage(imageId: string): Promise<{ message: string }> {
    const response = await request.delete(`/ai/image-gen/${imageId}`)
    return response.data
  },
}
