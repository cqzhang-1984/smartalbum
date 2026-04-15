# SmartAlbum 服务停止脚本

param(
    [switch]$Force
)

$BACKEND_PORT = 9000
$FRONTEND_PORT = 5173

function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }

function Stop-ProcessOnPort {
    param([int]$Port)
    try {
        $connections = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING"
        if ($connections) {
            foreach ($conn in $connections) {
                $parts = $conn -split '\s+'
                $pid = $parts[-1]
                if ($pid -match '^\d+$' -and $pid -ne '0') {
                    Write-Warning "停止端口 $Port 的进程 (PID: $pid)..."
                    Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue
                    return $true
                }
            }
        }
        return $false
    } catch {
        return $false
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     停止 SmartAlbum 服务" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$stopped = $false

if (Stop-ProcessOnPort -Port $BACKEND_PORT) {
    Write-Success "后端服务已停止"
    $stopped = $true
}

if (Stop-ProcessOnPort -Port $FRONTEND_PORT) {
    Write-Success "前端服务已停止"
    $stopped = $true
}

if (-not $stopped) {
    Write-Info "没有运行中的服务"
}

Write-Host ""
