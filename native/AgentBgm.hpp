#pragma once
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")

class AgentBgm
{
    static int& ModeStorage()
    {
        static int mode = 0; // 0=home (Desiderium), 1=top/OP, 2=mute
        return mode;
    }

    static bool& StartedStorage()
    {
        static bool started = false;
        return started;
    }

    static const char* HomePath()
    {
        return "home-audio/bgm01_anime06.wav";
    }

    static const char* TopPath()
    {
        return "home-audio/bgm00_system01.wav";
    }

    static void ApplyMode()
    {
        const int mode = ModeStorage();
        if (mode == 2)
        {
            PlaySoundA(NULL, NULL, 0);
            return;
        }

        const char* path = mode == 1 ? TopPath() : HomePath();
        if (GetFileAttributesA(path) == INVALID_FILE_ATTRIBUTES)
        {
            if (mode == 0 && GetFileAttributesA(TopPath()) != INVALID_FILE_ATTRIBUTES)
            {
                PlaySoundA(TopPath(), NULL, SND_FILENAME | SND_ASYNC | SND_LOOP | SND_NODEFAULT);
            }
            return;
        }
        PlaySoundA(path, NULL, SND_FILENAME | SND_ASYNC | SND_LOOP | SND_NODEFAULT);
    }

public:
    static void EnsureStarted()
    {
        if (StartedStorage()) return;
        StartedStorage() = true;
        ModeStorage() = 0;
        ApplyMode();
    }

    static void Cycle()
    {
        StartedStorage() = true;
        ModeStorage() = (ModeStorage() + 1) % 3;
        ApplyMode();
    }

    static int Mode()
    {
        return ModeStorage();
    }
};
