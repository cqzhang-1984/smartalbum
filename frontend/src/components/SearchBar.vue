<template>
  <div class="search-bar relative">
    <div class="relative">
      <Search
        :size="20"
        class="absolute left-3 top-1/2 transform -translate-y-1/2 text-text-muted"
      />
      <input
        v-model="searchQuery"
        type="text"
        :placeholder="placeholder"
        class="w-full pl-10 pr-4 py-2.5 bg-background-secondary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary placeholder-text-muted transition-all duration-200"
        @input="handleInput"
        @keyup.enter="handleSearch"
      />
      <button
        v-if="searchQuery"
        @click="clearSearch"
        class="absolute right-3 top-1/2 transform -translate-y-1/2 text-text-muted hover:text-text-secondary transition-colors duration-200"
      >
        <X :size="18" />
      </button>
    </div>
    
    <!-- AI提示 -->
    <div v-if="showAIHint" class="mt-2 flex items-center text-xs text-text-muted">
      <Sparkles :size="14" class="mr-1 text-primary" />
      <span>支持自然语言搜索，如"穿着白色裙子的女孩"</span>
    </div>
    
    <!-- 搜索建议 -->
    <div
      v-if="showSuggestions && suggestions.length > 0"
      class="absolute top-full left-0 right-0 mt-2 glass rounded-lg overflow-hidden z-10"
    >
      <button
        v-for="suggestion in suggestions"
        :key="suggestion"
        @click="selectSuggestion(suggestion)"
        class="w-full px-4 py-2 text-left text-sm text-text-secondary hover:bg-white/5 transition-colors duration-200"
      >
        {{ suggestion }}
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { Search, X, Sparkles } from 'lucide-vue-next'

interface Props {
  placeholder?: string
  showAIHint?: boolean
  suggestions?: string[]
}

const props = withDefaults(defineProps<Props>(), {
  placeholder: '搜索照片...',
  showAIHint: true,
  suggestions: () => []
})

const emit = defineEmits<{
  search: [query: string]
  clear: []
}>()

const searchQuery = ref('')
const showSuggestions = ref(false)

function handleInput() {
  showSuggestions.value = searchQuery.value.length > 0
}

function handleSearch() {
  if (searchQuery.value.trim()) {
    emit('search', searchQuery.value.trim())
    showSuggestions.value = false
  }
}

function clearSearch() {
  searchQuery.value = ''
  showSuggestions.value = false
  emit('clear')
}

function selectSuggestion(suggestion: string) {
  searchQuery.value = suggestion
  handleSearch()
}
</script>
