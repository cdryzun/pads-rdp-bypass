#include <windows.h>
#include <detours.h>
#include <stdio.h>
#include <string.h>
#include <tlhelp32.h>
#include <psapi.h>

// 默认 PADS 跳板路径，可通过命令行参数覆盖
#define DEFAULT_PADS_PATH                                                      \
    "D:\\MentorGraphics\\PADSVX.2.4\\SDD_HOME\\common\\win32\\bin\\powerpcb.exe"

// 等待真正的 powerpcb.exe 进程出现（内存 > 阈值）
// 返回进程 PID，超时返回 0
static DWORD WaitForRealProcess(DWORD stubPid, int timeoutMs) {
    int elapsed = 0;
    const int interval = 500;

    while (elapsed < timeoutMs) {
        Sleep(interval);
        elapsed += interval;

        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snap == INVALID_HANDLE_VALUE)
            continue;

        PROCESSENTRY32 pe;
        pe.dwSize = sizeof(pe);
        if (Process32First(snap, &pe)) {
            do {
                // 找 powerpcb.exe 但排除跳板自身
                if (_stricmp(pe.szExeFile, "powerpcb.exe") == 0 &&
                    pe.th32ProcessID != stubPid) {
                    // 检查内存占用 > 10MB 表示是真正的主程序
                    HANDLE proc = OpenProcess(
                        PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE,
                        pe.th32ProcessID);
                    if (proc) {
                        PROCESS_MEMORY_COUNTERS pmc;
                        if (GetProcessMemoryInfo(proc, &pmc, sizeof(pmc))) {
                            if (pmc.WorkingSetSize > 10 * 1024 * 1024) {
                                CloseHandle(proc);
                                CloseHandle(snap);
                                return pe.th32ProcessID;
                            }
                        }
                        CloseHandle(proc);
                    }
                }
            } while (Process32Next(snap, &pe));
        }
        CloseHandle(snap);
    }
    return 0;
}

// 通过 CreateRemoteThread + LoadLibraryA 注入 DLL
static BOOL InjectDll(DWORD pid, const char *dllPath) {
    HANDLE proc =
        OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (!proc) {
        printf("[RunPADS] Cannot open process %lu, error: %lu\n", pid,
               GetLastError());
        return FALSE;
    }

    size_t pathLen = strlen(dllPath) + 1;
    LPVOID remoteMem =
        VirtualAllocEx(proc, NULL, pathLen, MEM_COMMIT | MEM_RESERVE,
                       PAGE_READWRITE);
    if (!remoteMem) {
        printf("[RunPADS] VirtualAllocEx failed, error: %lu\n",
               GetLastError());
        CloseHandle(proc);
        return FALSE;
    }

    if (!WriteProcessMemory(proc, remoteMem, dllPath, pathLen, NULL)) {
        printf("[RunPADS] WriteProcessMemory failed, error: %lu\n",
               GetLastError());
        VirtualFreeEx(proc, remoteMem, 0, MEM_RELEASE);
        CloseHandle(proc);
        return FALSE;
    }

    HMODULE k32 = GetModuleHandleA("kernel32.dll");
    FARPROC loadLib = GetProcAddress(k32, "LoadLibraryA");

    HANDLE thread = CreateRemoteThread(proc, NULL, 0,
                                       (LPTHREAD_START_ROUTINE)loadLib,
                                       remoteMem, 0, NULL);
    if (!thread) {
        printf("[RunPADS] CreateRemoteThread failed, error: %lu\n",
               GetLastError());
        VirtualFreeEx(proc, remoteMem, 0, MEM_RELEASE);
        CloseHandle(proc);
        return FALSE;
    }

    WaitForSingleObject(thread, 5000);
    CloseHandle(thread);
    VirtualFreeEx(proc, remoteMem, 0, MEM_RELEASE);
    CloseHandle(proc);
    return TRUE;
}

int main(int argc, char *argv[]) {
    const char *exePath = (argc > 1) ? argv[1] : DEFAULT_PADS_PATH;

    // 获取 DLL 绝对路径（与本 EXE 同目录）
    char dllPath[MAX_PATH];
    GetModuleFileNameA(NULL, dllPath, MAX_PATH);
    char *lastSlash = strrchr(dllPath, '\\');
    if (lastSlash) {
        *(lastSlash + 1) = '\0';
    }
    strcat_s(dllPath, MAX_PATH, "RdpBypass.dll");

    printf("[RunPADS] Target: %s\n", exePath);
    printf("[RunPADS] DLL:    %s\n", dllPath);

    // 第一步：正常启动跳板程序（不注入）
    printf("[RunPADS] Starting PADS launcher...\n");

    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    // 提取工作目录
    char workDir[MAX_PATH];
    strncpy_s(workDir, MAX_PATH, exePath, MAX_PATH);
    char *wdSlash = strrchr(workDir, '\\');
    if (wdSlash) *wdSlash = '\0';

    BOOL ok = CreateProcessA(exePath, NULL, NULL, NULL, FALSE,
                             0, NULL, workDir, &si, &pi);
    if (!ok) {
        printf("[RunPADS] Failed to start launcher, error: %lu\n",
               GetLastError());
        getchar();
        return 1;
    }

    printf("[RunPADS] Launcher PID: %lu\n", pi.dwProcessId);
    printf("[RunPADS] Waiting for real PADS process...\n");

    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);

    // 第二步：等待真正的 powerpcb.exe 出现（内存 > 10MB）
    DWORD realPid = WaitForRealProcess(pi.dwProcessId, 30000);
    if (realPid == 0) {
        printf("[RunPADS] Timeout: real PADS process not found\n");
        return 1;
    }

    printf("[RunPADS] Found real PADS process, PID: %lu\n", realPid);

    // 第三步：注入 DLL
    printf("[RunPADS] Injecting RDP bypass DLL...\n");
    if (InjectDll(realPid, dllPath)) {
        printf("[RunPADS] Success! DLL injected into PID %lu\n", realPid);
    } else {
        printf("[RunPADS] DLL injection failed!\n");
        return 1;
    }

    return 0;
}
