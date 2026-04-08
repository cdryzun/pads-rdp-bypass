@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title PADS RDP Bypass - Installer

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
set "SCRIPT_DIR=%~dp0"
set "SOURCE_DLL=%SCRIPT_DIR%%DLL_NAME%"

:: 32 位 AppInit_DLLs 注册表路径
set "REG_KEY=HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"

echo ============================================================
echo   PADS RDP Bypass - Installer
echo ============================================================
echo.
echo   DLL 源文件:  %SOURCE_DLL%
echo   安装目录:    %INSTALL_DIR%
echo   注册表路径:  %REG_KEY%
echo.

:: ============================================================
::  检查源 DLL 是否存在
:: ============================================================
if not exist "%SOURCE_DLL%" (
    echo [错误] 未找到 %DLL_NAME%
    echo        请将本脚本与 %DLL_NAME% 放在同一目录
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  创建安装目录（幂等）
:: ============================================================
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    echo [安装] 创建目录: %INSTALL_DIR%
) else (
    echo [跳过] 目录已存在: %INSTALL_DIR%
)

:: ============================================================
::  复制 DLL（幂等：比较文件，不同则覆盖）
:: ============================================================
fc /b "%SOURCE_DLL%" "%DLL_PATH%" >nul 2>&1
if %errorlevel% neq 0 (
    copy /y "%SOURCE_DLL%" "%DLL_PATH%" >nul
    echo [安装] 复制 DLL: %DLL_PATH%
) else (
    echo [跳过] DLL 已是最新: %DLL_PATH%
)

:: ============================================================
::  设置注册表: AppInit_DLLs（幂等）
:: ============================================================
for /f "tokens=2*" %%a in ('reg query "%REG_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "CURRENT_APPINIT=%%b"

echo "%CURRENT_APPINIT%" | findstr /i /c:"%DLL_PATH%" >nul 2>&1
if %errorlevel% neq 0 (
    if "%CURRENT_APPINIT%"=="" (
        reg add "%REG_KEY%" /v AppInit_DLLs /t REG_SZ /d "%DLL_PATH%" /f >nul
    ) else (
        reg add "%REG_KEY%" /v AppInit_DLLs /t REG_SZ /d "%DLL_PATH% %CURRENT_APPINIT%" /f >nul
    )
    echo [安装] 注册表 AppInit_DLLs: %DLL_PATH%
) else (
    echo [跳过] AppInit_DLLs 已包含 DLL 路径
)

:: ============================================================
::  设置注册表: LoadAppInit_DLLs = 1（幂等）
:: ============================================================
for /f "tokens=3" %%a in ('reg query "%REG_KEY%" /v LoadAppInit_DLLs 2^>nul ^| findstr LoadAppInit_DLLs') do set "CURRENT_LOAD=%%a"

if not "%CURRENT_LOAD%"=="0x1" (
    reg add "%REG_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d 1 /f >nul
    echo [安装] 注册表 LoadAppInit_DLLs: 1
) else (
    echo [跳过] LoadAppInit_DLLs 已为 1
)

:: ============================================================
::  设置注册表: RequireSignedAppInit_DLLs = 0（幂等）
:: ============================================================
for /f "tokens=3" %%a in ('reg query "%REG_KEY%" /v RequireSignedAppInit_DLLs 2^>nul ^| findstr RequireSignedAppInit_DLLs') do set "CURRENT_SIGNED=%%a"

if not "%CURRENT_SIGNED%"=="0x0" (
    reg add "%REG_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d 0 /f >nul
    echo [安装] 注册表 RequireSignedAppInit_DLLs: 0
) else (
    echo [跳过] RequireSignedAppInit_DLLs 已为 0
)

:: ============================================================
::  验证
:: ============================================================
echo.
echo ============================================================
echo   验证安装结果
echo ============================================================
echo.

set "VERIFY_OK=1"

if exist "%DLL_PATH%" (
    echo   [OK] DLL 文件存在
) else (
    echo   [NG] DLL 文件不存在!
    set "VERIFY_OK=0"
)

for /f "tokens=2*" %%a in ('reg query "%REG_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do (
    echo "%%b" | findstr /i /c:"%DLL_PATH%" >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [OK] AppInit_DLLs 已配置
    ) else (
        echo   [NG] AppInit_DLLs 未正确配置!
        set "VERIFY_OK=0"
    )
)

for /f "tokens=3" %%a in ('reg query "%REG_KEY%" /v LoadAppInit_DLLs 2^>nul ^| findstr LoadAppInit_DLLs') do (
    if "%%a"=="0x1" (
        echo   [OK] LoadAppInit_DLLs = 1
    ) else (
        echo   [NG] LoadAppInit_DLLs != 1
        set "VERIFY_OK=0"
    )
)

for /f "tokens=3" %%a in ('reg query "%REG_KEY%" /v RequireSignedAppInit_DLLs 2^>nul ^| findstr RequireSignedAppInit_DLLs') do (
    if "%%a"=="0x0" (
        echo   [OK] RequireSignedAppInit_DLLs = 0
    ) else (
        echo   [NG] RequireSignedAppInit_DLLs != 0
        set "VERIFY_OK=0"
    )
)

echo.
if "%VERIFY_OK%"=="1" (
    echo   安装完成! 现在可以通过 RDP 正常启动 PADS 了。
    echo   无需使用 RunPADS.exe，直接双击 PADS 快捷方式即可。
) else (
    echo   安装存在异常，请检查上方 [NG] 项目。
)

echo.
pause
