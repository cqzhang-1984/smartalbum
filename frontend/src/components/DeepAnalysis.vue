<template>
  <div class="deep-analysis-panel glass rounded-xl p-8 animate-fade-in">
    <!-- 标题栏 -->
    <div class="flex items-center justify-between mb-6">
      <h3 class="text-base font-semibold text-text-primary flex items-center gap-2.5">
        <span class="flex items-center justify-center w-7 h-7 rounded-lg bg-primary/15">
          <Sparkles :size="16" class="text-primary" />
        </span>
        AI深度分析
      </h3>
      <button
        v-if="report && !isAnalyzing"
        @click="$emit('analyze')"
        class="px-3 py-1.5 text-xs text-text-muted hover:text-primary hover:bg-primary/10 rounded-lg transition-all duration-200 flex items-center gap-1.5"
        title="重新分析"
      >
        <RefreshCw :size="12" />
        重新分析
      </button>
    </div>

    <!-- 未生成：显示生成按钮 -->
    <div v-if="!report && !isAnalyzing" class="text-center py-10">
      <div class="inline-flex flex-col items-center">
        <span class="flex items-center justify-center w-14 h-14 rounded-2xl bg-primary/10 mb-4">
          <Sparkles :size="28" class="text-primary/70" />
        </span>
        <p class="text-sm text-text-secondary mb-5">生成专业级人像摄影深度分析报告</p>
        <button
          @click="$emit('analyze')"
          class="group px-6 py-2.5 bg-primary/20 hover:bg-primary/30 text-primary rounded-lg text-sm font-medium transition-all duration-300 hover:shadow-lg hover:shadow-primary/10 inline-flex items-center gap-2"
        >
          <Sparkles :size="16" class="group-hover:rotate-12 transition-transform duration-300" />
          生成深度分析报告
        </button>
      </div>
    </div>

    <!-- 分析中：显示loading -->
    <div v-else-if="isAnalyzing" class="text-center py-10">
      <div class="inline-flex items-center gap-4">
        <div class="relative">
          <div class="animate-spin">
            <Loader2 :size="28" class="text-primary" />
          </div>
          <div class="absolute inset-0 animate-ping opacity-20">
            <Loader2 :size="28" class="text-primary" />
          </div>
        </div>
        <div class="text-left">
          <p class="text-sm text-text-primary font-medium">AI正在后台深度分析中</p>
          <p class="text-xs text-text-muted mt-1">预计需要1-3分钟，分析完成后将自动显示...</p>
        </div>
      </div>
      <div class="mt-5 max-w-sm mx-auto bg-background-secondary rounded-full h-1 overflow-hidden">
        <div class="h-full rounded-full shimmer-bar" style="width: 70%"></div>
      </div>
    </div>

    <!-- 已生成：显示Markdown报告 -->
    <div v-else-if="report" class="deep-analysis-report">
      <div class="flex items-center gap-3 mb-5 pb-4 border-b border-white/5">
        <span v-if="analysisTime" class="text-xs text-text-muted flex items-center gap-1.5">
          <Clock :size="12" />
          分析于 {{ formatTime(analysisTime) }}
        </span>
      </div>
      <div class="deep-analysis-content" v-html="renderedHtml"></div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, watch } from 'vue'
import { marked } from 'marked'
import { Sparkles, Loader2, RefreshCw, Clock } from 'lucide-vue-next'

const props = defineProps<{
  report: string | null | undefined
  analysisTime: string | null | undefined
  isAnalyzing: boolean
}>()

// 调试：监听 props 变化
watch(() => props.report, (newVal) => {
  console.log('[DeepAnalysis] report changed:', {
    hasValue: !!newVal,
    type: typeof newVal,
    length: typeof newVal === 'string' ? newVal.length : 0,
    preview: typeof newVal === 'string' ? newVal.substring(0, 100) : newVal
  })
}, { immediate: true })

watch(() => props.isAnalyzing, (newVal) => {
  console.log('[DeepAnalysis] isAnalyzing changed:', newVal)
}, { immediate: true })

defineEmits<{
  analyze: []
}>()

// 配置marked
marked.setOptions({
  breaks: true,
  gfm: true
})

const renderedHtml = computed(() => {
  if (!props.report) return ''
  return marked.parse(props.report) as string
})

function formatTime(isoStr: string): string {
  try {
    const date = new Date(isoStr)
    return date.toLocaleString('zh-CN', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    })
  } catch {
    return isoStr
  }
}
</script>

<style scoped>
.deep-analysis-panel {
  position: relative;
  overflow: hidden;
}

.deep-analysis-panel::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--primary, #818cf8) 30%, var(--primary, #818cf8) 70%, transparent);
  opacity: 0.3;
}

.deep-analysis-content {
  font-size: 0.9375rem;
  line-height: 1.9;
  color: var(--text-secondary, #a0aec0);
  max-width: 72rem;
  columns: 1;
}

.deep-analysis-content :deep(h2) {
  font-size: 1.125rem;
  font-weight: 600;
  color: var(--primary, #818cf8);
  margin-top: 1.75rem;
  margin-bottom: 0.75rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  break-after: avoid;
  column-span: all;
}

.deep-analysis-content :deep(h2:first-child) {
  margin-top: 0;
}

.deep-analysis-content :deep(h3) {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-primary, #e2e8f0);
  margin-top: 1.25rem;
  margin-bottom: 0.5rem;
  break-after: avoid;
}

.deep-analysis-content :deep(p) {
  margin: 0.5rem 0;
}

.deep-analysis-content :deep(ul),
.deep-analysis-content :deep(ol) {
  padding-left: 1.5rem;
  margin: 0.5rem 0;
}

.deep-analysis-content :deep(li) {
  margin: 0.25rem 0;
}

.deep-analysis-content :deep(li::marker) {
  color: var(--primary, #818cf8);
}

.deep-analysis-content :deep(strong) {
  color: var(--primary, #818cf8);
  font-weight: 600;
}

.deep-analysis-content :deep(code) {
  background: rgba(255, 255, 255, 0.06);
  padding: 0.125rem 0.375rem;
  border-radius: 0.25rem;
  font-size: 0.8125rem;
}

.deep-analysis-content :deep(blockquote) {
  border-left: 3px solid var(--primary, #818cf8);
  padding-left: 1rem;
  margin: 0.875rem 0;
  opacity: 0.85;
}

.deep-analysis-content :deep(hr) {
  border: none;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
  margin: 1.25rem 0;
}

.shimmer-bar {
  background: linear-gradient(
    90deg,
    var(--primary, #818cf8) 0%,
    rgba(129, 140, 248, 0.4) 50%,
    var(--primary, #818cf8) 100%
  );
  background-size: 200% 100%;
  animation: shimmer 2s ease-in-out infinite;
}

@keyframes shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

@keyframes fade-in {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-fade-in {
  animation: fade-in 0.4s ease-out;
}
</style>
