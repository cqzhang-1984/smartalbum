@echo off
REM SmartAlbum Service Manager - Simple wrapper for PowerShell script
REM Usage: start.bat [backend|frontend|stop|status|restart|logs]

set "ACTION=%~1"
if "%ACTION%"=="" set "ACTION=all"

powershell -ExecutionPolicy Bypass -Command "& '%~dp0start.ps1' -Action '%ACTION%'"
