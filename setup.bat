@echo off
setlocal

:: Auto-elevate: if not admin, relaunch as admin (WSL mode requires it)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  Se requieren permisos de Administrador para habilitar WSL.
    echo  Aparecera un cuadro de dialogo pidiendo permiso.
    echo.
    powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/c','cd /d \"%~dp0\" && \"%~nx0\"'"
    exit /b
)

echo.
echo  Iniciando instalador de Claude Code...
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0setup.ps1"
pause
