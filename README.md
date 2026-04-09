# PADS RDP Bypass

> **在远程桌面中运行 PADS，无需断开 RDP 回到物理机。**

通过 [Microsoft Detours](https://github.com/microsoft/Detours) Hook `GetSystemMetrics(SM_REMOTESESSION)` API，让 PADS (Siemens EDA / Mentor Graphics) 在 RDP / RDS 远程桌面环境下正常获取 FlexNet 授权。

**一键安装，零配置使用，支持多用户 RDS。**

---

## 为什么需要这个工具？

PADS 的 FlexNet 许可系统会检测远程桌面环境并拒绝授权。硬件工程师远程访问设计工作站时，每次都需要断开 RDP、走到物理机前操作——这在实际工作中非常低效。

本工具通过 Windows `AppInit_DLLs` 机制，在进程初始化阶段自动加载 Hook DLL，拦截远程桌面检测调用并返回"本地环境"，让 PADS 正常运行。

## 快速开始

### 1. 下载

前往 [Releases / Actions](https://github.com/cdryzun/pads-rdp-bypass/actions) 页面，下载最新的 **pads-rdp-bypass-x86** 产物。

### 2. 安装

解压后，右键 `Install.bat` → **以管理员身份运行**：

```
[安装] 创建目录: C:\RdpBypass
[安装] 复制 DLL: C:\RdpBypass\RdpBypass.dll
[安装] 注册表 AppInit_DLLs 已配置
  [OK] 安装完成! 可直接通过 RDP 启动 PADS
```

### 3. 使用

安装完成后，**无需任何额外操作**。通过 RDP 连接，直接双击 PADS 快捷方式启动即可。

### 4. 卸载

右键 `Uninstall.bat` → 以管理员身份运行，自动从备份恢复所有注册表修改。

## 产物清单

| 文件 | 说明 |
|------|------|
| `RdpBypass.dll` | Hook DLL（仅 106KB，依赖 KERNEL32 + USER32） |
| `Install.bat` | 一键安装，幂等，自动备份原始注册表值 |
| `Uninstall.bat` | 一键卸载，从备份恢复，不影响其他 AppInit 配置 |

## 特性

- **一键安装/卸载** — 管理员运行 BAT 脚本即可，幂等设计
- **多用户 RDS 支持** — 所有远程桌面会话自动生效
- **进程初始化阶段 Hook** — 通过 AppInit_DLLs 加载，早于 FlexNet 检查
- **不修改 PADS 文件** — 仅修改注册表，卸载时从备份恢复原状
- **最小化 Hook** — 仅拦截 `SM_REMOTESESSION` 一个参数，其他 API 调用完全透传
- **无外部依赖** — 静态链接 (`/MT`)，DLL 仅依赖系统自带的 kernel32 和 user32
- **CI/CD 自动构建** — GitHub Actions 编译，`git push` 即出二进制

## 工作原理

```
FlexNet 授权检查:
  GetSystemMetrics(SM_REMOTESESSION)
      ↓
  [Hook 拦截] → 强制返回 0（非远程桌面）
      ↓
  FlexNet 认为在本地物理环境 → 授权通过
```

**核心代码仅 30 行**：

```cpp
static int(WINAPI *TrueGetSystemMetrics)(int) = GetSystemMetrics;

int WINAPI FakeGetSystemMetrics(int nIndex) {
    if (nIndex == SM_REMOTESESSION) {
        return 0;  // 伪装本地环境
    }
    return TrueGetSystemMetrics(nIndex);  // 其他参数透传
}
```

## 技术细节

| 项目 | 说明 |
|------|------|
| 架构 | x86 (32位)，匹配 PADS 进程 |
| Hook 库 | [Microsoft Detours v4.0.1](https://github.com/microsoft/Detours) |
| 注入方式 | `AppInit_DLLs` 注册表（系统级，进程初始化前加载） |
| Hook 目标 | `GetSystemMetrics(SM_REMOTESESSION)` → 返回 `0` |
| 编译参数 | MSVC `/MT /O2 /W4`，静态链接，无 VC++ 运行时依赖 |
| CI/CD | GitHub Actions，`windows-latest` + MSVC x86 |

## 常见问题

### PADS 仍报 License 错误？

FlexNet 可能还通过其他方式检测 RDP（注册表 `Terminal Server` 键值、`WTSQuerySessionInformationW` API、`rdpclip.exe` 进程检测等）。如遇到此情况，需在 DLL 中补充更多 Hook。

### 杀毒软件报警？

DLL 注入行为可能被安全软件标记。将 `C:\RdpBypass\RdpBypass.dll` 添加到白名单即可。

### 影响范围？

DLL 通过 AppInit_DLLs 加载到所有 32 位 user32.dll 进程，但仅修改 `SM_REMOTESESSION` 返回值，对其他程序无功能影响。安装时自动备份原始注册表值，卸载时完整恢复。

## 自行编译

```bash
# 本项目通过 GitHub Actions 自动编译，推送即构建
git push origin main

# 本地编译要求: Windows + Visual Studio 2019/2022 (C++ 桌面开发)
# 配置: Release / x86
```

## 相关文章

- [在 RDP 远程桌面中运行 PADS：从 API Hook 到 AppInit_DLLs 的工程实践](blog.md) — 完整技术分析，记录了三次失败方案和最终解决路径

## License

[MIT](LICENSE) - 基于 [Microsoft Detours](https://github.com/microsoft/Detours)（MIT License）构建。
