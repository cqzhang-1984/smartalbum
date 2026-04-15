<template>
  <div 
    class="photo-card group relative overflow-hidden rounded-lg bg-background-secondary cursor-pointer"
    :class="{ 'ring-2 ring-primary': selectable && selected }"
  >
    <div class="aspect-[3/4] relative">
      <img
        :src="photoUrl"
        :alt="photo.filename"
        class="w-full h-full object-cover transition-transform duration-300 group-hover:scale-110"
        :class="{ 'opacity-70': selectable && selected }"
        loading="lazy"
        @click="handleClick"
      />
      
      <!-- 加载占位 -->
      <div v-if="!loaded" class="absolute inset-0 bg-background-tertiary animate-pulse"></div>
      
      <!-- 选择模式下显示勾选图标 -->
      <div 
        v-if="selectable"
        class="absolute top-2 left-2 z-10"
        @click.stop
      >
        <div 
          :class="[
            'w-6 h-6 rounded-full flex items-center justify-center transition-all duration-200',
            selected 
              ? 'bg-primary text-white' 
              : 'bg-black/50 text-transparent group-hover:text-white/50'
          ]"
        >
          <Check :size="16" />
        </div>
      </div>
      
      <!-- 删除按钮 - 非选择模式下显示 -->
      <div 
        v-if="!selectable"
        class="absolute top-2 left-2 z-10 opacity-0 group-hover:opacity-100 transition-opacity duration-300"
        @click.stop
        @mousedown.stop
        @pointerdown.stop
      >
        <button
          @click.stop.prevent="handleDelete"
          class="p-2 bg-black/60 hover:bg-danger rounded-lg transition-all duration-200"
          title="删除照片"
        >
          <Trash2 :size="16" class="text-white" />
        </button>
      </div>
      
      <!-- 悬停遮罩 -->
      <div class="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
        <div class="absolute bottom-0 left-0 right-0 p-4">
          <!-- EXIF信息 -->
          <div class="mb-2">
            <p v-if="photo.camera_model" class="text-sm text-text-primary truncate">
              {{ photo.camera_model }}
            </p>
            <p v-if="photo.shot_time" class="text-xs text-text-muted">
              {{ formatDate(photo.shot_time) }}
            </p>
          </div>
          
          <!-- 评分和收藏 -->
          <div class="flex items-center justify-between">
            <div class="flex space-x-0.5">
              <Star
                v-for="i in 5"
                :key="i"
                :size="14"
                :class="i <= photo.rating ? 'text-warning fill-warning' : 'text-text-muted'"
              />
            </div>
            <Heart
              :size="18"
              :class="photo.is_favorite ? 'text-danger fill-danger' : 'text-text-secondary'"
            />
          </div>
        </div>
      </div>
    </div>
    
    <!-- AI标签预览 -->
    <div v-if="photo.ai_tags && Object.keys(photo.ai_tags).length > 0" class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
      <div class="flex flex-wrap gap-1">
        <span
          v-if="photo.ai_tags.subject_emotion"
          class="px-2 py-1 bg-primary/80 text-white text-xs rounded-full backdrop-blur-sm"
        >
          {{ photo.ai_tags.subject_emotion }}
        </span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import type { Photo } from '../types/photo'
import { Star, Heart, Trash2, Check } from 'lucide-vue-next'
import { getImageUrl } from '../utils/image'

interface Props {
  photo: Photo
  selectable?: boolean
  selected?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  selectable: false,
  selected: false
})

const emit = defineEmits<{
  (e: 'delete', photoId: string): void
  (e: 'toggle-selection', photoId: string): void
}>()

const loaded = ref(false)

// 优先使用后端返回的完整URL，其次使用本地路径
const photoUrl = computed(() => {
  // 优先使用后端生成的URL（支持COS）
  if (props.photo.thumbnail_medium_url) {
    return props.photo.thumbnail_medium_url
  }
  if (props.photo.thumbnail_small_url) {
    return props.photo.thumbnail_small_url
  }
  // 兼容本地存储
  return getImageUrl(props.photo.thumbnail_medium || props.photo.thumbnail_small)
})

onMounted(() => {
  const img = new Image()
  img.src = photoUrl.value || ''
  img.onload = () => {
    loaded.value = true
  }
})

function formatDate(dateStr: string): string {
  const date = new Date(dateStr)
  return date.toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  })
}

function handleDelete() {
  if (confirm(`确定要删除照片"${props.photo.filename}"吗？`)) {
    emit('delete', props.photo.id)
  }
}

function handleClick() {
  if (props.selectable) {
    emit('toggle-selection', props.photo.id)
  }
}
</script>

<style scoped>
.photo-card {
  break-inside: avoid;
  margin-bottom: 1rem;
}
</style>
