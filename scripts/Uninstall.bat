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
set "BACKUP_FILE=%INSTALL_DIR%\backup.reg.txt"
set "REG_KEY=HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"

echo ============================================================
echo   PADS RDP Bypass - Uninstaller
echo ============================================================
echo.

:: ============================================================
::  读取备份值（如果存在）
:: ============================================================
set "BAK_APPINIT="
set "BAK_LOAD="
set "BAK_SIGNED="
set "HAS_BACKUP=0"

if exist "%BACKUP_FILE%" (
    set "HAS_BACKUP=1"
    for /f "tokens=1,* delims==" %%a in ('type "%BACKUP_FILE%" ^| findstr /v "^#"') do (
        if "%%a"=="AppInit_DLLs" set "BAK_APPINIT=%%b"
        if "%%a"=="LoadAppInit_DLLs" set "BAK_LOAD=%%b"
        if "%%a"=="RequireSignedAppInit_DLLs" set "BAK_SIGNED=%%b"
    )
    echo [信息] 已读取安装前备份
)

:: ============================================================
::  清理注册表: 从 AppInit_DLLs 中移除我们的 DLL（幂等）
:: ============================================================
for /f "tokens=2*" %%a in ('reg query "%REG_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "CURRENT_APPINIT=%%b"

echo "!CURRENT_APPINIT!" | findstr /i /c:"%DLL_PATH%" >nul 2>&1
if %errorlevel% equ 0 (
    if "!HAS_BACKUP!"=="1" (
        :: 有备份：恢复原始值
        reg add "%REG_KEY%" /v AppInit_DLLs /t REG_SZ /d "!BAK_APPINIT!" /f >nul
    ) else (
        :: 无备份：精确移除本项目路径，保留其他条目
        set "NEW_APPINIT=!CURRENT_APPINIT!"
        :: 移除路径（可能带前后空格的多种情况）
        set "NEW_APPINIT=!NEW_APPINIT:%DLL_PATH% =!"
        set "NEW_APPINIT=!NEW_APPINIT: %DLL_PATH%=!"
        set "NEW_APPINIT=!NEW_APPINIT:%DLL_PATH%=!"
        :: 去除首尾空格
        for /f "tokens=*" %%x in ("!NEW_APPINIT!") do set "NEW_APPINIT=%%x"
        reg add "%REG_KEY%" /v AppInit_DLLs /t REG_SZ /d "!NEW_APPINIT!" /f >nul
    )
    if !errorlevel! neq 0 (
        echo [错误] 恢复 AppInit_DLLs 失败
    ) else (
        echo [卸载] 已从 AppInit_DLLs 移除 DLL 路径
    )
) else (
    echo [跳过] AppInit_DLLs 中未包含 DLL 路径
)

:: ============================================================
::  恢复注册表: LoadAppInit_DLLs（幂等）
:: ============================================================
if "!HAS_BACKUP!"=="1" (
    if defined BAK_LOAD (
        :: 将 0xN 格式转为十进制
        set /a "RESTORE_LOAD=!BAK_LOAD!"
        reg add "%REG_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d !RESTORE_LOAD! /f >nul
        echo [卸载] LoadAppInit_DLLs 恢复为备份值: !BAK_LOAD!
    )
) else (
    :: 无备份：仅当 AppInit_DLLs 为空时才关闭加载
    for /f "tokens=2*" %%a in ('reg query "%REG_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "REMAINING=%%b"
    if "!REMAINING!"=="" (
        reg add "%REG_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d 0 /f >nul
        echo [卸载] AppInit_DLLs 已空，LoadAppInit_DLLs 设为 0
    ) else (
        echo [跳过] AppInit_DLLs 仍有其他条目，保留 LoadAppInit_DLLs 当前值
    )
)

:: ============================================================
::  恢复注册表: RequireSignedAppInit_DLLs（幂等）
:: ============================================================
if "!HAS_BACKUP!"=="1" (
    if defined BAK_SIGNED (
        set /a "RESTORE_SIGNED=!BAK_SIGNED!"
        reg add "%REG_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d !RESTORE_SIGNED! /f >nul
        echo [卸载] RequireSignedAppInit_DLLs 恢复为备份值: !BAK_SIGNED!
    )
) else (
    for /f "tokens=2*" %%a in ('reg query "%REG_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "REMAINING2=%%b"
    if "!REMAINING2!"=="" (
        reg add "%REG_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d 1 /f >nul
        echo [卸载] AppInit_DLLs 已空，RequireSignedAppInit_DLLs 恢复为 1
    ) else (
        echo [跳过] AppInit_DLLs 仍有其他条目，保留 RequireSignedAppInit_DLLs 当前值
    )
)

:: ============================================================
::  删除 DLL 文件和目录（幂等）
:: ============================================================
if exist "%DLL_PATH%" (
    del /f /q "%DLL_PATH%" 2>nul
    if exist "%DLL_PATH%" (
        echo [警告] DLL 正被占用，请重启后手动删除 %INSTALL_DIR%
    ) else (
        echo [卸载] 已删除 DLL: %DLL_PATH%
    )
) else (
    echo [跳过] DLL 文件不存在
)

:: 删除备份文件
if exist "%BACKUP_FILE%" (
    del /f /q "%BACKUP_FILE%" 2>nul
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
echo   卸载完成!
echo.
pause
