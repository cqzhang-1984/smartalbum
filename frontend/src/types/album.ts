/**
 * 相册相关类型定义
 */

// 相册信息
export interface Album {
  id: string
  name: string
  description?: string
  cover_photo_id?: string
  cover_photo_url?: string
  photo_count: number
  is_default: boolean
  created_at: string
  updated_at: string
}

// 创建相册请求
export interface CreateAlbumRequest {
  name: string
  description?: string
  cover_photo_id?: string
}

// 更新相册请求
export interface UpdateAlbumRequest {
  name?: string
  description?: string
  cover_photo_id?: string
}

// 相册照片关联
export interface AlbumPhoto {
  album_id: string
  photo_id: string
  added_at: string
}

// 人脸聚类
export interface FaceCluster {
  id: string
  name?: string
  cover_photo_id?: string
  cover_photo_url?: string
  photo_count: number
  created_at: string
}

// 搜索相关类型
export interface SearchResult {
  photo_id: string
  description: string
  metadata: Record<string, any>
  distance: number
  similarity_score: number
}

export interface SearchResponse {
  query: string
  results: SearchResult[]
  total: number
}

// AI 分析相关
export interface AIAnalysisResult {
  overall_description: string
  subject_emotion?: string
  pose?: string
  clothing_style?: string
  lighting?: string
  environment?: string
  aesthetic_score?: number
  deep_analysis?: string
  deep_analysis_time?: string
}

export interface DeepAnalysisStatus {
  photo_id: string
  status: 'pending' | 'processing' | 'completed' | 'failed'
  progress?: number
  result?: string
  error?: string
}

// 存储统计
export interface StorageStats {
  total_photos: number
  total_size: number
  thumbnails_size: number
  originals_size: number
  ai_generated_size: number
}

// 向量统计
export interface VectorStats {
  total_vectors: number
  collection_name: string
  storage_type: string
  storage_path?: string
  status: string
}
