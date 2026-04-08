# PADS RDP Bypass

通过 Microsoft Detours Hook `GetSystemMetrics(SM_REMOTESESSION)`，让 PADS 在远程桌面 (RDP) 环境下正常运行，绕过 FlexNet 的远程会话检测。

## 原理

PADS 启动时，FlexNet 许可系统会调用 `GetSystemMetrics(SM_REMOTESESSION)` 检测是否运行在 RDP 会话中。如果检测到远程桌面，会拒绝启动并报 License 错误。

本工具通过 Detours 在进程创建时注入 DLL，拦截该 API 调用并强制返回 `0`（非远程桌面），其他所有调用正常透传。

## 下载

前往本仓库的 [Actions](../../actions) 页面，点击最新一次成功的构建，下载 **pads-rdp-bypass-x86** 产物压缩包。

压缩包内含两个文件：

| 文件 | 说明 |
|------|------|
| `RunPADS.exe` | 启动器，负责创建进程并注入 DLL |
| `RdpBypass.dll` | Hook DLL，拦截远程桌面检测 |
| `RunPADS.bat` | 一键启动脚本，双击即用 |

## 使用方法

### 1. 部署

将 `RunPADS.exe` 和 `RdpBypass.dll` 放在**同一个文件夹**中。可以放在：
- 桌面
- PADS 安装目录（如 `D:\MentorGraphics\PADSVX.2.8\SDD_HOME\Programs\`）
- 任意你喜欢的位置

### 2. 配置路径

用记事本打开 `RunPADS.bat`，修改第 7 行的 PADS 路径为你的实际安装路径：

```bat
set "PADS_EXE=D:\MentorGraphics\PADSVX.2.8\SDD_HOME\Programs\powerpcb.exe"
```

### 3. 启动 PADS

通过 RDP 远程连接到目标电脑后，有三种启动方式：

**方式一：双击 BAT 脚本（推荐，最简单）**

直接双击 `RunPADS.bat`，脚本会自动检查文件是否齐全并启动 PADS。

**方式二：命令行指定路径**

```cmd
RunPADS.exe "D:\MentorGraphics\PADSVX.2.8\SDD_HOME\Programs\powerpcb.exe"
```

**方式三：使用默认路径**

直接双击 `RunPADS.exe`，将使用编译时的默认路径：

```
C:\MentorGraphics\PADSVX.2.8\SDD_HOME\Programs\powerpcb.exe
```

### 4. 创建快捷方式（可选）

为了方便日常使用，可以创建一个桌面快捷方式：

1. 右键 `RunPADS.bat` → 发送到 → 桌面快捷方式
2. 重命名为 `PADS (RDP模式)`
3. 以后双击快捷方式即可

## 启动输出示例

```
[RunPADS] Target: D:\MentorGraphics\PADSVX.2.8\SDD_HOME\Programs\powerpcb.exe
[RunPADS] DLL:    C:\Users\你的用户名\Desktop\RdpBypass.dll
[RunPADS] WorkDir: D:\MentorGraphics\PADSVX.2.8\SDD_HOME\Programs
[RunPADS] Launching with RDP bypass...
[RunPADS] Success! PADS PID: 12345
```

## 常见问题

### 启动失败，错误码 2

**原因**：PADS 路径不存在。

**解决**：确认 `powerpcb.exe` 的实际安装路径，通过命令行参数传入正确路径。

### 启动失败，错误码 740

**原因**：需要管理员权限。

**解决**：右键 `RunPADS.exe` → 以管理员身份运行。

### 启动成功但 PADS 仍报 License 错误

**可能原因**：FlexNet 除了 `GetSystemMetrics` 外还通过其他方式检测 RDP。

**排查方向**：
- 检查注册表 `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server`
- 检查是否调用了 `WTSQuerySessionInformationW`
- 检查是否检测了 `rdpclip.exe` 进程

如遇到此情况，需要在 `RdpBypass.dll` 中补充更多 API Hook。

### 杀毒软件报警

DLL 注入行为可能被安全软件拦截，这是正常现象。将 `RunPADS.exe` 和 `RdpBypass.dll` 添加到杀毒软件的白名单/排除列表即可。

## 技术细节

- **架构**：x86 (32位)，匹配 PADS 的 32 位进程
- **Hook 库**：[Microsoft Detours](https://github.com/microsoft/Detours)
- **注入方式**：`DetourCreateProcessWithDllExA`，在进程创建时注入，早于任何业务逻辑
- **Hook 目标**：`GetSystemMetrics(SM_REMOTESESSION)` → 强制返回 `0`
- **副作用**：仅影响 `SM_REMOTESESSION` 查询，其他系统指标正常透传

## 自行编译

本项目通过 GitHub Actions 自动编译，无需本地安装 Visual Studio。

推送代码到 `main` 分支后自动触发构建，也可在 Actions 页面手动触发。

如需本地编译，要求：
- Windows + Visual Studio 2019/2022（C++ 桌面开发工作负载）
- 编译配置：**Release / x86**
