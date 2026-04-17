/**
 * SmartAlbum 前端配置中心
 * 集中管理所有环境配置和常量
 */

// ==========================================
// 环境配置类型定义
// ==========================================
export interface AppConfig {
  // 基础信息
  readonly appTitle: string
  readonly appVersion: string
  readonly appEnv: 'development' | 'staging' | 'production'

  // API 配置
  readonly apiBaseUrl: string
  readonly requestTimeout: number

  // 功能开关
  readonly features: {
    readonly enableAI: boolean
    readonly enableFaceRecognition: boolean
    readonly enableSemanticSearch: boolean
    readonly enableImageGeneration: boolean
    readonly enableDebug: boolean
  }

  // 性能配置
  readonly performance: {
    readonly lazyLoadThreshold: number
    readonly thumbnailQuality: number
    readonly pageSize: number
    readonly uploadConcurrency: number
  }

  // 用户体验
  readonly ux: {
    readonly previewMaxWidth: number
    readonly autoSaveInterval: number
    readonly messageDuration: number
  }

  // 安全配置
  readonly security: {
    readonly maxUploadSize: number // MB
    readonly allowedFileTypes: string[]
  }
}

// ==========================================
// 配置解析工具
// =========================================

/**
 * 解析布尔值配置
 */
function parseBoolean(value: string | undefined, defaultValue: boolean): boolean {
  if (value === undefined) return defaultValue
  return value.toLowerCase() === 'true'
}

/**
 * 解析数值配置
 */
function parseNumber(value: string | undefined, defaultValue: number): number {
  if (value === undefined) return defaultValue
  const parsed = parseInt(value, 10)
  return isNaN(parsed) ? defaultValue : parsed
}

/**
 * 解析数组配置
 */
function parseArray(value: string | undefined, defaultValue: string[]): string[] {
  if (value === undefined) return defaultValue
  return value.split(',').map(item => item.trim()).filter(Boolean)
}

// ==========================================
// 配置验证
// ==========================================

class ConfigValidator {
  private errors: string[] = []

  /**
   * 验证数值范围
   */
  range(name: string, value: number, min: number, max: number): void {
    if (value < min || value > max) {
      this.errors.push(`配置错误: ${name}=${value} 超出有效范围 [${min}, ${max}]`)
    }
  }

  /**
   * 验证必填项
   */
  required(name: string, value: string | undefined): void {
    if (!value || value.trim() === '') {
      this.errors.push(`配置错误: ${name} 不能为空`)
    }
  }

  /**
   * 验证 URL 格式
   */
  url(name: string, value: string): void {
    try {
      new URL(value)
    } catch {
      // 相对路径以 / 开头也是有效的
      if (!value.startsWith('/')) {
        this.errors.push(`配置错误: ${name}=${value} 不是有效的 URL`)
      }
    }
  }

  /**
   * 获取验证结果
   */
  getErrors(): string[] {
    return this.errors
  }

  /**
   * 是否验证通过
   */
  isValid(): boolean {
    return this.errors.length === 0
  }

  /**
   * 抛出验证错误
   */
  throwIfInvalid(): void {
    if (!this.isValid()) {
      throw new Error(`配置验证失败:\n${this.errors.join('\n')}`)
    }
  }
}

// ==========================================
// 构建配置对象
// ==========================================

const validator = new ConfigValidator()

// 验证必填项
validator.required('VITE_APP_TITLE', import.meta.env.VITE_APP_TITLE)
validator.required('VITE_API_BASE_URL', import.meta.env.VITE_API_BASE_URL)

// 解析功能开关
const features = {
  enableAI: parseBoolean(import.meta.env.VITE_ENABLE_AI, true),
  enableFaceRecognition: parseBoolean(import.meta.env.VITE_ENABLE_FACE_RECOGNITION, true),
  enableSemanticSearch: parseBoolean(import.meta.env.VITE_ENABLE_SEMANTIC_SEARCH, true),
  enableImageGeneration: parseBoolean(import.meta.env.VITE_ENABLE_IMAGE_GENERATION, true),
  enableDebug: parseBoolean(import.meta.env.VITE_ENABLE_DEBUG, false)
}

// 解析性能配置
const performance = {
  lazyLoadThreshold: parseNumber(import.meta.env.VITE_LAZY_LOAD_THRESHOLD, 300),
  thumbnailQuality: parseNumber(import.meta.env.VITE_THUMBNAIL_QUALITY, 85),
  pageSize: parseNumber(import.meta.env.VITE_PAGE_SIZE, 20),
  uploadConcurrency: parseNumber(import.meta.env.VITE_UPLOAD_CONCURRENCY, 3)
}

// 验证性能配置范围
validator.range('VITE_THUMBNAIL_QUALITY', performance.thumbnailQuality, 1, 100)
validator.range('VITE_PAGE_SIZE', performance.pageSize, 1, 100)
validator.range('VITE_UPLOAD_CONCURRENCY', performance.uploadConcurrency, 1, 10)

// 解析用户体验配置
const ux = {
  previewMaxWidth: parseNumber(import.meta.env.VITE_PREVIEW_MAX_WIDTH, 1920),
  autoSaveInterval: parseNumber(import.meta.env.VITE_AUTO_SAVE_INTERVAL, 30000),
  messageDuration: parseNumber(import.meta.env.VITE_MESSAGE_DURATION, 3000)
}

// 解析安全配置
const security = {
  maxUploadSize: parseNumber(import.meta.env.VITE_MAX_UPLOAD_SIZE, 50),
  allowedFileTypes: parseArray(import.meta.env.VITE_ALLOWED_FILE_TYPES, ['jpg', 'jpeg', 'png', 'gif', 'webp'])
}

validator.range('VITE_MAX_UPLOAD_SIZE', security.maxUploadSize, 1, 500)

// 构建完整配置
export const config: AppConfig = {
  appTitle: import.meta.env.VITE_APP_TITLE || 'SmartAlbum',
  appVersion: import.meta.env.VITE_APP_VERSION || '1.0.0',
  appEnv: (import.meta.env.VITE_APP_ENV as AppConfig['appEnv']) || 'development',

  apiBaseUrl: import.meta.env.VITE_API_BASE_URL || 'http://localhost:9999',
  requestTimeout: parseNumber(import.meta.env.VITE_REQUEST_TIMEOUT, 30000),

  features,
  performance,
  ux,
  security
}

// 验证 URL
validator.url('VITE_API_BASE_URL', config.apiBaseUrl)

// 开发环境打印验证错误
if (config.appEnv === 'development') {
  if (!validator.isValid()) {
    console.warn('⚠️ 配置验证警告:', validator.getErrors())
  } else {
    console.log('✅ 配置验证通过')
  }
}

// 生产环境抛出错误
if (config.appEnv === 'production') {
  validator.throwIfInvalid()
}

// ==========================================
// 便捷导出
// ==========================================

export const {
  appTitle,
  appVersion,
  appEnv,
  apiBaseUrl,
  requestTimeout,
  features,
  performance,
  ux,
  security
} = config

export default config

// ==========================================
// 配置工具函数
// ==========================================

/**
 * 检查功能是否启用
 */
export function isFeatureEnabled(featureName: keyof typeof features): boolean {
  return features[featureName]
}

/**
 * 获取图片完整 URL
 */
export function getImageUrl(path: string): string {
  if (path.startsWith('http')) return path
  return `${apiBaseUrl}/storage/${path.replace(/^\//, '')}`
}

/**
 * 获取 API URL
 */
export function getApiUrl(endpoint: string): string {
  const base = apiBaseUrl.endsWith('/') ? apiBaseUrl.slice(0, -1) : apiBaseUrl
  const path = endpoint.startsWith('/') ? endpoint : `/${endpoint}`
  return `${base}/api${path}`
}

/**
 * 检查文件类型是否允许
 */
export function isAllowedFileType(filename: string): boolean {
  const ext = filename.split('.').pop()?.toLowerCase() || ''
  return security.allowedFileTypes.includes(ext)
}

/**
 * 检查文件大小是否合法
 */
export function isValidFileSize(sizeBytes: number): boolean {
  const sizeMB = sizeBytes / (1024 * 1024)
  return sizeMB <= security.maxUploadSize
}
