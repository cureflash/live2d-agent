# Native speech synchronization probe

## Confirmed user observations
2026-09-10: private model display confirmed by the user. The motion/voice audition launcher produced audible Sasara speech, confirmed with "喋った". This confirms independent speech playback, not lip synchronization.

## Implemented scope
The isolated D3D11 application uses official Cubism Core/Framework and an explicit source patch in the sample application's model-update and window-lifecycle owners. Existing SDK and model source assets remain unchanged.
AgentAudio owns configured LipSync parameters immediately after other updaters and before Cubism model evaluation; the sample's independent lip updater is removed from this application copy.
Playback uses waveOut. WAV RMS is sampled at the output device position, not elapsed synthesis time. Only PCM16 mono/stereo is supported; unsupported audio and nonexistent lip parameters fail. This is amplitude mouth opening, not phonetic mouth shapes. The factor 4 and 10 ms RMS window are provisional tuning values for this probe.
The window requests topmost status. Visual acceptance is still required.

Each ready command has a 32-character lowercase hexadecimal ID. Before audio submission a CREATE_NEW claim is persisted. A repeated ID in the same runtime is suppressed, including after restarting that runtime. A crash after claim is ambiguous and is not automatically retried. No production retry or retention policy is implied.
Status distinguishes accepted, playback submitted, device-position advancement, completion, interruption, and failure. Device position is not a microphone measurement of audible onset.

## Interactive local test
Run in ordinary Windows PowerShell:

```powershell
& (Join-Path $env:LOCALAPPDATA 'live2d-agent\Launch-SyncSpeech.cmd')
```

Type FREE only when CeVIO is available and keep it available until the one speech test ends. The launcher starts its own isolated renderer; an independent child PowerShell synthesizes the same text/settings used for phoneme validation. The child exits before native playback. CeVIO host shutdown/restart is never called. User confirmation of availability is not automated occupancy detection.

The new renderer uses the original private model configuration. No production idle motion has been selected. The previous numbered motion audition remains separate.

## One notification from this Work chat
Run:

```powershell
& (Join-Path $env:LOCALAPPDATA 'live2d-agent\Launch-SyncReceive.cmd')
```

Type FREE; wait for WAITING_FOR_NOTIFICATION. Keep the PowerShell and renderer open. The GitHub delivery workflow may then place one fixed test sentence into this explicit receiver session. It checks receiver process identity/start time and session ID. Delivery jobs neither synthesize audio nor own the GUI.
The receiver accepts one command, synthesizes it, submits its WAV to the renderer, and records completion locally. Another command is rejected; this is intentionally a single-command transport test, not the production latest-pending queue.
The public repository must contain only a nonprivate fixed test payload, never actual work progress. Private production transport/authentication remains undecided. Do not generalize this Work connector to every ChatGPT web interface.

## Technical verification and limits
Native build: Actions run 34464486146 succeeded.
Initial device tests reached accepted → playback submitted → device position advanced → playback completed → duplicate suppressed. They failed their final lifecycle gate because CloseRequested, WaitReturned and HasExited were true but the PowerShell Start-Process returned object's ExitCode was null.
The test and launcher now own a System.Diagnostics.Process directly and drain its redirected streams asynchronously. The exit-code gate is retained, not relaxed. Its rerun result must be checked before calling the smoke test successful.

Synthesis worker and launcher scripts are installed and syntax-checked on Windows. The new synthesis worker's full execution with CeVIO and native renderer still requires the interactive test.
No new connection to CeVIO was made by setup/build/synthetic-audio test jobs.

## Still unverified or unimplemented
Actual Sasara/native lip-sync visual and audible acceptance; topmost visual acceptance; device-loss and interrupted-speech mouth-reset acceptance; after-exit other-app CeVIO use; end-to-end notification latency. ActualAudioOnsetMs remains null; startup and worker timings are separate. No 10-second guarantee.
Web Work one-shot delivery is prepared but has not yet been exercised with this receiver. Codex delivery remains separately unverified and no automatic Codex event hook has been configured.
Continuous progress input, active-plus-latest-pending production queue, pause/resume and sleep/restart policy, tap arbitration, expressions/gesture selection and quality acceptance remain unfinished. These require their existing unresolved decisions; this probe does not settle them.
SDK/model/audio binaries and private runtime diagnostics remain on Windows and are not committed or uploaded.
Playback position API: https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutgetposition
Playback completion flag: https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutwrite
