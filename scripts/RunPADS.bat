@echo off
chcp 65001 >nul 2>&1
title PADS RDP Bypass Launcher

:: ============================================================
::  PADS 路径配置 - 请根据实际安装路径修改下面这一行
:: ============================================================
set "PADS_EXE=D:\MentorGraphics\PADSVX.2.4\SDD_HOME\common\win32\bin\powerpcb.exe"

:: ============================================================
::  以下内容无需修改
:: ============================================================

:: 获取当前脚本所在目录
set "SCRIPT_DIR=%~dp0"

:: RunPADS.exe 和 RdpBypass.dll 应与本脚本放在同一目录
set "LAUNCHER=%SCRIPT_DIR%RunPADS.exe"

:: 检查文件是否存在
if not exist "%LAUNCHER%" (
    echo [错误] 未找到 RunPADS.exe
    echo        请将本脚本与 RunPADS.exe、RdpBypass.dll 放在同一目录
    echo.
    pause
    exit /b 1
)

if not exist "%SCRIPT_DIR%RdpBypass.dll" (
    echo [错误] 未找到 RdpBypass.dll
    echo        请将本脚本与 RunPADS.exe、RdpBypass.dll 放在同一目录
    echo.
    pause
    exit /b 1
)

if not exist "%PADS_EXE%" (
    echo [错误] 未找到 PADS 程序: %PADS_EXE%
    echo        请编辑本脚本，修改 PADS_EXE 变量为正确的路径
    echo.
    pause
    exit /b 1
)

echo ============================================================
echo   PADS RDP Bypass Launcher
echo ============================================================
echo.
echo   PADS 路径: %PADS_EXE%
echo   启动器:    %LAUNCHER%
echo.

"%LAUNCHER%" "%PADS_EXE%"

if %errorlevel% neq 0 (
    echo.
    echo [错误] 启动失败，错误码: %errorlevel%
    echo.
    pause
    exit /b %errorlevel%
)

echo.
echo [完成] PADS 已成功启动
timeout /t 3 >nul
