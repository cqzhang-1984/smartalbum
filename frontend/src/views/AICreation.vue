<template>
  <div class="min-h-screen bg-background">
    <!-- 顶部导航栏 -->
    <header class="fixed top-0 left-0 right-0 z-50 glass border-b border-white/10">
      <div class="flex items-center justify-between h-16 px-6">
        <div class="flex items-center space-x-4">
          <button
            @click="router.back()"
            class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
          >
            <ArrowLeft :size="24" class="text-text-secondary" />
          </button>
          
          <h1 class="text-lg font-semibold text-text-primary">AI 创作中心</h1>
        </div>
        
        <div class="flex items-center space-x-4">
          <router-link
            to="/"
            class="p-2 hover:bg-white/10 rounded-lg transition-colors duration-200"
          >
            <Home :size="24" class="text-text-secondary" />
          </router-link>
        </div>
      </div>
    </header>

    <!-- 主内容区 -->
    <main class="pt-20 px-6 max-w-7xl mx-auto pb-8">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- 左侧：生成面板 -->
        <div class="space-y-6">
          <!-- 提示词输入 -->
          <section class="glass rounded-lg p-6">
            <h2 class="text-xl font-semibold text-text-primary mb-4 flex items-center">
              <Sparkles :size="24" class="mr-2 text-primary" />
              创作提示词
            </h2>
            
            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-text-muted mb-2">正向提示词</label>
                <textarea
                  v-model="prompt"
                  rows="4"
                  class="w-full px-4 py-3 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary resize-none"
                  placeholder="描述您想要生成的图片，例如：充满活力的特写编辑肖像，模特眼神犀利，头戴雕塑感帽子..."
                ></textarea>
              </div>
              
              <div>
                <label class="block text-sm font-medium text-text-muted mb-2">负向提示词（可选）</label>
                <textarea
                  v-model="negativePrompt"
                  rows="2"
                  class="w-full px-4 py-3 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary resize-none"
                  placeholder="描述不希望出现的内容，例如：模糊、低质量、变形..."
                ></textarea>
              </div>
            </div>
            
            <div class="flex justify-between items-center mt-3">
              <span class="text-sm text-text-muted">{{ prompt.length }} 字符</span>
              <button
                @click="enhancePrompt"
                :disabled="!prompt || enhancing"
                class="text-sm text-primary hover:text-primary-light disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {{ enhancing ? '优化中...' : 'AI优化提示词' }}
              </button>
            </div>
          </section>
          
          <!-- 生成设置 -->
          <section class="glass rounded-lg p-6">
            <h2 class="text-xl font-semibold text-text-primary mb-4 flex items-center">
              <Settings :size="24" class="mr-2" />
              生成设置
            </h2>
            
            <div class="space-y-4">
              <!-- 模型选择（多个模型时显示） -->
              <div v-if="models.length > 1">
                <label class="block text-sm font-medium text-text-muted mb-2">生成模型</label>
                <div class="grid grid-cols-2 gap-2">
                  <button
                    v-for="model in models"
                    :key="model.id"
                    @click="selectedModel = model.id"
                    :class="[
                      'p-3 rounded-lg border-2 transition-all text-left',
                      selectedModel === model.id 
                        ? 'border-primary bg-primary/10' 
                        : 'border-white/10 hover:border-white/20'
                    ]"
                  >
                    <div class="font-medium text-text-primary text-sm">{{ model.name }}</div>
                    <div class="text-xs text-text-muted mt-1">{{ model.description }}</div>
                  </button>
                </div>
              </div>
              
              <!-- 单个模型时显示当前使用的模型信息 -->
              <div v-else-if="models.length === 1" class="px-4 py-3 bg-background-tertiary/50 rounded-lg">
                <div class="flex items-center justify-between">
                  <span class="text-sm text-text-muted">生成模型</span>
                  <span class="text-sm text-text-primary">{{ models[0].name }}</span>
                </div>
              </div>
              
              <!-- 尺寸选择 -->
              <div>
                <label class="block text-sm font-medium text-text-muted mb-2">图片尺寸</label>
                <div class="grid grid-cols-3 gap-2">
                  <button
                    v-for="size in sizes"
                    :key="size.id"
                    @click="selectedSizeRatio = size.ratio"
                    :class="[
                      'p-3 rounded-lg border-2 transition-all text-center',
                      selectedSizeRatio === size.ratio 
                        ? 'border-primary bg-primary/10' 
                        : 'border-white/10 hover:border-white/20'
                    ]"
                  >
                    <div class="flex justify-center mb-1">
                      <div 
                        :class="[
                          'bg-text-muted rounded',
                          size.ratio === '1:1' ? 'w-6 h-6' : '',
                          size.ratio === '4:3' ? 'w-6 h-4.5' : '',
                          size.ratio === '3:4' ? 'w-4.5 h-6' : '',
                          size.ratio === '16:9' ? 'w-8 h-4.5' : '',
                          size.ratio === '9:16' ? 'w-4.5 h-8' : '',
                          size.ratio === '21:9' ? 'w-10 h-4' : '',
                          size.ratio === '2K' ? 'w-6 h-6' : '',
                          size.ratio === '4K' ? 'w-7 h-7' : '',
                        ]"
                      ></div>
                    </div>
                    <div class="text-xs font-medium text-text-primary">{{ size.name }}</div>
                    <div class="text-xs text-text-muted">{{ size.width }}×{{ size.height }}</div>
                  </button>
                </div>
              </div>
              
              <!-- 输出格式 -->
              <div>
                <label class="block text-sm font-medium text-text-muted mb-2">输出格式</label>
                <select
                  v-model="outputFormat"
                  class="w-full px-4 py-2 bg-background-tertiary border border-white/10 rounded-lg focus:border-primary focus:outline-none text-text-primary"
                >
                  <option value="png">PNG (无损)</option>
                  <option value="jpg">JPG (较小)</option>
                  <option value="webp">WebP (高效)</option>
                </select>
              </div>
            </div>
          </section>
          
          <!-- 生成按钮 -->
          <button
            @click="generateImage"
            :disabled="!prompt || generating"
            class="w-full py-4 bg-primary hover:bg-primary-light disabled:opacity-50 disabled:cursor-not-allowed rounded-lg transition-colors duration-200 flex items-center justify-center space-x-2 text-lg font-semibold"
          >
            <Loader2 v-if="generating" :size="24" class="animate-spin" />
            <Wand2 v-else :size="24" />
            <span>{{ generating ? '生成中...' : '开始创作' }}</span>
          </button>
        </div>
        
        <!-- 右侧：预览和历史 -->
        <div class="space-y-6">
          <!-- 当前生成预览 -->
          <section class="glass rounded-lg p-6">
            <h2 class="text-xl font-semibold text-text-primary mb-4 flex items-center">
              <Image :size="24" class="mr-2" />
              生成预览
            </h2>
            
            <div class="aspect-square bg-background-tertiary rounded-lg overflow-hidden flex items-center justify-center">
              <img
                v-if="currentImage"
                :src="getImageUrl(currentImage)"
                :alt="currentImage.prompt"
                class="max-w-full max-h-full object-contain"
              />
              <div v-else class="text-center text-text-muted">
                <ImageIcon :size="64" class="mx-auto mb-4 opacity-50" />
                <p>生成后将在此显示</p>
              </div>
            </div>
            
            <div v-if="currentImage" class="mt-4 space-y-3">
              <div class="flex items-center justify-between text-sm">
                <span class="text-text-muted">模型: {{ currentImage.model_name || currentImage.model_id }}</span>
                <span class="text-text-muted">尺寸: {{ currentImage.size_display || `${currentImage.width}×${currentImage.height}` }}</span>
              </div>
              
              <div class="flex space-x-3">
                <button
                  @click="saveToAlbum(currentImage.id)"
                  :disabled="currentImage.is_saved"
                  class="flex-1 py-2 bg-primary hover:bg-primary-light disabled:opacity-50 rounded-lg transition-colors duration-200"
                >
                  {{ currentImage.is_saved ? '已保存' : '保存到相册' }}
                </button>
                <button
                  @click="downloadImage(currentImage)"
                  class="flex-1 py-2 bg-background-tertiary hover:bg-background-secondary rounded-lg transition-colors duration-200"
                >
                  下载图片
                </button>
                <button
                  @click="deleteImage(currentImage.id)"
                  class="py-2 px-4 bg-error/20 hover:bg-error/30 text-error rounded-lg transition-colors duration-200"
                >
                  <Trash2 :size="20" />
                </button>
              </div>
            </div>
          </section>
          
          <!-- 历史记录 -->
          <section class="glass rounded-lg p-6">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xl font-semibold text-text-primary flex items-center">
                <History :size="24" class="mr-2" />
                历史记录
              </h2>
              <span class="text-sm text-text-muted">共 {{ historyTotal }} 张</span>
            </div>
            
            <div v-if="historyLoading" class="flex justify-center py-8">
              <Loader2 :size="32" class="animate-spin text-primary" />
            </div>
            
            <div v-else-if="history.length === 0" class="text-center py-8 text-text-muted">
              <History :size="48" class="mx-auto mb-4 opacity-50" />
              <p>暂无生成记录</p>
            </div>
            
            <div v-else class="grid grid-cols-3 gap-3">
              <div
                v-for="img in history"
                :key="img.id"
                class="aspect-square bg-background-tertiary rounded-lg overflow-hidden cursor-pointer hover:ring-2 hover:ring-primary transition-all"
                @click="selectHistoryItem(img)"
              >
                <img
                  v-if="img.local_path"
                  :src="img.local_path"
                  :alt="img.prompt"
                  class="w-full h-full object-cover"
                />
                <div v-else class="w-full h-full flex items-center justify-center">
                  <ImageIcon :size="24" class="text-text-muted" />
                </div>
              </div>
            </div>
            
            <div v-if="historyTotal > history.length" class="mt-4 text-center">
              <button
                @click="loadMoreHistory"
                class="text-sm text-primary hover:text-primary-light"
              >
                加载更多
              </button>
            </div>
          </section>
        </div>
      </div>
    </main>
    
    <!-- 保存成功提示 -->
    <div
      v-if="showSaveSuccess"
      class="fixed bottom-8 left-1/2 -translate-x-1/2 px-6 py-3 bg-success/90 text-white rounded-lg shadow-lg z-50 flex items-center space-x-2"
    >
      <Check :size="20" />
      <span>已保存到相册</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { 
  ArrowLeft, Home, Sparkles, Settings, Image as ImageIcon, 
  History, Loader2, Wand2, Check, Trash2
} from 'lucide-vue-next'
import { aiApi, type ImageGenModel, type ImageGenSize, type GeneratedImage } from '../api/ai'

const router = useRouter()

// 生成参数
const prompt = ref('')
const negativePrompt = ref('')
const selectedModel = ref('')
const selectedSizeRatio = ref('2K')
const outputFormat = ref('png')

// 模型和尺寸选项
const models = ref<ImageGenModel[]>([])
const sizes = ref<ImageGenSize[]>([])

// 状态
const generating = ref(false)
const enhancing = ref(false)
const historyLoading = ref(false)
const showSaveSuccess = ref(false)

// 当前生成的图片
const currentImage = ref<GeneratedImage | null>(null)

// 历史记录
const history = ref<GeneratedImage[]>([])
const historyTotal = ref(0)
const historyPage = ref(1)

onMounted(async () => {
  await loadConfig()
  await loadHistory()
})

async function loadConfig() {
  try {
    const data = await aiApi.getModels()
    models.value = data.models || []
    sizes.value = data.sizes || []
    
    if (data.models?.length > 0) {
      const defaultModel = data.models.find((m: ImageGenModel) => m.is_default) || data.models[0]
      selectedModel.value = defaultModel.id
    }
    
    if (data.sizes?.length > 0) {
      selectedSizeRatio.value = data.sizes[0].ratio
    }
  } catch (error) {
    console.error('Failed to load config:', error)
    // 默认配置
    models.value = [
      { id: 'high_aes_general_v1.3', name: '高美感通用', description: '高质量写实风格' }
    ]
    sizes.value = [
      { id: '1:1', ratio: '1:1', name: '正方形 2048×2048', width: 2048, height: 2048, description: '头像、社交媒体' },
      { id: '16:9', ratio: '16:9', name: '横屏宽屏 2560×1440', width: 2560, height: 1440, description: '视频封面' },
      { id: '9:16', ratio: '9:16', name: '竖屏手机 1440×2560', width: 1440, height: 2560, description: '手机壁纸' },
      { id: '3:4', ratio: '3:4', name: '竖屏标准 1920×2560', width: 1920, height: 2560, description: '人像照' },
      { id: '4:3', ratio: '4:3', name: '横屏标准 2560×1920', width: 2560, height: 1920, description: '电脑壁纸' },
      { id: '2K', ratio: '2K', name: '2K高清 2048×2048', width: 2048, height: 2048, description: '高质量' },
      { id: '4K', ratio: '4K', name: '3K高清 3072×3072', width: 3072, height: 3072, description: '超高分辨率' }
    ]
    selectedModel.value = 'high_aes_general_v1.3'
    selectedSizeRatio.value = '2K'
  }
}

async function generateImage() {
  if (!prompt.value || generating.value) return
  
  generating.value = true
  currentImage.value = null
  
  try {
    const data = await aiApi.generateImage({
      prompt: prompt.value,
      negative_prompt: negativePrompt.value || undefined,
      model_id: selectedModel.value || undefined,
      size_ratio: selectedSizeRatio.value,
      output_format: outputFormat.value
    })
    
    currentImage.value = data as unknown as GeneratedImage
    
    // 刷新历史记录
    await loadHistory()
    
  } catch (error: any) {
    console.error('Generation failed:', error)
    alert(error.response?.data?.detail || error.message || '生成失败，请稍后重试')
  } finally {
    generating.value = false
  }
}

async function enhancePrompt() {
  if (!prompt.value || enhancing.value) return
  
  enhancing.value = true
  try {
    alert('AI优化提示词功能开发中...')
  } catch (error) {
    console.error('Enhance failed:', error)
  } finally {
    enhancing.value = false
  }
}

async function loadHistory() {
  historyLoading.value = true
  try {
    const data = await aiApi.getHistory(1, 9)
    history.value = data.images || []
    historyTotal.value = data.pagination?.total || 0
  } catch (error) {
    console.error('Failed to load history:', error)
  } finally {
    historyLoading.value = false
  }
}

async function loadMoreHistory() {
  historyPage.value++
  historyLoading.value = true
  
  try {
    const data = await aiApi.getHistory(historyPage.value, 9)
    history.value = [...history.value, ...data.images]
  } catch (error) {
    console.error('Failed to load more:', error)
  } finally {
    historyLoading.value = false
  }
}

function selectHistoryItem(img: GeneratedImage) {
  currentImage.value = img
  prompt.value = img.prompt
  negativePrompt.value = img.negative_prompt || ''
}

async function saveToAlbum(imageId: string) {
  try {
    await aiApi.saveToAlbum(imageId)
    
    if (currentImage.value) {
      currentImage.value.is_saved = true
    }
    
    showSaveSuccess.value = true
    setTimeout(() => {
      showSaveSuccess.value = false
    }, 2000)
    
  } catch (error) {
    console.error('Save failed:', error)
    alert('保存失败，请稍后重试')
  }
}

async function deleteImage(imageId: string) {
  if (!confirm('确定要删除这张生成的图片吗？')) return
  
  try {
    await aiApi.deleteGeneratedImage(imageId)
    currentImage.value = null
    await loadHistory()
  } catch (error) {
    console.error('Delete failed:', error)
    alert('删除失败，请稍后重试')
  }
}

function getImageUrl(img: GeneratedImage): string {
  return img.local_path || img.image_url || ''
}

async function downloadImage(img: GeneratedImage) {
  const url = getImageUrl(img)
  if (url) {
    const link = document.createElement('a')
    link.href = url
    link.download = `ai_generated_${img.id}.png`
    link.click()
  }
}
</script>
