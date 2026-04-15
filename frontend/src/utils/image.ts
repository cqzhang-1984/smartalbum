/**
 * 获取图片完整URL
 * 将相对路径转换为可访问的静态文件URL
 */
export function getImageUrl(relativePath: string | undefined | null): string {
  if (!relativePath) return ''
  // 如果已经是完整URL，直接返回
  if (relativePath.startsWith('http://') || relativePath.startsWith('https://')) {
    return relativePath
  }
  // 如果已经包含 /storage/ 前缀，直接返回
  if (relativePath.startsWith('/storage/')) {
    return relativePath
  }
  // 添加 /storage/ 前缀
  return `/storage/${relativePath}`
}
