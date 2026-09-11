#pragma once

#include <windows.h>
#include <cstddef>
#include <CubismFramework.hpp>
#include <Id/CubismIdManager.hpp>
#include <Model/CubismModel.hpp>

struct AgentHomeScene
{
    double Seconds;
    int Motion;
    const char* Expression;
    float Cheek;
    float Tear;
};

struct AgentHomeSequence
{
    int Voice;
    const AgentHomeScene* Scenes;
    std::size_t Count;
};

struct AgentHomeAction
{
    int Voice;
    int Motion;
    const char* Expression;
};

class AgentHome
{
    static constexpr float Keep = 99.0f;

    bool _startupPending = true;
    bool _tapPending = false;
    bool _active = false;
    bool _emitPending = false;
    bool _voicePending = false;
    bool _cheekSet = false;
    bool _tearSet = false;
    bool _resetTearPending = false;
    float _cheek = 0.0f;
    float _tear = 0.0f;
    int _sequenceIndex = -1;
    std::size_t _sceneIndex = 0;
    unsigned _tapSerial = 0;
    ULONGLONG _bootAt = GetTickCount64() + 500;
    ULONGLONG _sceneStarted = 0;

    static const AgentHomeSequence& Sequence(int index)
    {
        static const AgentHomeScene startup[] = {
            {1.0, 100, "mtn_ex_010.exp3.json", 1.0f, Keep},
            {1.0,  -1, "mtn_ex_011.exp3.json", 2.0f, Keep},
            {4.0,   0, "mtn_ex_010.exp3.json", 1.0f, Keep},
            {1.5,  -1, "mtn_ex_011.exp3.json", 2.0f, Keep},
            {5.0, 100, "mtn_ex_010.exp3.json", 1.0f, Keep},
        };
        static const AgentHomeScene talk1[] = {
            {1.0,   0, "mtn_ex_040.exp3.json", -1.0f, Keep},
            {2.0,  -1, "mtn_ex_041.exp3.json", -1.0f, Keep},
            {3.0, 100, "mtn_ex_040.exp3.json", -1.0f, Keep},
            {3.0, 300, "mtn_ex_020.exp3.json", -1.0f, Keep},
            {2.0,  -1, "mtn_ex_030.exp3.json", -1.0f, Keep},
            {4.0,   0, "mtn_ex_040.exp3.json", -1.0f, Keep},
        };
        static const AgentHomeScene talk2[] = {
            {1.0, 100, "mtn_ex_011.exp3.json", 2.0f, Keep},
            {3.0,   0, "mtn_ex_010.exp3.json", 1.0f, Keep},
            {2.0,  -1, "mtn_ex_011.exp3.json", 2.0f, Keep},
            {2.0, 300, "mtn_ex_010.exp3.json", 1.0f, Keep},
            {2.0,  -1, "mtn_ex_011.exp3.json", 2.0f, Keep},
            {2.0, 100, "mtn_ex_010.exp3.json", 1.0f, Keep},
            {2.0,  -1, "mtn_ex_041.exp3.json", -1.0f, Keep},
        };
        static const AgentHomeScene talk3[] = {
            {4.0,   0, "mtn_ex_030.exp3.json", -1.0f, Keep},
            {4.0, 100, "mtn_ex_040.exp3.json", -1.0f, Keep},
            {1.0,   0, "mtn_ex_041.exp3.json", -1.0f, Keep},
            {5.0,  -1, "mtn_ex_010.exp3.json",  1.0f, Keep},
        };
        static const AgentHomeScene talk4[] = {
            {4.0,   0, "mtn_ex_051.exp3.json", -1.0f, Keep},
            {4.0, 300, "mtn_ex_030.exp3.json", -1.0f, Keep},
            {4.0, 100, "mtn_ex_010.exp3.json",  1.0f, Keep},
        };
        static const AgentHomeScene talk5[] = {
            {4.0,   0, "mtn_ex_040.exp3.json", -1.0f, Keep},
            {4.0, 300, "mtn_ex_030.exp3.json", -1.0f, Keep},
            {6.0, 200, "mtn_ex_020.exp3.json", -1.0f, Keep},
            {3.0,   0, "mtn_ex_010.exp3.json",  1.0f, Keep},
        };
        static const AgentHomeScene talk6[] = {
            {5.0,   0, "mtn_ex_040.exp3.json", -1.0f, Keep},
            {2.0,  -1, "mtn_ex_030.exp3.json", -1.0f, Keep},
            {6.0, 100, "mtn_ex_010.exp3.json",  1.0f, Keep},
            {4.0,  -1, "mtn_ex_011.exp3.json",  2.0f, Keep},
        };
        static const AgentHomeScene talk7[] = {
            {2.0,   0, "mtn_ex_010.exp3.json", 1.0f, Keep},
            {3.0, 100, nullptr,                 Keep, Keep},
            {6.0, 300, "mtn_ex_011.exp3.json", 2.0f, Keep},
        };
        static const AgentHomeScene talk8[] = {
            {3.0, 100, "mtn_ex_051.exp3.json", -1.0f, Keep},
            {3.5, 300, "mtn_ex_040.exp3.json", -1.0f, Keep},
            {7.0,   0, "mtn_ex_051.exp3.json", -1.0f, Keep},
        };
        static const AgentHomeScene talk9[] = {
            {2.0,   0, "mtn_ex_051.exp3.json", 1.0f, Keep},
            {3.0,  -1, "mtn_ex_030.exp3.json", 2.0f, 1.0f},
            {2.0, 300, "mtn_ex_040.exp3.json", 2.0f, 1.0f},
            {3.0,  -1, "mtn_ex_051.exp3.json", 2.0f, 1.0f},
            {4.0,   0, "mtn_ex_030.exp3.json", 2.0f, 1.0f},
        };
        static const AgentHomeSequence sequences[] = {
            {24, startup, sizeof(startup) / sizeof(startup[0])},
            {33, talk1, sizeof(talk1) / sizeof(talk1[0])},
            {34, talk2, sizeof(talk2) / sizeof(talk2[0])},
            {35, talk3, sizeof(talk3) / sizeof(talk3[0])},
            {36, talk4, sizeof(talk4) / sizeof(talk4[0])},
            {37, talk5, sizeof(talk5) / sizeof(talk5[0])},
            {38, talk6, sizeof(talk6) / sizeof(talk6[0])},
            {39, talk7, sizeof(talk7) / sizeof(talk7[0])},
            {40, talk8, sizeof(talk8) / sizeof(talk8[0])},
            {41, talk9, sizeof(talk9) / sizeof(talk9[0])},
        };
        return sequences[index];
    }

    void Begin(int sequenceIndex, ULONGLONG now)
    {
        _sequenceIndex = sequenceIndex;
        _sceneIndex = 0;
        _sceneStarted = now;
        _active = true;
        _emitPending = true;
        _voicePending = true;
        _resetTearPending = false;
        _tearSet = false;
        ApplySceneState(Sequence(_sequenceIndex).Scenes[_sceneIndex]);
    }

    void ApplySceneState(const AgentHomeScene& scene)
    {
        if (scene.Cheek != Keep)
        {
            _cheek = scene.Cheek;
            _cheekSet = true;
        }
        if (scene.Tear != Keep)
        {
            _tear = scene.Tear;
            _tearSet = true;
        }
    }

    static void SetParameter(Live2D::Cubism::Framework::CubismModel* model, const char* name, float value)
    {
        using namespace Live2D::Cubism::Framework;
        CubismIdHandle target = CubismFramework::GetIdManager()->GetId(name);
        for (int i = 0; i < model->GetParameterCount(); ++i)
        {
            if (model->GetParameterId(i) == target)
            {
                model->SetParameterValue(i, value);
                return;
            }
        }
    }

public:
    bool IsActive() const { return _active || _startupPending || _tapPending; }

    bool RequestTap()
    {
        if (_startupPending || _active || _tapPending) return false;
        _tapPending = true;
        return true;
    }

    bool Poll(AgentHomeAction& action)
    {
        action = {-1, -1, nullptr};
        const ULONGLONG now = GetTickCount64();
        if (!_active)
        {
            if (_startupPending && now >= _bootAt)
            {
                _startupPending = false;
                Begin(0, now);
            }
            else if (_tapPending)
            {
                _tapPending = false;
                ++_tapSerial;
                const int tapIndex = 1 + static_cast<int>((now + static_cast<ULONGLONG>(_tapSerial) * 2654435761ULL) % 9ULL);
                Begin(tapIndex, now);
            }
            else
            {
                return false;
            }
        }

        const AgentHomeSequence& sequence = Sequence(_sequenceIndex);
        if (!_emitPending)
        {
            while (_active)
            {
                const AgentHomeScene& current = sequence.Scenes[_sceneIndex];
                const ULONGLONG durationMs = static_cast<ULONGLONG>(current.Seconds * 1000.0 + 0.5);
                if (now - _sceneStarted < durationMs) return false;
                _sceneStarted += durationMs;
                ++_sceneIndex;
                if (_sceneIndex >= sequence.Count)
                {
                    _active = false;
                    _cheekSet = false;
                    if (_tearSet)
                    {
                        _tearSet = false;
                        _resetTearPending = true;
                    }
                    return false;
                }
                ApplySceneState(sequence.Scenes[_sceneIndex]);
                _emitPending = true;
                break;
            }
        }

        if (!_emitPending) return false;
        const AgentHomeScene& scene = sequence.Scenes[_sceneIndex];
        action.Voice = _voicePending ? sequence.Voice : -1;
        action.Motion = scene.Motion;
        action.Expression = scene.Expression;
        _voicePending = false;
        _emitPending = false;
        return true;
    }

    void ApplyOverrides(Live2D::Cubism::Framework::CubismModel* model)
    {
        if (_active)
        {
            if (_cheekSet) SetParameter(model, "ParamCheek", _cheek);
            if (_tearSet) SetParameter(model, "ParamTear", _tear);
        }
        else if (_resetTearPending)
        {
            SetParameter(model, "ParamTear", 0.0f);
            _resetTearPending = false;
        }
    }
};
