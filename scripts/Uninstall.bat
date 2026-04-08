@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title PADS RDP Bypass - Uninstaller

:: ============================================================
::  检查管理员权限
:: ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 需要管理员权限运行此脚本
    echo        请右键 -^> 以管理员身份运行
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  配置
:: ============================================================
set "INSTALL_DIR=C:\RdpBypass"
set "DLL_NAME=RdpBypass.dll"
set "DLL_PATH=%INSTALL_DIR%\%DLL_NAME%"
set "REG_KEY=HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"

echo ============================================================
echo   PADS RDP Bypass - Uninstaller
echo ============================================================
echo.

:: ============================================================
::  清理注册表: 从 AppInit_DLLs 中移除我们的 DLL（幂等）
:: ============================================================
for /f "tokens=2*" %%a in ('reg query "%REG_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "CURRENT_APPINIT=%%b"

echo "%CURRENT_APPINIT%" | findstr /i /c:"%DLL_PATH%" >nul 2>&1
if %errorlevel% equ 0 (
    :: 移除我们的 DLL 路径，保留其他值
    set "NEW_APPINIT=!CURRENT_APPINIT:%DLL_PATH%=!"
    :: 清理多余空格
    if "!NEW_APPINIT!"==" " set "NEW_APPINIT="
    reg add "%REG_KEY%" /v AppInit_DLLs /t REG_SZ /d "!NEW_APPINIT!" /f >nul
    echo [卸载] 已从 AppInit_DLLs 移除 DLL 路径
) else (
    echo [跳过] AppInit_DLLs 中未包含 DLL 路径
)

:: ============================================================
::  恢复注册表: LoadAppInit_DLLs = 0（幂等）
:: ============================================================
for /f "tokens=3" %%a in ('reg query "%REG_KEY%" /v LoadAppInit_DLLs 2^>nul ^| findstr LoadAppInit_DLLs') do set "CURRENT_LOAD=%%a"

if "%CURRENT_LOAD%"=="0x1" (
    reg add "%REG_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d 0 /f >nul
    echo [卸载] 注册表 LoadAppInit_DLLs: 0
) else (
    echo [跳过] LoadAppInit_DLLs 已为 0
)

:: ============================================================
::  恢复注册表: RequireSignedAppInit_DLLs = 1（幂等）
:: ============================================================
for /f "tokens=3" %%a in ('reg query "%REG_KEY%" /v RequireSignedAppInit_DLLs 2^>nul ^| findstr RequireSignedAppInit_DLLs') do set "CURRENT_SIGNED=%%a"

if "%CURRENT_SIGNED%"=="0x0" (
    reg add "%REG_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d 1 /f >nul
    echo [卸载] 注册表 RequireSignedAppInit_DLLs: 1
) else (
    echo [跳过] RequireSignedAppInit_DLLs 已为 1
)

:: ============================================================
::  删除 DLL 文件和目录（幂等）
:: ============================================================
if exist "%DLL_PATH%" (
    del /f /q "%DLL_PATH%" 2>nul
    if exist "%DLL_PATH%" (
        echo [警告] DLL 正被占用，将在重启后自动删除
        echo        请重启后手动删除 %INSTALL_DIR%
    ) else (
        echo [卸载] 已删除 DLL: %DLL_PATH%
    )
) else (
    echo [跳过] DLL 文件不存在
)

if exist "%INSTALL_DIR%" (
    rd /q "%INSTALL_DIR%" 2>nul
    if not exist "%INSTALL_DIR%" (
        echo [卸载] 已删除目录: %INSTALL_DIR%
    ) else (
        echo [警告] 目录非空或被占用: %INSTALL_DIR%
    )
) else (
    echo [跳过] 安装目录不存在
)

echo.
echo   卸载完成! 已恢复系统默认设置。
echo.
pause
