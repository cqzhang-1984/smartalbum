/**
 * 照片相关类型定义
 */

// AI 标签
export interface AITags {
  subject_emotion?: string
  pose?: string
  clothing_style?: string
  lighting?: string
  environment?: string
  overall_description?: string
  aesthetic_score?: number
  deep_analysis?: string
  deep_analysis_time?: string
}

// EXIF 信息
export interface ExifInfo {
  shot_time?: string
  camera_model?: string
  lens_model?: string
  focal_length?: number
  aperture?: number
  shutter_speed?: string
  iso?: number
  width?: number
  height?: number
  orientation?: number
}

// 照片缩略图 URL
export interface PhotoUrls {
  original_url?: string
  thumbnail_small_url?: string
  thumbnail_medium_url?: string
  thumbnail_large_url?: string
}

// 照片基础信息
export interface Photo {
  id: string
  filename: string
  original_path: string
  file_size: number
  file_hash?: string
  
  // EXIF信息
  shot_time?: string
  camera_model?: string
  lens_model?: string
  focal_length?: number
  aperture?: number
  shutter_speed?: string
  iso?: number
  
  // 缩略图路径
  thumbnail_small?: string
  thumbnail_medium?: string
  thumbnail_large?: string
  
  // 完整URL（COS或本地）
  original_url?: string
  thumbnail_small_url?: string
  thumbnail_medium_url?: string
  thumbnail_large_url?: string
  
  // AI标签
  ai_tags?: AITags
  
  // 用户数据
  rating: number
  is_favorite: boolean
  face_cluster_id?: string
  
  created_at: string
  updated_at: string
}

// 照片列表响应
export interface PhotoListResponse {
  photos: Photo[]
  total: number
  page: number
  page_size: number
}

// 照片筛选选项
export interface PhotoFilterOptions {
  cameras: string[]
  years: number[]
  min_rating: number
  max_rating: number
}

// 更新照片请求
export interface UpdatePhotoRequest {
  rating?: number
  is_favorite?: boolean
  ai_tags?: Partial<AITags>
}

// 批量操作请求
export interface BatchDeleteRequest {
  photo_ids: string[]
}

// 批量操作响应
export interface BatchOperationResponse {
  success: string[]
  failed: Array<{ id: string; reason: string }>
}

// 上传结果
export interface UploadResult {
  filename: string
  photo_id?: string
  status: 'success' | 'skipped' | 'error'
  reason?: string
}

// 上传响应
export interface UploadResponse {
  uploaded: number
  skipped: number
  files: UploadResult[]
}
