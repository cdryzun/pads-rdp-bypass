#include <windows.h>
#include <detours.h>
#include <string.h>

// 保存真实函数地址
static int(WINAPI *TrueGetSystemMetrics)(int) = GetSystemMetrics;
static BOOL(WINAPI *TrueCreateProcessA)(
    LPCSTR, LPSTR, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES, BOOL, DWORD,
    LPVOID, LPCSTR, LPSTARTUPINFOA, LPPROCESS_INFORMATION) = CreateProcessA;
static BOOL(WINAPI *TrueCreateProcessW)(
    LPCWSTR, LPWSTR, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES, BOOL, DWORD,
    LPVOID, LPCWSTR, LPSTARTUPINFOW, LPPROCESS_INFORMATION) = CreateProcessW;

// 获取自身 DLL 路径
static char g_dllPath[MAX_PATH] = {0};

static void InitDllPath(HINSTANCE hinst) {
    GetModuleFileNameA(hinst, g_dllPath, MAX_PATH);
}

// Hook: GetSystemMetrics - 核心功能，伪装非远程桌面
int WINAPI FakeGetSystemMetrics(int nIndex) {
    if (nIndex == SM_REMOTESESSION) {
        return 0;
    }
    return TrueGetSystemMetrics(nIndex);
}

// Hook: CreateProcessA - 让子进程也注入我们的 DLL
BOOL WINAPI FakeCreateProcessA(LPCSTR lpApp, LPSTR lpCmd,
                               LPSECURITY_ATTRIBUTES lpPA,
                               LPSECURITY_ATTRIBUTES lpTA, BOOL bInherit,
                               DWORD dwFlags, LPVOID lpEnv, LPCSTR lpDir,
                               LPSTARTUPINFOA lpSI, LPPROCESS_INFORMATION lpPI) {
    return DetourCreateProcessWithDllExA(lpApp, lpCmd, lpPA, lpTA, bInherit,
                                        dwFlags, lpEnv, lpDir, lpSI, lpPI,
                                        g_dllPath, NULL);
}

// Hook: CreateProcessW - 同上，宽字符版
BOOL WINAPI FakeCreateProcessW(LPCWSTR lpApp, LPWSTR lpCmd,
                               LPSECURITY_ATTRIBUTES lpPA,
                               LPSECURITY_ATTRIBUTES lpTA, BOOL bInherit,
                               DWORD dwFlags, LPVOID lpEnv, LPCWSTR lpDir,
                               LPSTARTUPINFOW lpSI, LPPROCESS_INFORMATION lpPI) {
    return DetourCreateProcessWithDllExW(lpApp, lpCmd, lpPA, lpTA, bInherit,
                                        dwFlags, lpEnv, lpDir, lpSI, lpPI,
                                        g_dllPath, NULL);
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD dwReason, LPVOID reserved) {
    if (DetourIsHelperProcess()) {
        return TRUE;
    }

    if (dwReason == DLL_PROCESS_ATTACH) {
        InitDllPath(hinst);
        DetourRestoreAfterWith();
        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        DetourAttach(&(PVOID &)TrueGetSystemMetrics, FakeGetSystemMetrics);
        DetourAttach(&(PVOID &)TrueCreateProcessA, FakeCreateProcessA);
        DetourAttach(&(PVOID &)TrueCreateProcessW, FakeCreateProcessW);
        DetourTransactionCommit();
    } else if (dwReason == DLL_PROCESS_DETACH) {
        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        DetourDetach(&(PVOID &)TrueGetSystemMetrics, FakeGetSystemMetrics);
        DetourDetach(&(PVOID &)TrueCreateProcessA, FakeCreateProcessA);
        DetourDetach(&(PVOID &)TrueCreateProcessW, FakeCreateProcessW);
        DetourTransactionCommit();
    }
    return TRUE;
}
