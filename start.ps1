# SmartAlbum Service Start Script (PowerShell)
# Usage: 
#   .\start.ps1              # Start all services
#   .\start.ps1 -Backend     # Start backend only
#   .\start.ps1 -Frontend    # Start frontend only
#   .\start.ps1 -Stop        # Stop all services
#   .\start.ps1 -Status      # Check port status
#   .\start.ps1 -Restart     # Restart all services
#   .\start.ps1 -Action all  # Start all services (alternative)

param(
    [switch]$Backend,
    [switch]$Frontend,
    [switch]$Stop,
    [switch]$Status,
    [switch]$Restart,
    [string]$Action
)

$ErrorActionPreference = "Continue"

# Config
$BACKEND_PORT = 9999
$FRONTEND_PORT = 8888  # 与 vite.config.ts 保持一致
$PROJECT_ROOT = $PSScriptRoot
$BACKEND_DIR = Join-Path $PROJECT_ROOT "backend"
$FRONTEND_DIR = Join-Path $PROJECT_ROOT "frontend"
$LOGS_DIR = Join-Path $PROJECT_ROOT "logs"

# Ensure logs directory exists
if (-not (Test-Path $LOGS_DIR)) {
    New-Item -ItemType Directory -Path $LOGS_DIR -Force | Out-Null
}

# Try multiple possible venv locations (backend/venv is preferred)
$VENV_PATHS = @(
    (Join-Path $BACKEND_DIR "venv\Scripts\python.exe"),
    (Join-Path $PROJECT_ROOT "venv\Scripts\python.exe")
)

function Get-VenvPython {
    foreach ($path in $VENV_PATHS) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

$VENV_PYTHON = Get-VenvPython

function Write-Info { 
    param($msg) 
    Write-Host "[INFO] $msg" -ForegroundColor Cyan 
}

function Write-Success { 
    param($msg) 
    Write-Host "[OK] $msg" -ForegroundColor Green 
}

function Write-Warning { 
    param($msg) 
    Write-Host "[WARN] $msg" -ForegroundColor Yellow 
}

function Write-ErrorMsg { 
    param($msg) 
    Write-Host "[ERROR] $msg" -ForegroundColor Red 
}

function Get-AllPidsOnPort {
    param([int]$Port)
    try {
        $pids = @()
        $connections = netstat -ano | Select-String ":$Port\s"
        foreach ($conn in $connections) {
            $parts = $conn -split '\s+'
            $pid = $parts[-1]
            if ($pid -match '^\d+$' -and $pid -ne '0') {
                $pids += [int]$pid
            }
        }
        return $pids | Select-Object -Unique
    } catch {
        return @()
    }
}

function Get-ListeningPidOnPort {
    param([int]$Port)
    try {
        $connections = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING"
        if ($connections) {
            foreach ($conn in $connections) {
                $parts = $conn -split '\s+'
                $pid = $parts[-1]
                if ($pid -match '^\d+$' -and $pid -ne '0') {
                    return [int]$pid
                }
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Get-ProcessNameByPid {
    param([int]$Pid)
    try {
        $process = Get-Process -Id $Pid -ErrorAction SilentlyContinue
        if ($process) {
            return $process.ProcessName
        }
        return "Unknown"
    } catch {
        return "Unknown"
    }
}

function Show-PortStatus {
    param([int]$Port, [string]$ServiceName)
    $processPid = Get-ListeningPidOnPort -Port $Port
    if ($processPid) {
        $processName = Get-ProcessNameByPid -Pid $processPid
        Write-Host "  $ServiceName (Port $Port): " -NoNewline
        Write-Host "OCCUPIED by $processName (PID:$processPid)" -ForegroundColor Yellow
        return $true
    } else {
        Write-Host "  $ServiceName (Port $Port): " -NoNewline
        Write-Host "AVAILABLE" -ForegroundColor Green
        return $false
    }
}

function Show-AllPortStatus {
    Write-Info "Port Status Check:"
    $backendOccupied = Show-PortStatus -Port $BACKEND_PORT -ServiceName "Backend "
    $frontendOccupied = Show-PortStatus -Port $FRONTEND_PORT -ServiceName "Frontend"
    Write-Host ""
    return @{Backend = $backendOccupied; Frontend = $frontendOccupied}
}

function Stop-ProcessOnPort {
    param(
        [int]$Port, 
        [string]$ServiceName,
        [int]$MaxRetries = 5,
        [switch]$Graceful
    )
    
    $retry = 0
    while ($retry -lt $MaxRetries) {
        $allPids = Get-AllPidsOnPort -Port $Port
        $listeningPid = Get-ListeningPidOnPort -Port $Port
        
        if (-not $listeningPid -and $allPids.Count -eq 0) {
            return $true
        }
        
        # Kill all processes related to this port
        $killedAny = $false
        foreach ($pid in $allPids) {
            $processName = Get-ProcessNameByPid -Pid $pid
            if ($processName -ne "Unknown") {
                Write-Warning "Stopping $processName (PID:$pid) on port $Port..."
                try {
                    if ($Graceful -and $retry -eq 0) {
                        # 第一次尝试优雅关闭
                        $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
                        if ($process) {
                            $process.CloseMainWindow() | Out-Null
                            Start-Sleep -Milliseconds 500
                        }
                    }
                    # 强制关闭
                    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                    $killedAny = $true
                } catch {
                    Write-ErrorMsg "Failed to stop process $pid"
                }
            }
        }
        
        if ($killedAny) {
            Start-Sleep -Milliseconds 800
        }
        
        # Check if port is now free
        $listeningPid = Get-ListeningPidOnPort -Port $Port
        if (-not $listeningPid) {
            Write-Success "Port $Port is now free"
            return $true
        }
        
        $retry++
        if ($retry -lt $MaxRetries) {
            Write-Warning "Retry $retry/$MaxRetries for port $Port..."
            Start-Sleep -Seconds 1
        }
    }
    
    $stillListening = Get-ListeningPidOnPort -Port $Port
    if ($stillListening) {
        Write-ErrorMsg "Failed to free port $Port after $MaxRetries attempts"
        return $false
    }
    return $true
}

function Stop-AllServices {
    Write-Info "Stopping all services..."
    Stop-ProcessOnPort -Port $BACKEND_PORT -ServiceName "Backend"
    Stop-ProcessOnPort -Port $FRONTEND_PORT -ServiceName "Frontend"
    Write-Success "All services stopped"
}

function Test-Environment {
    Write-Info "Checking environment..."
    
    # Check .env file
    $envFile = Join-Path $BACKEND_DIR ".env"
    if (-not (Test-Path $envFile)) {
        Write-Warning ".env file not found in backend directory"
        Write-Info "Please create backend/.env file with required configuration"
    } else {
        Write-Success ".env file exists"
    }
    
    # Check venv
    if (-not $VENV_PYTHON) {
        Write-ErrorMsg "Python venv not found!"
        Write-Info "Searched paths:"
        foreach ($path in $VENV_PATHS) {
            Write-Host "  - $path" -ForegroundColor Gray
        }
        Write-Info "Please run: cd backend; python -m venv venv; .\venv\Scripts\activate; pip install -r requirements.txt"
        return $false
    }
    Write-Success "Python venv found: $VENV_PYTHON"
    
    # Check uvicorn
    $uvicornCheck = & $VENV_PYTHON -c "import uvicorn" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "uvicorn not installed in venv"
        Write-Info "Please run: cd backend; .\venv\Scripts\activate; pip install uvicorn"
        return $false
    }
    Write-Success "uvicorn is installed"
    
    # Check Node.js
    $nodeVersion = node --version 2>$null
    if (-not $nodeVersion) {
        Write-ErrorMsg "Node.js not found, please install Node.js 18+"
        return $false
    }
    Write-Success "Node.js version: $nodeVersion"
    
    # Check frontend dependencies
    $nodeModules = Join-Path $FRONTEND_DIR "node_modules"
    if (-not (Test-Path $nodeModules)) {
        Write-Warning "Frontend dependencies not installed, installing..."
        Push-Location $FRONTEND_DIR
        npm install
        Pop-Location
    } else {
        Write-Success "Frontend dependencies installed"
    }
    
    return $true
}

function Wait-ForService {
    param(
        [string]$Url,
        [int]$MaxWaitSeconds = 15,
        [string]$ServiceName
    )
    
    $waited = 0
    $interval = 1
    
    while ($waited -lt $MaxWaitSeconds) {
        Start-Sleep -Seconds $interval
        $waited += $interval
        
        Write-Host "." -NoNewline
        
        try {
            $response = Invoke-WebRequest -Uri $Url -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 304) {
                Write-Host ""
                return $true
            }
        } catch {
            # Continue waiting
        }
    }
    
    Write-Host ""
    return $false
}

function Start-Backend {
    param([switch]$Detach)
    
    Write-Info "Starting backend service (port: $BACKEND_PORT)..."
    
    # Force kill any process on the port first
    Stop-ProcessOnPort -Port $BACKEND_PORT -ServiceName "Backend" -Graceful
    
    # Double check port is free
    $stillOccupied = Get-ListeningPidOnPort -Port $BACKEND_PORT
    if ($stillOccupied) {
        Write-ErrorMsg "Port $BACKEND_PORT is still occupied, cannot start backend"
        return $false
    }
    
    # Verify venv exists
    if (-not $VENV_PYTHON) {
        Write-ErrorMsg "Python venv not found!"
        return $false
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LOGS_DIR "backend_$timestamp.log"
    $uvicornCmd = "& '$VENV_PYTHON' -m uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT"
    
    Write-Info "Log file: $logFile"
    
    if ($Detach) {
        # 后台运行模式
        $process = Start-Process powershell -ArgumentList @(
            "-Command",
            "cd '$BACKEND_DIR'; `$env:PYTHONUNBUFFERED=1; $uvicornCmd 2>&1 | Tee-Object -FilePath '$logFile'"
        ) -PassThru -WindowStyle Hidden
        
        # 保存 PID
        $process.Id | Out-File (Join-Path $LOGS_DIR "backend.pid")
    } else {
        # 前台窗口模式
        Start-Process powershell -ArgumentList @(
            "-NoExit",
            "-Command",
            "cd '$BACKEND_DIR'; Write-Host '========== SmartAlbum Backend ==========' -ForegroundColor Cyan; Write-Host 'Venv: $VENV_PYTHON'; Write-Host 'Log: $logFile'; Write-Host ''; `$env:PYTHONUNBUFFERED=1; $uvicornCmd 2>&1 | Tee-Object -FilePath '$logFile'"
        )
    }
    
    Write-Info "Waiting for backend to start"
    $started = Wait-ForService -Url "http://localhost:$BACKEND_PORT/" -MaxWaitSeconds 15 -ServiceName "Backend"
    
    if ($started) {
        Write-Success "Backend started successfully!"
        Write-Info "API Docs: http://localhost:$BACKEND_PORT/docs"
        return $true
    } else {
        Write-Warning "Backend may still be starting, please check the backend window"
        return $true
    }
}

function Start-Frontend {
    param([switch]$Detach)
    
    Write-Info "Starting frontend service (port: $FRONTEND_PORT)..."
    
    # Force kill any process on the port first
    Stop-ProcessOnPort -Port $FRONTEND_PORT -ServiceName "Frontend" -Graceful
    
    # Double check port is free
    $stillOccupied = Get-ListeningPidOnPort -Port $FRONTEND_PORT
    if ($stillOccupied) {
        Write-ErrorMsg "Port $FRONTEND_PORT is still occupied, cannot start frontend"
        return $false
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LOGS_DIR "frontend_$timestamp.log"
    
    Write-Info "Log file: $logFile"
    
    if ($Detach) {
        # 后台运行模式
        $process = Start-Process powershell -ArgumentList @(
            "-Command",
            "cd '$FRONTEND_DIR'; npm run dev 2>&1 | Tee-Object -FilePath '$logFile'"
        ) -PassThru -WindowStyle Hidden
        
        # 保存 PID
        $process.Id | Out-File (Join-Path $LOGS_DIR "frontend.pid")
    } else {
        # 前台窗口模式
        Start-Process powershell -ArgumentList @(
            "-NoExit",
            "-Command",
            "cd '$FRONTEND_DIR'; Write-Host '========== SmartAlbum Frontend ==========' -ForegroundColor Cyan; Write-Host 'Log: $logFile'; Write-Host ''; npm run dev 2>&1 | Tee-Object -FilePath '$logFile'"
        )
    }
    
    Write-Info "Waiting for frontend to start"
    $started = Wait-ForService -Url "http://localhost:$FRONTEND_PORT/" -MaxWaitSeconds 20 -ServiceName "Frontend"
    
    if ($started) {
        Write-Success "Frontend started successfully!"
    } else {
        Write-Info "Frontend starting (Vite may take a few more seconds)..."
    }
    
    Write-Info "Frontend URL: http://localhost:$FRONTEND_PORT"
    return $true
}

function Restart-Services {
    Write-Info "Restarting all services..."
    Stop-AllServices
    Write-Host ""
    Start-Sleep -Seconds 2
    
    if (-not (Test-Environment)) {
        Write-ErrorMsg "Environment check failed"
        exit 1
    }
    
    Start-Backend
    Start-Sleep -Seconds 2
    Start-Frontend
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "     Services Restarted!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Backend API:  http://localhost:$BACKEND_PORT" -ForegroundColor White
    Write-Host "API Docs:     http://localhost:$BACKEND_PORT/docs" -ForegroundColor White
    Write-Host "Frontend:     http://localhost:$FRONTEND_PORT" -ForegroundColor White
    Write-Host ""
}

function Show-Logs {
    param([int]$Lines = 50)
    
    Write-Info "Recent logs (last $Lines lines):"
    Write-Host ""
    
    $backendLogs = Get-ChildItem -Path $LOGS_DIR -Filter "backend_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $frontendLogs = Get-ChildItem -Path $LOGS_DIR -Filter "frontend_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    
    if ($backendLogs) {
        Write-Host "--- Backend Log ($($backendLogs.Name)) ---" -ForegroundColor Cyan
        Get-Content $backendLogs.FullName -Tail $Lines
        Write-Host ""
    }
    
    if ($frontendLogs) {
        Write-Host "--- Frontend Log ($($frontendLogs.Name)) ---" -ForegroundColor Cyan
        Get-Content $frontendLogs.FullName -Tail $Lines
    }
}

function Main {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "     SmartAlbum Service Manager" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Show port status
    $portStatus = Show-AllPortStatus
    
    # Handle Action parameter from batch file
    if ($Action) {
        switch ($Action.ToLower()) {
            "status" { return }
            "stop" { 
                Stop-AllServices
                Write-Host ""
                Show-AllPortStatus | Out-Null
                return 
            }
            "restart" {
                Restart-Services
                return
            }
            "logs" {
                Show-Logs
                return
            }
            "backend" {
                if (-not (Test-Environment)) { exit 1 }
                Write-Host ""
                Start-Backend
            }
            "frontend" {
                if (-not (Test-Environment)) { exit 1 }
                Write-Host ""
                Start-Frontend
            }
            default {
                if (-not (Test-Environment)) { exit 1 }
                Write-Host ""
                Start-Backend
                Start-Sleep -Seconds 2
                Start-Frontend
            }
        }
    } elseif ($Status) {
        return
    } elseif ($Stop) {
        Stop-AllServices
        Write-Host ""
        Show-AllPortStatus | Out-Null
        return
    } elseif ($Restart) {
        Restart-Services
        return
    } else {
        if (-not (Test-Environment)) {
            Write-ErrorMsg "Environment check failed, please install dependencies first"
            exit 1
        }
        
        Write-Host ""
        
        if ($Backend) {
            Start-Backend
        } elseif ($Frontend) {
            Start-Frontend
        } else {
            Start-Backend
            Start-Sleep -Seconds 2
            Start-Frontend
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "     Services Started!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Backend API:  http://localhost:$BACKEND_PORT" -ForegroundColor White
    Write-Host "API Docs:     http://localhost:$BACKEND_PORT/docs" -ForegroundColor White
    Write-Host "Frontend:     http://localhost:$FRONTEND_PORT" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  .\start.ps1 -Status   # Check port status" -ForegroundColor Gray
    Write-Host "  .\start.ps1 -Stop     # Stop all services" -ForegroundColor Gray
    Write-Host "  .\start.ps1 -Restart  # Restart all services" -ForegroundColor Gray
    Write-Host "  .\start.ps1 -Action logs  # View recent logs" -ForegroundColor Gray
    Write-Host ""
}

Main
