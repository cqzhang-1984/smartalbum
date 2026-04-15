<template>
  <div class="filter-panel glass rounded-lg p-4">
    <h3 class="text-lg font-semibold text-text-primary mb-4">筛选</h3>
    
    <!-- 时间筛选 -->
    <div class="mb-4">
      <h4 class="text-sm font-medium text-text-muted mb-2">时间</h4>
      <div class="space-y-2">
        <button
          v-for="year in availableYears"
          :key="year"
          @click="toggleYear(year)"
          :class="[
            'w-full px-3 py-2 text-left rounded-lg transition-colors duration-200 text-sm',
            selectedYears.includes(year)
              ? 'bg-primary text-white'
              : 'bg-background-tertiary text-text-secondary hover:bg-background-secondary'
          ]"
        >
          {{ year }}
        </button>
      </div>
    </div>
    
    <!-- 相机筛选 -->
    <div class="mb-4">
      <h4 class="text-sm font-medium text-text-muted mb-2">相机</h4>
      <div class="space-y-2">
        <button
          v-for="camera in cameras"
          :key="camera.model"
          @click="toggleCamera(camera.model)"
          :class="[
            'w-full px-3 py-2 text-left rounded-lg transition-colors duration-200 text-sm flex justify-between items-center',
            selectedCameras.includes(camera.model)
              ? 'bg-primary text-white'
              : 'bg-background-tertiary text-text-secondary hover:bg-background-secondary'
          ]"
        >
          <span>{{ camera.model }}</span>
          <span class="text-xs opacity-70">{{ camera.count }}</span>
        </button>
      </div>
    </div>
    
    <!-- 评分筛选 -->
    <div class="mb-4">
      <h4 class="text-sm font-medium text-text-muted mb-2">评分</h4>
      <div class="flex space-x-2">
        <button
          v-for="i in 5"
          :key="i"
          @click="toggleRating(i)"
          :class="[
            'flex-1 py-2 rounded-lg transition-colors duration-200',
            selectedRatings.includes(i)
              ? 'bg-warning text-background'
              : 'bg-background-tertiary text-text-secondary hover:bg-background-secondary'
          ]"
        >
          <Star
            :size="16"
            :class="selectedRatings.includes(i) ? 'fill-current' : ''"
          />
        </button>
      </div>
    </div>
    
    <!-- 收藏筛选 -->
    <div class="mb-4">
      <button
        @click="toggleFavoritesOnly"
        :class="[
          'w-full px-3 py-2 rounded-lg transition-colors duration-200 text-sm flex items-center space-x-2',
          favoritesOnly
            ? 'bg-danger text-white'
            : 'bg-background-tertiary text-text-secondary hover:bg-background-secondary'
        ]"
      >
        <Heart :size="16" :class="favoritesOnly ? 'fill-current' : ''" />
        <span>仅显示收藏</span>
      </button>
    </div>
    
    <!-- 清除筛选 -->
    <button
      v-if="hasFilters"
      @click="clearFilters"
      class="w-full px-3 py-2 bg-background-tertiary hover:bg-background-secondary rounded-lg transition-colors duration-200 text-sm text-text-secondary"
    >
      清除所有筛选
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { Star, Heart } from 'lucide-vue-next'

interface Camera {
  model: string
  count: number
}

interface Props {
  cameras?: Camera[]
  availableYears?: number[]
  modelValue?: {
    years: number[]
    cameras: string[]
    ratings: number[]
    favoritesOnly: boolean
  }
}

const props = withDefaults(defineProps<Props>(), {
  cameras: () => [],
  availableYears: () => []
})

const emit = defineEmits<{
  filter: [filters: any]
  'update:modelValue': [filters: any]
}>()

const selectedYears = ref<number[]>([])
const selectedCameras = ref<string[]>([])
const selectedRatings = ref<number[]>([])
const favoritesOnly = ref(false)

// 监听外部清除筛选
watch(() => props.modelValue, (newVal) => {
  if (!newVal || (newVal.years.length === 0 && newVal.cameras.length === 0 && newVal.ratings.length === 0 && !newVal.favoritesOnly)) {
    clearFilters()
  }
}, { deep: true })

const hasFilters = computed(() => {
  return selectedYears.value.length > 0 ||
         selectedCameras.value.length > 0 ||
         selectedRatings.value.length > 0 ||
         favoritesOnly.value
})

function toggleYear(year: number) {
  const index = selectedYears.value.indexOf(year)
  if (index > -1) {
    selectedYears.value.splice(index, 1)
  } else {
    selectedYears.value.push(year)
  }
  emitFilters()
}

function toggleCamera(camera: string) {
  const index = selectedCameras.value.indexOf(camera)
  if (index > -1) {
    selectedCameras.value.splice(index, 1)
  } else {
    selectedCameras.value.push(camera)
  }
  emitFilters()
}

function toggleRating(rating: number) {
  const index = selectedRatings.value.indexOf(rating)
  if (index > -1) {
    selectedRatings.value.splice(index, 1)
  } else {
    selectedRatings.value.push(rating)
  }
  emitFilters()
}

function toggleFavoritesOnly() {
  favoritesOnly.value = !favoritesOnly.value
  emitFilters()
}

function clearFilters() {
  selectedYears.value = []
  selectedCameras.value = []
  selectedRatings.value = []
  favoritesOnly.value = false
  emitFilters()
}

function emitFilters() {
  emit('filter', {
    years: selectedYears.value,
    cameras: selectedCameras.value,
    ratings: selectedRatings.value,
    favoritesOnly: favoritesOnly.value
  })
}
</script>
