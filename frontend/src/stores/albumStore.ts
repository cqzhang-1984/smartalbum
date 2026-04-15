import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Album } from '../api/album'
import { albumApi, type CreateAlbumRequest } from '../api/album'
import type { Photo } from '../types/photo'

export const useAlbumStore = defineStore('album', () => {
  // State
  const albums = ref<Album[]>([])
  const currentAlbum = ref<Album | null>(null)
  const albumPhotos = ref<Photo[]>([])
  const loading = ref(false)
  const error = ref<string | null>(null)
  const totalPhotos = ref(0)
  const currentPage = ref(1)

  // Actions
  async function fetchAlbums() {
    loading.value = true
    error.value = null
    
    try {
      albums.value = await albumApi.getAlbums()
    } catch (e) {
      error.value = e instanceof Error ? e.message : '加载相册失败'
      console.error('Failed to fetch albums:', e)
    } finally {
      loading.value = false
    }
  }

  async function fetchAlbum(albumId: string) {
    loading.value = true
    error.value = null
    
    try {
      currentAlbum.value = await albumApi.getAlbum(albumId)
    } catch (e) {
      error.value = e instanceof Error ? e.message : '加载相册详情失败'
      console.error('Failed to fetch album:', e)
    } finally {
      loading.value = false
    }
  }

  async function createAlbum(data: CreateAlbumRequest): Promise<string | null> {
    loading.value = true
    error.value = null
    
    try {
      const result = await albumApi.createAlbum(data)
      await fetchAlbums()
      return result.album_id
    } catch (e) {
      error.value = e instanceof Error ? e.message : '创建相册失败'
      console.error('Failed to create album:', e)
      return null
    } finally {
      loading.value = false
    }
  }

  async function updateAlbum(albumId: string, data: Partial<CreateAlbumRequest>) {
    loading.value = true
    error.value = null
    
    try {
      await albumApi.updateAlbum(albumId, data)
      await fetchAlbums()
    } catch (e) {
      error.value = e instanceof Error ? e.message : '更新相册失败'
      console.error('Failed to update album:', e)
    } finally {
      loading.value = false
    }
  }

  async function deleteAlbum(albumId: string) {
    loading.value = true
    error.value = null
    
    try {
      await albumApi.deleteAlbum(albumId)
      albums.value = albums.value.filter(a => a.id !== albumId)
    } catch (e) {
      error.value = e instanceof Error ? e.message : '删除相册失败'
      console.error('Failed to delete album:', e)
    } finally {
      loading.value = false
    }
  }

  async function fetchAlbumPhotos(albumId: string, page: number = 1) {
    loading.value = true
    error.value = null
    
    try {
      const response = await albumApi.getAlbumPhotos(albumId, page, 20)
      
      if (page === 1) {
        albumPhotos.value = response.photos
      } else {
        albumPhotos.value.push(...response.photos)
      }
      
      totalPhotos.value = response.total
      currentPage.value = page
    } catch (e) {
      error.value = e instanceof Error ? e.message : '加载相册照片失败'
      console.error('Failed to fetch album photos:', e)
    } finally {
      loading.value = false
    }
  }

  async function addPhotoToAlbum(albumId: string, photoId: string) {
    try {
      await albumApi.addPhotoToAlbum(albumId, photoId)
      const album = albums.value.find(a => a.id === albumId)
      if (album) {
        album.photo_count++
      }
    } catch (e) {
      console.error('Failed to add photo to album:', e)
    }
  }

  async function removePhotoFromAlbum(albumId: string, photoId: string) {
    try {
      await albumApi.removePhotoFromAlbum(albumId, photoId)
      albumPhotos.value = albumPhotos.value.filter(p => p.id !== photoId)
      const album = albums.value.find(a => a.id === albumId)
      if (album) {
        album.photo_count = Math.max(0, album.photo_count - 1)
      }
    } catch (e) {
      console.error('Failed to remove photo from album:', e)
    }
  }

  async function refreshSmartAlbum(albumId: string) {
    loading.value = true
    error.value = null
    
    try {
      const result = await albumApi.refreshSmartAlbum(albumId)
      await fetchAlbums()
      return result.matched_photos
    } catch (e) {
      error.value = e instanceof Error ? e.message : '刷新智能相册失败'
      console.error('Failed to refresh smart album:', e)
      return 0
    } finally {
      loading.value = false
    }
  }

  function clearCurrentAlbum() {
    currentAlbum.value = null
    albumPhotos.value = []
    totalPhotos.value = 0
    currentPage.value = 1
  }

  return {
    albums,
    currentAlbum,
    albumPhotos,
    loading,
    error,
    totalPhotos,
    currentPage,
    fetchAlbums,
    fetchAlbum,
    createAlbum,
    updateAlbum,
    deleteAlbum,
    fetchAlbumPhotos,
    addPhotoToAlbum,
    removePhotoFromAlbum,
    refreshSmartAlbum,
    clearCurrentAlbum
  }
})
