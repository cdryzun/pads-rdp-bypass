---
title: "在 RDP 远程桌面中运行 PADS：从 API Hook 到 AppInit_DLLs 的工程实践"
date: 2026-04-09T00:00:00+08:00
draft: false
tags: ["Windows", "API Hook", "Detours", "PADS", "RDP", "GitHub Actions", "CI/CD"]
categories: ["逆向工程"]
description: "记录通过 Microsoft Detours Hook GetSystemMetrics API，绕过 PADS FlexNet 远程桌面检测的完整工程实践。经历三次失败方案后，最终采用 AppInit_DLLs 注册表注入实现可靠的解决方案。"
---

Author: [cdryzun](https://github.com/cdryzun)
Updated: 2026-04-09

本文项目地址：[github.com/cdryzun/pads-rdp-bypass](https://github.com/cdryzun/pads-rdp-bypass)

---

- [0. 问题背景](#0-问题背景)
  - [0.1 PADS 与远程桌面的冲突](#01-pads-与远程桌面的冲突)
  - [0.2 FlexNet 的检测原理](#02-flexnet-的检测原理)
- [1. 技术选型：API Hook 与 Microsoft Detours](#1-技术选型api-hook-与-microsoft-detours)
  - [1.1 什么是 API Hook](#11-什么是-api-hook)
  - [1.2 Hook DLL 的实现](#12-hook-dll-的实现)
- [2. 注入方案的演进：三次失败与一次成功](#2-注入方案的演进三次失败与一次成功)
  - [2.1 第一次：Detours 进程创建注入](#21-第一次detours-进程创建注入)
  - [2.2 第二次：绕过跳板直接注入主程序](#22-第二次绕过跳板直接注入主程序)
  - [2.3 第三次：CreateRemoteThread 运行时注入](#23-第三次createremotethread-运行时注入)
  - [2.4 最终方案：AppInit_DLLs 注册表注入](#24-最终方案appinit_dlls-注册表注入)
- [3. PADS 进程架构逆向分析](#3-pads-进程架构逆向分析)
  - [3.1 双 EXE 架构](#31-双-exe-架构)
  - [3.2 EEWrapper 跳板的二进制分析](#32-eewrapper-跳板的二进制分析)
- [4. 在 macOS 上交叉编译：GitHub Actions CI/CD](#4-在-macos-上交叉编译github-actions-cicd)
  - [4.1 为什么不能本地编译](#41-为什么不能本地编译)
  - [4.2 GitHub Actions 工作流](#42-github-actions-工作流)
  - [4.3 静态链接的关键决策](#43-静态链接的关键决策)
- [5. 部署：一键安装脚本](#5-部署一键安装脚本)
  - [5.1 安装](#51-安装)
  - [5.2 卸载](#52-卸载)
- [6. 踩坑记录与排错经验](#6-踩坑记录与排错经验)
- [7. 参考资料](#7-参考资料)

---

## 0. 问题背景

### 0.1 PADS 与远程桌面的冲突

PADS（现 Siemens EDA，原 Mentor Graphics）是硬件工程师日常使用的 PCB 设计工具。关于 PADS VX2.4 的安装配置，可参考 [这篇安装文档](https://www.mcuzx.com/t-53-1.html)。

本地物理机上，PADS 运行一切正常。但当我尝试通过 RDP 远程桌面连到工作站上启动 PADS 时，FlexNet 授权系统直接报错拒绝启动。这在实际工作中很不方便——每次都要断开远程、走到物理机前操作，效率极低。

我需要找到一种方式，让 PADS 在 RDP 会话中也能正常获取 License。

### 0.2 FlexNet 的检测原理

FlexNet 在授权验证阶段会调用一个 Windows API 来判断当前是否处于远程桌面环境：

```c
int result = GetSystemMetrics(SM_REMOTESESSION);
// result == 0  → 本地物理会话
// result != 0  → 远程桌面会话 (RDP/RDS)
```

`SM_REMOTESESSION` 的值是 `0x1000`，这是 Windows 提供的标准检测手段。返回非零时，FlexNet 判定当前是远程环境，拒绝发放授权。

思路很直接：**让这个 API 对 PADS 进程始终返回 0 就行了。**

---

## 1. 技术选型：API Hook 与 Microsoft Detours

### 1.1 什么是 API Hook

API Hook 是一种在不修改目标程序二进制的前提下，拦截系统 API 调用的技术。被 Hook 的函数会先经过我们写的"替身函数"，在那里可以修改参数、篡改返回值，或者直接放行到原始系统函数。

{{< mermaid >}}
flowchart LR
    A[powerpcb.exe] -->|"GetSystemMetrics(nIndex)"| B{FakeGetSystemMetrics}
    B -->|"nIndex == SM_REMOTESESSION"| C["return 0\n(伪装本地)"]
    B -->|"其他参数"| D["TrueGetSystemMetrics(nIndex)\n正常返回"]
{{< /mermaid >}}

[Microsoft Detours](https://github.com/microsoft/Detours) 是微软官方维护的 Hook 库。选它而不是 MinHook、EasyHook 的理由：

- 微软自家维护，跟 Windows 内核的兼容性不用担心
- 有事务机制（`DetourTransactionBegin/Commit`），Hook 操作是原子的
- `DetourUpdateThread` 保证多线程场景下的安全
- 同时支持 x86、x64、ARM

### 1.2 Hook DLL 的实现

核心代码只有 30 行。逻辑很简单——拦截 `SM_REMOTESESSION`，其他参数全部透传：

```cpp
#include <windows.h>
#include <detours.h>

static int(WINAPI *TrueGetSystemMetrics)(int) = GetSystemMetrics;

int WINAPI FakeGetSystemMetrics(int nIndex) {
    if (nIndex == SM_REMOTESESSION) {
        return 0;
    }
    return TrueGetSystemMetrics(nIndex);
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD dwReason, LPVOID reserved) {
    if (DetourIsHelperProcess()) return TRUE;

    if (dwReason == DLL_PROCESS_ATTACH) {
        DetourRestoreAfterWith();
        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        DetourAttach(&(PVOID &)TrueGetSystemMetrics, FakeGetSystemMetrics);
        DetourTransactionCommit();
    } else if (dwReason == DLL_PROCESS_DETACH) {
        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        DetourDetach(&(PVOID &)TrueGetSystemMetrics, FakeGetSystemMetrics);
        DetourTransactionCommit();
    }
    return TRUE;
}
```

几个要点：

1. **最小影响**：只动 `SM_REMOTESESSION` 一个参数，不碰别的
2. **事务原子性**：`Begin → UpdateThread → Attach → Commit` 四步，中途出错会回滚
3. **自清理**：`DLL_PROCESS_DETACH` 时自动卸载，进程退出后不留痕迹

---

## 2. 注入方案的演进：三次失败与一次成功

DLL 写好了，怎么塞进 PADS 进程里？这才是真正折腾的地方。

### 2.1 第一次：Detours 进程创建注入

最直觉的做法——用 Detours 提供的 `DetourCreateProcessWithDllExA` 在进程创建时注入：

```cpp
DetourCreateProcessWithDllExA(
    "powerpcb.exe",
    ...,
    CREATE_SUSPENDED,  // 先暂停
    ...,
    "RdpBypass.dll",   // 注入 DLL
    NULL
);
ResumeThread(pi.hThread);  // 注入完再恢复
```

**结果**：弹窗 `0xc000007b`（STATUS_INVALID_IMAGE_FORMAT），进程直接挂掉。

**根因**：后面逆向分析才搞明白（详见 [第 3 节](#3-pads-进程架构逆向分析)），PADS 快捷方式指向的 `powerpcb.exe` 是一个 24KB 的跳板程序，用 VS2013 编译。我们的 DLL 用 VS2022 编译，两者的 CRT 运行时在同一进程里冲突了。

### 2.2 第二次：绕过跳板直接注入主程序

既然跳板有兼容性问题，那直接找到真正的 PADS 主程序（38MB，在 `SDD_HOME\Programs\` 下）注入。

为了弥补绕过跳板带来的问题，在启动器里手动补全了环境变量和 PATH：

```cpp
SetEnvironmentVariableA("SDD_HOME", sddHome);
SetEnvironmentVariableA("MGC_HOME", sddHome);

char extraPaths[4096];
_snprintf_s(extraPaths, sizeof(extraPaths), _TRUNCATE,
    "%s\\common\\win32\\lib;%s\\common\\win32\\bin;%s\\Programs",
    sddHome, sddHome, sddHome);
// ... 追加到 PATH
```

**结果**：进程能启动，几秒后默默退出。提示找不到 `xf_Os.dll`，补上路径后换成别的 DLL 找不到。

**根因**：跳板程序做的初始化远不止设置几个环境变量。它通过 `SDDEnv.dll` 执行了一整套运行环境配置，没有文档记录，无法完全复现。

### 2.3 第三次：CreateRemoteThread 运行时注入

换思路。既然跳板不能注入、主程序不能直接启动，那就让跳板正常运行，等真正的 PADS 主进程起来后，再注入进去：

```cpp
// 1. 正常启动跳板
CreateProcessA("powerpcb.exe", ...);

// 2. 轮询等待真正的主程序出现 (内存 > 10MB)
DWORD realPid = WaitForRealProcess(stubPid, 30000);

// 3. 注入
LPVOID remoteMem = VirtualAllocEx(proc, NULL, pathLen, ...);
WriteProcessMemory(proc, remoteMem, dllPath, pathLen, NULL);
CreateRemoteThread(proc, NULL, 0,
    (LPTHREAD_START_ROUTINE)GetProcAddress(k32, "LoadLibraryA"),
    remoteMem, 0, NULL);
```

**结果**：DLL 注入成功了，但 PADS 依然报 License 错误。

**根因**：**注入时机太晚**。FlexNet 的 License 检查发生在进程初始化极早期。等到主进程的内存涨到 10MB 可以被我们识别出来时，`GetSystemMetrics(SM_REMOTESESSION)` 早就被调用过了。

另外在 RDS 多用户环境下还有个问题：多个用户同时开 PADS，无法准确判断哪个进程属于当前用户。

### 2.4 最终方案：AppInit_DLLs 注册表注入

三次失败的核心矛盾是 **注入时机**。需要一种在进程初始化之前就完成 Hook 的机制。

Windows 的 `AppInit_DLLs` 正好解决这个问题：配置注册表后，**所有加载了 `user32.dll` 的进程**在初始化阶段会自动加载指定的 DLL，比任何业务代码都早。

注册表路径（32 位进程用 WOW6432Node）：

```
HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows
```

需要设置三个值：

| 值名 | 类型 | 数据 | 作用 |
|------|------|------|------|
| `AppInit_DLLs` | REG_SZ | `C:\RdpBypass\RdpBypass.dll` | DLL 绝对路径 |
| `LoadAppInit_DLLs` | DWORD | `1` | 启用加载 |
| `RequireSignedAppInit_DLLs` | DWORD | `0` | 允许未签名 DLL |

**四种方案的对比**：

| 维度 | Detours 注入 | 注入主程序 | CreateRemoteThread | AppInit_DLLs |
|------|-------------|-----------|-------------------|-------------|
| 注入时机 | 进程创建时 | 进程创建时 | 进程运行后 | **进程初始化前** |
| 跳板兼容 | CRT 冲突 | 环境缺失 | 不涉及 | **无冲突** |
| 多用户 RDS | 不支持 | 不支持 | 有歧义 | **全部生效** |
| 成功率 | 低 | 低 | 中 | **高** |
| 用户感知 | 需启动器 | 需启动器 | 需启动器 | **零操作** |

验证注册表配置是否生效：

```cmd
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows" /v AppInit_DLLs
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows" /v LoadAppInit_DLLs
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows" /v RequireSignedAppInit_DLLs
```

预期输出：

```
AppInit_DLLs              REG_SZ    C:\RdpBypass\RdpBypass.dll
LoadAppInit_DLLs          REG_DWORD 0x1
RequireSignedAppInit_DLLs REG_DWORD 0x0
```

---

## 3. PADS 进程架构逆向分析

在调试过程中发现了 PADS 一个有意思的内部架构，官方文档里完全没有提到。

### 3.1 双 EXE 架构

PADS 安装目录里有两个 `powerpcb.exe`：

| 路径 | 大小 | 身份 |
|------|------|------|
| `SDD_HOME\common\win32\bin\powerpcb.exe` | 24 KB | EEWrapper 跳板程序 |
| `SDD_HOME\Programs\powerpcb.exe` | 38 MB | 真正的 PADS 主程序 |

用户双击的快捷方式指向 24KB 的跳板。跳板负责初始化运行环境后启动真正的主程序：

{{< mermaid >}}
flowchart TD
    A["用户双击 PADS 快捷方式"] --> B

    subgraph stub ["EEWrapper 跳板 (24KB)"]
        B["common\win32\bin\powerpcb.exe"] --> B1["读取 SDD_HOME / MGC_HOME"]
        B1 --> B2["通过 SDDEnv.dll 初始化环境"]
        B2 --> B3["配置 DLL 搜索路径"]
    end

    B3 --> C

    subgraph main ["PADS 主程序 (38MB)"]
        C["Programs\powerpcb.exe"] --> C1["加载 xf_Os.dll, mfc120.dll ..."]
        C1 --> C2["FlexNet License 检查"]
        C2 --> C3["启动 GUI"]
    end

    C2 -.->|"GetSystemMetrics\n(SM_REMOTESESSION)"| D{{"Hook 拦截点"}}

    C3 --> E["PADS 正常运行"]
{{< /mermaid >}}

### 3.2 EEWrapper 跳板的二进制分析

通过 PowerShell 提取 24KB 跳板中的可读 ASCII 字符串：

```powershell
$bytes = [IO.File]::ReadAllBytes("powerpcb.exe")
$text = [Text.Encoding]::ASCII.GetString($bytes)
$matches = [regex]::Matches($text, '[\x20-\x7E]{4,}')
foreach ($m in $matches) { Write-Output $m.Value }
```

关键发现：

```
SDD_HOME NOT DEFINED.
MGC_HOME NOT DEFINED.
SDD_PLATFORM NOT DEFINED.
SDDEnv.dll           ← 环境初始化库
EEWrapper.pdb        ← 跳板的调试符号名
MSVCP120.dll         ← VS2013 C++ 运行时
MSVCR120.dll         ← VS2013 C 运行时
mfc120.dll           ← VS2013 MFC 库
```

这些发现直接解释了两个问题：

- **为什么 Detours 注入跳板会 `0xc000007b`**：跳板用 VS2013 编译（链接 `msvcr120.dll`），我们的 DLL 用 VS2022 编译（静态链接），两套 CRT 在同一进程空间冲突
- **为什么绕过跳板直接启动主程序会失败**：主程序依赖跳板通过 `SDDEnv.dll` 完成的环境初始化，不是简单补几个环境变量就能替代的

---

## 4. 在 macOS 上交叉编译：GitHub Actions CI/CD

### 4.1 为什么不能本地编译

开发环境是 macOS，目标产物是 Windows x86 的 DLL 和 EXE。Detours 只支持 MSVC 编译器，MinGW 的兼容性不可靠（大量 MSVC 特有的 pragma 和内联汇编）。

可选方案：

| 方案 | 可行性 | 便利性 |
|------|--------|--------|
| MinGW 交叉编译 | 低（Detours 不兼容） | 高 |
| Windows 虚拟机 + VS | 高 | 低 |
| **GitHub Actions** | **高** | **高** |

### 4.2 GitHub Actions 工作流

利用 GitHub Actions 的 `windows-latest` Runner，推代码就自动编译。以下为核心步骤示意（完整配置见仓库 `.github/workflows/build.yml`）：

```yaml
name: Build Windows Binaries
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup MSVC (x86)
        uses: ilammy/msvc-dev-cmd@v1
        with:
          arch: x86     # 目标 32 位

      - name: Build Detours
        run: |
          git clone https://github.com/microsoft/Detours.git
          cd Detours\src
          nmake DETOURS_TARGET_PROCESSOR=X86
        shell: cmd

      - name: Build RdpBypass.dll
        run: |
          cl /nologo /W4 /O2 /MT /LD ^
            /I Detours\include ^
            src\RdpBypass.cpp ^
            /Fe:RdpBypass.dll ^
            /link /LIBPATH:Detours\lib.X86 detours.lib user32.lib kernel32.lib
        shell: cmd

      - name: Verify dependencies
        run: dumpbin /dependents RdpBypass.dll
        shell: cmd

      - uses: actions/upload-artifact@v4
        with:
          name: pads-rdp-bypass-x86
          path: RdpBypass.dll
```

### 4.3 静态链接的关键决策

编译参数里 `/MT` 是一个重要决策：

| 参数 | 作用 |
|------|------|
| `/MT` | 静态链接 C 运行时，DLL 不依赖 `vcruntime140.dll` |
| `/O2` | 优化代码体积和执行速度 |
| `/LD` | 生成 DLL（而非 EXE） |
| `/W4` | 最高警告级别 |

如果用默认的 `/MD`（动态链接），产出的 DLL 会依赖 `vcruntime140.dll`。目标机器不一定装了对应版本的 VC++ Redistributable。早期调试阶段就因为这个问题踩过坑——DLL 注入后目标进程直接 `0xc000007b`。

通过 `dumpbin /dependents` 验证最终产物的依赖：

```
RdpBypass.dll dependencies:
    USER32.dll      ← 系统自带
    KERNEL32.dll    ← 系统自带
```

干干净净，没有任何第三方依赖。

---

## 5. 部署：一键安装脚本

### 5.1 安装

脚本设计为**幂等**——多次执行结果相同，不会重复配置：

```bat
@echo off
setlocal enabledelayedexpansion

:: 管理员权限检查
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 需要管理员权限运行
    exit /b 1
)

set "INSTALL_DIR=C:\RdpBypass"
set "DLL_PATH=%INSTALL_DIR%\RdpBypass.dll"
set "REG_KEY=HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"

:: 创建目录（幂等：已存在则跳过）
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    echo [安装] 创建目录: %INSTALL_DIR%
) else (
    echo [跳过] 目录已存在
)

:: 复制 DLL（幂等：二进制比较，不同才覆盖）
fc /b "%~dp0RdpBypass.dll" "%DLL_PATH%" >nul 2>&1
if %errorlevel% neq 0 (
    copy /y "%~dp0RdpBypass.dll" "%DLL_PATH%" >nul
    echo [安装] 复制 DLL
) else (
    echo [跳过] DLL 已是最新
)

:: 注册表配置（幂等：检查当前值后决定是否修改）
reg add "%REG_KEY%" /v AppInit_DLLs /t REG_SZ /d "%DLL_PATH%" /f >nul
reg add "%REG_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d 1 /f >nul
reg add "%REG_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d 0 /f >nul

echo [完成] 安装成功，可直接通过 RDP 启动 PADS
```

操作步骤：

1. 从 [GitHub Actions](https://github.com/cdryzun/pads-rdp-bypass/actions) 下载最新构建产物
2. 解压到目标 Windows 机器的任意目录
3. 右键 `Install.bat` → **以管理员身份运行**
4. 验证输出全部为 `[OK]`

安装后无需任何额外操作。通过 RDP 连接，直接双击 PADS 快捷方式启动即可。

### 5.2 卸载

`Uninstall.bat`（同样需要管理员权限）会自动恢复所有修改：

- 从 `AppInit_DLLs` 移除 DLL 路径
- 将 `LoadAppInit_DLLs` 恢复为 `0`
- 将 `RequireSignedAppInit_DLLs` 恢复为 `1`
- 删除 `C:\RdpBypass\` 目录

---

## 6. 踩坑记录与排错经验

**`0xc000007b` STATUS_INVALID_IMAGE_FORMAT**

在本项目中遇到这个错误有两种成因：

| 场景 | 原因 | 解决方案 |
|------|------|---------|
| 注入 24KB 跳板 | VS2013 目标 + VS2022 DLL → CRT 冲突 | 改用 AppInit_DLLs，不直接注入跳板 |
| `/MD` 编译的 DLL | 目标机器缺 VC++ Redistributable | 改用 `/MT` 静态链接 |

**进程启动后立即退出**

如果 PADS 主进程 `powerpcb.exe` 启动后几秒就退出：
- 检查 `SDD_HOME`、`MGC_HOME` 环境变量是否定义
- 检查 PATH 中是否包含 `common\win32\lib`（`xf_Os.dll` 所在目录）
- 这通常意味着绕过了 EEWrapper 跳板，缺少环境初始化

**RDS 多用户环境**

`AppInit_DLLs` 方案的一个天然优势是对所有用户会话生效，不存在进程识别歧义。`CreateRemoteThread` 方案在多用户环境下需要额外处理会话隔离，实现复杂度高且不可靠。

**杀毒软件拦截**

DLL 注入类行为容易被安全软件标记。将 `C:\RdpBypass\RdpBypass.dll` 添加到杀毒白名单即可。

---

## 7. 参考资料

- [Microsoft Detours - GitHub](https://github.com/microsoft/Detours) - 微软官方 API Hook 库
- [GetSystemMetrics - Win32 API](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics) - SM_REMOTESESSION 文档
- [AppInit_DLLs - Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/dlls/secure-boot-and-appinit-dlls) - AppInit_DLLs 注册表机制说明
- [PADS VX2.4 安装教程](https://www.mcuzx.com/t-53-1.html) - PADS 安装配置参考
- [ilammy/msvc-dev-cmd](https://github.com/ilammy/msvc-dev-cmd) - GitHub Actions 中配置 MSVC 编译环境
- [pads-rdp-bypass 项目地址](https://github.com/cdryzun/pads-rdp-bypass) - 本文完整源码和 CI/CD 配置
