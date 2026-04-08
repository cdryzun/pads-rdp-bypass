# PADS RDP Bypass

通过 Hook `GetSystemMetrics(SM_REMOTESESSION)`，让 PADS 在远程桌面 (RDP/RDS) 环境下正常运行，绕过 FlexNet 的远程会话检测。

## 原理

PADS 启动时，FlexNet 许可系统会调用 `GetSystemMetrics(SM_REMOTESESSION)` 检测是否运行在 RDP 会话中。如果检测到远程桌面，会拒绝启动并报 License 错误。

本工具通过 Windows `AppInit_DLLs` 机制，在进程初始化阶段（早于任何业务代码）自动加载 Hook DLL，拦截该 API 调用并强制返回 `0`（非远程桌面），其他所有调用正常透传。

## 下载

前往本仓库的 [Actions](../../actions) 页面，点击最新一次成功的构建，下载 **pads-rdp-bypass-x86** 产物压缩包。

压缩包内含：

| 文件 | 说明 |
|------|------|
| `RdpBypass.dll` | Hook DLL，拦截远程桌面检测 |
| `Install.bat` | 一键安装脚本（需管理员权限） |
| `Uninstall.bat` | 一键卸载脚本（需管理员权限） |

## 安装方法（推荐）

### 1. 下载并解压

将产物压缩包解压到任意目录。

### 2. 运行安装脚本

右键 `Install.bat` → **以管理员身份运行**。

脚本会自动完成以下操作：

1. 创建 `C:\RdpBypass\` 目录
2. 复制 `RdpBypass.dll` 到该目录
3. 设置注册表 `AppInit_DLLs` 指向 DLL
4. 启用 `LoadAppInit_DLLs`
5. 关闭 `RequireSignedAppInit_DLLs`
6. 验证所有配置是否正确

### 3. 使用

安装完成后，**无需任何额外操作**。直接通过 RDP 远程连接，像往常一样双击 PADS 快捷方式启动即可。

### 安装输出示例

```
============================================================
  PADS RDP Bypass - Installer
============================================================

  DLL 源文件:  C:\Users\你的用户名\Desktop\RdpBypass.dll
  安装目录:    C:\RdpBypass
  注册表路径:  HKLM\SOFTWARE\WOW6432Node\...

[安装] 创建目录: C:\RdpBypass
[安装] 复制 DLL: C:\RdpBypass\RdpBypass.dll
[安装] 注册表 AppInit_DLLs: C:\RdpBypass\RdpBypass.dll
[安装] 注册表 LoadAppInit_DLLs: 1
[安装] 注册表 RequireSignedAppInit_DLLs: 0

============================================================
  验证安装结果
============================================================

  [OK] DLL 文件存在
  [OK] AppInit_DLLs 已配置
  [OK] LoadAppInit_DLLs = 1
  [OK] RequireSignedAppInit_DLLs = 0

  安装完成! 现在可以通过 RDP 正常启动 PADS 了。
```

## 卸载

右键 `Uninstall.bat` → **以管理员身份运行**，会自动恢复所有修改。

## 特性

- **幂等安装**：多次运行 Install.bat 不会重复配置
- **多用户支持**：RDS 环境下所有用户会话均生效
- **100% 注入成功率**：DLL 在进程初始化阶段加载，早于 License 检查
- **零侵入**：不修改 PADS 任何文件，卸载后完全恢复
- **最小副作用**：DLL 仅拦截 `SM_REMOTESESSION` 查询，其他调用透传

## 常见问题

### 启动成功但 PADS 仍报 License 错误

**可能原因**：FlexNet 除了 `GetSystemMetrics` 外还通过其他方式检测 RDP。

**排查方向**：
- 检查注册表 `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server`
- 检查是否调用了 `WTSQuerySessionInformationW`
- 检查是否检测了 `rdpclip.exe` 进程

如遇到此情况，需要在 `RdpBypass.dll` 中补充更多 API Hook。

### 杀毒软件报警

DLL 注入行为可能被安全软件拦截。将 `C:\RdpBypass\RdpBypass.dll` 添加到杀毒软件的白名单即可。

### Install.bat 提示需要管理员权限

修改 `AppInit_DLLs` 注册表需要管理员权限。右键脚本 → 以管理员身份运行。

## 技术细节

- **架构**：x86 (32位)，匹配 PADS 的 32 位进程
- **Hook 库**：[Microsoft Detours](https://github.com/microsoft/Detours)
- **注入方式**：`AppInit_DLLs` 注册表，Windows 在进程初始化时自动加载
- **Hook 目标**：`GetSystemMetrics(SM_REMOTESESSION)` → 强制返回 `0`
- **注册表位置**：`HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows`
- **副作用**：DLL 被加载到所有 32 位进程，但仅修改 `SM_REMOTESESSION` 返回值，对其他程序无影响

## 自行编译

本项目通过 GitHub Actions 自动编译，无需本地安装 Visual Studio。

推送代码到 `main` 分支后自动触发构建，也可在 Actions 页面手动触发。

如需本地编译，要求：
- Windows + Visual Studio 2019/2022（C++ 桌面开发工作负载）
- 编译配置：**Release / x86**
