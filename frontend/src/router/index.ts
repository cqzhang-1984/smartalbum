import { createRouter, createWebHistory } from 'vue-router'
import type { RouteRecordRaw, NavigationGuardNext, RouteLocationNormalized } from 'vue-router'
import { useAuthStore } from '../stores/authStore'

const routes: RouteRecordRaw[] = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('../views/LoginView.vue'),
    meta: { title: '登录', public: true }
  },
  {
    path: '/',
    name: 'Gallery',
    component: () => import('../views/PhotoGallery.vue'),
    meta: { title: '照片墙', requiresAuth: true }
  },
  {
    path: '/photo/:id',
    name: 'PhotoDetail',
    component: () => import('../views/PhotoDetail.vue'),
    meta: { title: '照片详情', requiresAuth: true }
  },
  {
    path: '/albums',
    name: 'Albums',
    component: () => import('../views/Albums.vue'),
    meta: { title: '智能相册', requiresAuth: true }
  },
  {
    path: '/ai-creation',
    name: 'AICreation',
    component: () => import('../views/AICreation.vue'),
    meta: { title: 'AI创作中心', requiresAuth: true }
  },
  {
    path: '/settings',
    name: 'Settings',
    component: () => import('../views/Settings.vue'),
    meta: { title: '系统设置', requiresAuth: true }
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

// 路由守卫
router.beforeEach(async (to: RouteLocationNormalized, _from: RouteLocationNormalized, next: NavigationGuardNext) => {
  // 设置页面标题
  document.title = `${to.meta.title || 'SmartAlbum'} - SmartAlbum`
  
  // 公开页面直接放行
  if (to.meta.public) {
    next()
    return
  }
  
  // 检查是否需要认证
  if (to.meta.requiresAuth) {
    const authStore = useAuthStore()
    const isAuthenticated = await authStore.checkAuth()
    
    if (!isAuthenticated) {
      next('/login')
      return
    }
  }
  
  next()
})

export default router
