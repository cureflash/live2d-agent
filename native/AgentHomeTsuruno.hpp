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

class AgentHomeTsuruno
{
    static constexpr float Keep = 99.0f;

    bool _startupPending = true;
    bool _active = false;
    bool _emitPending = false;
    bool _voicePending = false;
    bool _cheekSet = false;
    float _cheek = 0.0f;
    std::size_t _sceneIndex = 0;
    ULONGLONG _bootAt = GetTickCount64() + 500;
    ULONGLONG _sceneStarted = 0;

    static const AgentHomeSequence& Sequence()
    {
        // Tsuruno Yui (100300) group_16. This probe intentionally disables
        // audio and expressions so movement can be validated independently.
        static const AgentHomeScene startup[] = {
            {0.5,   0, nullptr, 1.0f, Keep},
            {0.5,  -1, nullptr, 2.0f, Keep},
            {4.0, 101, nullptr, 1.0f, Keep},
            {2.7, 200, nullptr, 2.0f, Keep},
            {4.3, 400, nullptr, 0.0f, Keep},
        };
        static const AgentHomeSequence sequence = {
            -1,
            startup,
            sizeof(startup) / sizeof(startup[0]),
        };
        return sequence;
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

    void Begin(ULONGLONG now)
    {
        _sceneIndex = 0;
        _sceneStarted = now;
        _active = true;
        _emitPending = true;
        _voicePending = true;
        ApplySceneState(Sequence().Scenes[_sceneIndex]);
    }

    void ApplySceneState(const AgentHomeScene& scene)
    {
        if (scene.Cheek != Keep)
        {
            _cheek = scene.Cheek;
            _cheekSet = true;
        }
    }

public:
    bool IsActive() const { return _active || _startupPending; }

    bool RequestTap() { return false; }

    bool Poll(AgentHomeAction& action)
    {
        action = {-1, -1, nullptr};
        const ULONGLONG now = GetTickCount64();
        if (!_active)
        {
            if (_startupPending && now >= _bootAt)
            {
                _startupPending = false;
                Begin(now);
            }
            else
            {
                return false;
            }
        }

        const AgentHomeSequence& sequence = Sequence();
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
        if (_active && _cheekSet)
        {
            SetParameter(model, "ParamCheek", _cheek);
        }
    }
};
