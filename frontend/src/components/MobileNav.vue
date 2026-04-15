<template>
  <nav class="fixed bottom-0 left-0 right-0 glass border-t border-white/10 md:hidden z-50 safe-area-bottom">
    <div class="flex items-center justify-around py-1">
      <router-link 
        to="/" 
        class="flex flex-col items-center p-2 rounded-lg transition-colors duration-200"
        :class="$route.path === '/' ? 'text-primary' : 'text-text-secondary'"
      >
        <Home :size="22" />
        <span class="text-[10px] mt-0.5">首页</span>
      </router-link>
      
      <router-link 
        to="/albums" 
        class="flex flex-col items-center p-2 rounded-lg transition-colors duration-200"
        :class="$route.path === '/albums' ? 'text-primary' : 'text-text-secondary'"
      >
        <FolderOpen :size="22" />
        <span class="text-[10px] mt-0.5">相册</span>
      </router-link>
      
      <!-- 中央上传按钮 -->
      <button 
        @click="$emit('upload')"
        class="flex flex-col items-center justify-center w-12 h-12 -mt-4 bg-primary rounded-full shadow-lg shadow-primary/30 transition-transform duration-200 active:scale-95"
      >
        <Plus :size="24" class="text-white" />
      </button>
      
      <router-link 
        to="/ai-creation" 
        class="flex flex-col items-center p-2 rounded-lg transition-colors duration-200"
        :class="$route.path === '/ai-creation' ? 'text-primary' : 'text-text-secondary'"
      >
        <Sparkles :size="22" />
        <span class="text-[10px] mt-0.5">AI创作</span>
      </router-link>
      
      <router-link 
        to="/settings" 
        class="flex flex-col items-center p-2 rounded-lg transition-colors duration-200"
        :class="$route.path === '/settings' ? 'text-primary' : 'text-text-secondary'"
      >
        <Settings :size="22" />
        <span class="text-[10px] mt-0.5">设置</span>
      </router-link>
    </div>
  </nav>
</template>

<script setup lang="ts">
import { Home, FolderOpen, Sparkles, Settings, Plus } from 'lucide-vue-next'

defineEmits<{
  upload: []
}>()
</script>