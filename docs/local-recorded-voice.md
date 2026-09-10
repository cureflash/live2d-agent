# Local recorded voice and motion audition (CeVIO-free)

## Confirmed scope

Temporary private playback of the user's existing model and locally exported recorded voice clips. No CeVIO loading, host start, synthesis, connection or shutdown occurs. The original model/audio exports remain unchanged. A dedicated runtime copy uses the already-built official Cubism SDK renderer.

This mode plays existing recordings. It does not generate arbitrary progress sentences in the recorded character's voice.

## Implementation

- `probes/LocalPcmWave.psm1` validates RIFF bounds, PCM16 mono/stereo, sample rate, alignment and data length against the native player's requirements.
- `probes/Start-LocalVoiceMotion.ps1` loads a Windows-local voice manifest, validates clips and model motions, asks for a motion number, and starts its own model instance.
- A selected motion is assigned to the copied configuration's Idle group solely for looping audition. Original group names, files and source model are unchanged. Motion numbers have no asserted emotional/idle meaning.
- The console accepts a voice number and waits for that recording to finish before accepting another choice. Enter selects 0; q requests normal closure of this instance.
- Audio uses the existing native waveOut player and actual device position for RMS mouth opening. It is not phoneme-specific lip shaping.
- Each playback gets a new ID; failure/interruption is reported without automatic replay.
- Local status logs keep playback stage and identifiers. No model, audio or decoded WAV is uploaded to Git or Actions artifacts.

## Dependencies

Existing private model staging and successful native sync build, Windows PowerShell 5.1, and a local `madoka-voice-bank.json` manifest under `%LOCALAPPDATA%\\live2d-agent`.

The private setup workflow downloads the upstream portable [vgmstream r2117](https://github.com/vgmstream/vgmstream/releases/tag/r2117) win64 release into this application's tools directory; no installer, PATH or system setting change is used. Archive SHA256 is checked against release asset metadata: `6c4a8a3813864fefed081bbd337dbc0ad93bf88e0b92f5db98d7ab258b22dc6c`. Conversion uses upstream CLI `-i -W 1 -o` (one full stream, PCM16 output). Its package/license files remain alongside the executable.

## Launch after private setup succeeds

```powershell
& (Join-Path $env:LOCALAPPDATA 'live2d-agent\Launch-MadokaVoice.cmd')
```

Choose a motion number (Enter = 0), wait for the model window, then choose a voice number (Enter = 0). For a different motion, close this instance and relaunch. Other model windows are not closed.

## Verification status, 2026-09-10

Read-only Windows inventory: 43 HCA candidates found in an existing export, no scan errors. Filenames correspond to the provisional model's character ID. File existence and names alone do not confirm the audible speaker or line content.

The setup workflow is responsible for validating every decoded WAV, preflight of every motion/voice path, and a bounded native playback test using one actual recorded clip. Run results are tracked separately; implementation is not evidence of completed playback.

## Still unconfirmed

- Human confirmation of speaker, intelligibility, correct decoding, loudness, mouth sync and motion quality.
- Semantic pairing of each recording with a gesture/expression.
- Tap behavior and production notification policy remain the original unresolved requirements.
- No conclusion about game asset redistribution or character licensing follows from private playback. No private assets or SDK binaries are included in this repository.
