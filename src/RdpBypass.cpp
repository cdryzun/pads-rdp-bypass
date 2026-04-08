#include <windows.h>
#include <detours.h>

// 保存系统原始的 GetSystemMetrics 函数地址
static int(WINAPI *TrueGetSystemMetrics)(int) = GetSystemMetrics;

// 替代函数：拦截 SM_REMOTESESSION 查询
int WINAPI FakeGetSystemMetrics(int nIndex) {
    if (nIndex == SM_REMOTESESSION) {
        return 0; // 强制返回"非远程桌面"
    }
    return TrueGetSystemMetrics(nIndex);
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD dwReason, LPVOID reserved) {
    if (DetourIsHelperProcess()) {
        return TRUE;
    }

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
