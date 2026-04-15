import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath } from 'url'
import { dirname } from 'path'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  // 加载环境变量
  const env = loadEnv(mode, __dirname, '')
  // 默认代理到后端 9999 端口
  const apiBaseUrl = env.VITE_API_BASE_URL || 'http://localhost:9999'

  return {
    plugins: [vue()],
    server: {
      host: '0.0.0.0',
      port: 8888,
      allowedHosts: true,
      proxy: {
        '/api': {
          target: apiBaseUrl,
          changeOrigin: true,
        },
        '/storage': {
          target: apiBaseUrl,
          changeOrigin: true,
        },
      },
    },
  }
})
