#pragma once
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")

class AgentBgm
{
public:
    static void EnsureStarted(const char* path)
    {
        static bool started = false;
        if (started || path == nullptr) return;
        if (GetFileAttributesA(path) == INVALID_FILE_ATTRIBUTES) return;
        if (PlaySoundA(path, NULL, SND_FILENAME | SND_ASYNC | SND_LOOP | SND_NODEFAULT)) started = true;
    }
};
