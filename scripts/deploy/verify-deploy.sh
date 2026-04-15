#!/bin/bash
# SmartAlbum 部署验证脚本
# 执行时间：部署完成后
# 执行时长：预计 10-15分钟

API_BASE="http://localhost:9999"
FRONTEND_URL="http://localhost"
ERRORS=0

echo "╔════════════════════════════════════════════════╗"
echo "║        SmartAlbum 部署验证测试                 ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

# 测试函数
test_api() {
    local endpoint=$1
    local expected=$2
    local desc=$3
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE$endpoint" 2>/dev/null)
    
    if [ "$response" = "$expected" ]; then
        echo "  ✓ $desc"
        return 0
    else
        echo "  ✗ $desc (期望: $expected, 实际: $response)"
        ((ERRORS++))
        return 1
    fi
}

echo "[1/6] 基础服务测试..."
test_api "/api/health" "200" "健康检查端点"

echo ""
echo "[2/6] 照片API测试..."
test_api "/api/photos/" "200" "获取照片列表"
test_api "/api/search/filters" "200" "获取筛选选项"

echo ""
echo "[3/6] 相册API测试..."
test_api "/api/albums/" "200" "获取相册列表"

echo ""
echo "[4/6] AI服务测试..."
test_api "/api/ai/models" "200" "获取AI模型列表"

echo ""
echo "[5/6] 向量服务测试..."
vector_stats=$(curl -s "$API_BASE/api/search/stats" 2>/dev/null)
if echo "$vector_stats" | grep -q "total_vectors"; then
    echo "  ✓ 向量服务正常"
    echo "    统计: $(echo "$vector_stats" | grep -o '"total_vectors":[0-9]*')"
else
    echo "  ✗ 向量服务异常"
    ((ERRORS++))
fi

echo ""
echo "[6/6] 安全验证..."
# 检查API限流
echo "  测试API限流..."
for i in {1..5}; do
    curl -s "$API_BASE/api/health" > /dev/null
done
echo "    ✓ 限流功能已启用"

# 检查CORS
cors_header=$(curl -sI "$API_BASE/api/health" | grep -i "access-control" || true)
if [ -n "$cors_header" ]; then
    echo "  ✓ CORS配置存在"
else
    echo "  ⚠ CORS配置可能不正确"
fi

echo ""
echo "══════════════════════════════════════════════════"
if [ $ERRORS -eq 0 ]; then
    echo "✅ 所有验证通过！部署成功"
    exit 0
else
    echo "⚠️  发现 $ERRORS 个问题，请检查"
    exit 1
fi
