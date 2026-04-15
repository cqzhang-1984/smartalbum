import request from './request'
import type { Photo, PhotoListResponse } from '../types/photo'

export interface Album {
  id: string
  name: string
  description: string | null
  cover_photo_id: string | null
  is_smart: boolean
  rules: any[] | null
  photo_count: number
  cover?: string
  created_at: string
  updated_at: string
}

export interface CreateAlbumRequest {
  name: string
  description?: string
  is_smart?: boolean
  rules?: any[]
}

export const albumApi = {
  async getAlbums(): Promise<Album[]> {
    const response = await request.get('/albums/')
    return response.data
  },

  async getAlbum(albumId: string): Promise<Album> {
    const response = await request.get(`/albums/${albumId}`)
    return response.data
  },

  async createAlbum(data: CreateAlbumRequest): Promise<{ message: string; album_id: string; photo_count: number }> {
    const params: Record<string, any> = { name: data.name }
    if (data.description) params.description = data.description
    if (data.is_smart) params.is_smart = data.is_smart
    if (data.rules) params.rules = JSON.stringify(data.rules)
    
    const response = await request.post('/albums/', null, { params })
    return response.data
  },

  async updateAlbum(albumId: string, data: Partial<CreateAlbumRequest>): Promise<{ message: string; album_id: string }> {
    const params: Record<string, any> = {}
    if (data.name) params.name = data.name
    if (data.description !== undefined) params.description = data.description
    if (data.rules) params.rules = JSON.stringify(data.rules)
    
    const response = await request.put(`/albums/${albumId}`, null, { params })
    return response.data
  },

  async deleteAlbum(albumId: string): Promise<void> {
    await request.delete(`/albums/${albumId}`)
  },

  async getAlbumPhotos(albumId: string, page: number = 1, pageSize: number = 20): Promise<PhotoListResponse> {
    const response = await request.get(`/albums/${albumId}/photos`, {
      params: { page, page_size: pageSize }
    })
    return response.data
  },

  async addPhotoToAlbum(albumId: string, photoId: string): Promise<void> {
    await request.post(`/albums/${albumId}/photos/${photoId}`)
  },

  async removePhotoFromAlbum(albumId: string, photoId: string): Promise<void> {
    await request.delete(`/albums/${albumId}/photos/${photoId}`)
  },

  async refreshSmartAlbum(albumId: string): Promise<{ message: string; matched_photos: number }> {
    const response = await request.post(`/albums/${albumId}/refresh`)
    return response.data
  }
}
