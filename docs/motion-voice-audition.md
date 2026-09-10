# Motion and voice audition — 2026-09-10

## Confirmed requirements
Official Cubism SDK; private model stays on Windows. CeVIO CS7 Sasara; other work has priority. No host shutdown. This audition does not define production idle/tap/notification policies.

## Verified observations
The user confirmed the private model displays correctly. Prior standalone CS7 synthesis and audible playback were confirmed separately.
The dedicated runner installed and parsed the initial audition scripts and counted nine motions. This is not motion playback or audio integration verification.

## Implementation and use
After the latest windows-audition-setup workflow succeeds, run in ordinary Windows PowerShell:

```powershell
& (Join-Path $env:LOCALAPPDATA 'live2d-agent\Launch-MotionVoice.cmd')
```

Choose a displayed motion number (0–8). The launcher copies the private runtime into a unique local directory and assigns only the selected motion to the official sample's Idle slot in that copy. This is an explicit audition mapping, not a determination that the motion is an appropriate idle animation. The original configuration and motion files are unchanged. Close the newly opened window when finished; the temporary copy is removed after that process exits.

At the CeVIO prompt, type FREE only when makemovie and other work are not using CeVIO. Enter skips all CeVIO access. A separate Windows PowerShell process runs the existing standalone voice probe; the host is never closed. The fixed test sentence says movement and voice are being checked and lip synchronization remains to be done. Output and temporary WAV stay on Windows, not in Actions logs.

## Technical limits and unverified behavior
The model and voice tests run independently. No actual audio-position lip synchronization, topmost implementation, production motion arbitration, notification input, or persistent assistant lifecycle is provided by this launcher. Speech can start before the rendering window finishes loading. An existing model window is not controlled or closed. A failed voice probe leaves the new window available for inspection.
Current CeVIO occupancy cannot be inferred from the host process being present. Connection release needs a separate other-app test after the worker exits.
The new audition's motion playback and audible speech still require user observation. Earlier standalone results do not establish their integration.

## Remaining decisions
Which model motion is suitable for idle; tap responses and conflicts; expiry/pause/retry/multiple-job policy. Web ChatGPT and Codex end-to-end notification acceptance remain separate pending checks.
