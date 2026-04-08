#include <windows.h>
#include <detours.h>

static int(WINAPI *TrueGetSystemMetrics)(int) = GetSystemMetrics;

// 仅拦截 SM_REMOTESESSION (0x1000)，其他参数透传到真实函数
int WINAPI FakeGetSystemMetrics(int nIndex) {
    if (nIndex == SM_REMOTESESSION) {
        return 0;
    }
    return TrueGetSystemMetrics(nIndex);
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD dwReason, LPVOID reserved) {
    if (DetourIsHelperProcess()) {
        return TRUE;
    }

    LONG status;

    if (dwReason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hinst);
        DetourRestoreAfterWith();

        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        status = DetourAttach(&(PVOID &)TrueGetSystemMetrics,
                              FakeGetSystemMetrics);
        if (status != NO_ERROR) {
            DetourTransactionAbort();
            return FALSE;
        }
        status = DetourTransactionCommit();
        if (status != NO_ERROR) {
            return FALSE;
        }
    } else if (dwReason == DLL_PROCESS_DETACH) {
        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        DetourDetach(&(PVOID &)TrueGetSystemMetrics, FakeGetSystemMetrics);
        DetourTransactionCommit();
    }
    return TRUE;
}
