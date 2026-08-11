@echo off
REM ============================================================
REM Red Rock Robotics — local server restart script (Windows)
REM ------------------------------------------------------------
REM Usage: double-click this file, or run from Command Prompt:
REM   restart-server.bat          (defaults to port 8000)
REM   restart-server.bat 5000     (use a different port)
REM ============================================================

set PORT=%1
if "%PORT%"=="" set PORT=8000

echo Stopping anything already running on port %PORT%...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr :%PORT% ^| findstr LISTENING') do (
    taskkill /F /PID %%p >nul 2>&1
    echo   killed process %%p
)

echo Starting server on http://localhost:%PORT% ...
cd /d "%~dp0"
python -m http.server %PORT%
