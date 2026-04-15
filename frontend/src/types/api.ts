/**
 * API 通用类型定义
 */

// API 响应包装
export interface ApiResponse<T = any> {
  code: number
  message: string
  data: T
}

// 分页请求参数
export interface PaginationParams {
  page?: number
  page_size?: number
}

// 分页响应数据
export interface PaginatedResponse<T> {
  items: T[]
  total: number
  page: number
  page_size: number
  total_pages: number
}

// API 错误响应
export interface ApiError {
  error: string
  message: string
  details?: Record<string, string[]>
}

// 上传进度
export interface UploadProgress {
  file: string
  progress: number
  status: 'pending' | 'uploading' | 'success' | 'error'
  error?: string
}

// 筛选参数
export interface FilterParams {
  camera?: string
  min_rating?: number
  is_favorite?: boolean
  year?: number
  month?: number
  keyword?: string
}

// 排序参数
export type SortField = 'shot_time' | 'created_at' | 'rating' | 'file_size'
export type SortOrder = 'asc' | 'desc'

export interface SortParams {
  sort_by?: SortField
  sort_order?: SortOrder
}
