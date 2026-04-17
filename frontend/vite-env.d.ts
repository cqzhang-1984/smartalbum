/// <reference types="vite/client" />

/**
 * SmartAlbum 前端环境变量类型声明
 * 所有以 VITE_ 开头的环境变量都需要在此处声明类型
 */

interface ImportMetaEnv {
  // ==========================================
  // 基础配置
  // ==========================================
  /** 应用标题 */
  readonly VITE_APP_TITLE: string
  /** 应用版本号 */
  readonly VITE_APP_VERSION: string
  /** 应用环境标识 (development | staging | production) */
  readonly VITE_APP_ENV: 'development' | 'staging' | 'production'
  /** API 基础地址 */
  readonly VITE_API_BASE_URL: string

  // ==========================================
  // 功能开关
  // ==========================================
  /** 是否启用 AI 功能 */
  readonly VITE_ENABLE_AI: string
  /** 是否启用人脸识别 */
  readonly VITE_ENABLE_FACE_RECOGNITION: string
  /** 是否启用语义搜索 */
  readonly VITE_ENABLE_SEMANTIC_SEARCH: string
  /** 是否启用图片生成 */
  readonly VITE_ENABLE_IMAGE_GENERATION: string
  /** 是否启用调试工具 */
  readonly VITE_ENABLE_DEBUG: string

  // ==========================================
  // 性能配置
  // ==========================================
  /** 图片懒加载阈值（像素） */
  readonly VITE_LAZY_LOAD_THRESHOLD: string
  /** 缩略图默认质量 (0-100) */
  readonly VITE_THUMBNAIL_QUALITY: string
  /** 列表分页大小 */
  readonly VITE_PAGE_SIZE: string
  /** 上传并发数 */
  readonly VITE_UPLOAD_CONCURRENCY: string

  // ==========================================
  // 用户体验配置
  // ==========================================
  /** 预览图最大宽度 */
  readonly VITE_PREVIEW_MAX_WIDTH: string
  /** 自动保存间隔（毫秒） */
  readonly VITE_AUTO_SAVE_INTERVAL: string
  /** 消息提示持续时间（毫秒） */
  readonly VITE_MESSAGE_DURATION: string

  // ==========================================
  // 安全配置
  // ==========================================
  /** 请求超时时间（毫秒） */
  readonly VITE_REQUEST_TIMEOUT: string
  /** 最大上传文件大小（MB） */
  readonly VITE_MAX_UPLOAD_SIZE: string
  /** 允许的文件类型（逗号分隔） */
  readonly VITE_ALLOWED_FILE_TYPES: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
