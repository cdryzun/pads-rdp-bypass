#include <windows.h>
#include <detours.h>
#include <stdio.h>
#include <string.h>

// 默认 PADS 路径，可通过命令行参数覆盖
#define DEFAULT_PADS_PATH                                                      \
    "D:\\MentorGraphics\\PADSVX.2.4\\SDD_HOME\\common\\win32\\bin\\powerpcb.exe"

int main(int argc, char *argv[]) {
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    // 支持通过命令行参数指定 PADS 路径
    const char *exePath =
        (argc > 1) ? argv[1] : DEFAULT_PADS_PATH;

    // 获取 DLL 的绝对路径（与 EXE 同目录）
    char dllPath[MAX_PATH];
    GetModuleFileNameA(NULL, dllPath, MAX_PATH);
    char *lastSlash = strrchr(dllPath, '\\');
    if (lastSlash) {
        *(lastSlash + 1) = '\0';
    }
    strcat_s(dllPath, MAX_PATH, "RdpBypass.dll");

    // 提取 PADS 所在目录作为工作目录
    char workDir[MAX_PATH];
    strncpy_s(workDir, MAX_PATH, exePath, MAX_PATH);
    char *lastSlashWork = strrchr(workDir, '\\');
    if (lastSlashWork) {
        *lastSlashWork = '\0';
    }

    printf("[RunPADS] Target: %s\n", exePath);
    printf("[RunPADS] DLL:    %s\n", dllPath);
    printf("[RunPADS] WorkDir: %s\n", workDir);
    printf("[RunPADS] Launching with RDP bypass...\n");

    BOOL result = DetourCreateProcessWithDllExA(
        exePath,                                      // lpApplicationName
        NULL,                                         // lpCommandLine
        NULL,                                         // lpProcessAttributes
        NULL,                                         // lpThreadAttributes
        FALSE,                                        // bInheritHandles
        CREATE_DEFAULT_ERROR_MODE | CREATE_SUSPENDED, // dwCreationFlags
        NULL,                                         // lpEnvironment
        workDir,                                      // lpCurrentDirectory
        &si,                                          // lpStartupInfo
        &pi,                                          // lpProcessInformation
        dllPath,                                      // lpDllName
        NULL                                          // pfCreateProcessW
    );

    if (!result) {
        DWORD err = GetLastError();
        printf("[RunPADS] Failed! Error code: %lu\n", err);
        printf("[RunPADS] Press any key to exit...\n");
        getchar();
        return 1;
    }

    ResumeThread(pi.hThread);

    printf("[RunPADS] Success! PADS PID: %lu\n", pi.dwProcessId);

    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);

    return 0;
}
