# Magireco character asset extraction

This project keeps game-originated assets local on the Windows machine. Git contains only extraction/build tooling and documentation.

## Established local source

- Emulator: Nox
- ADB: `C:\Program Files (x86)\Nox\bin\nox_adb.exe`
- Device: `127.0.0.1:62001`
- Package: `io.kamihama.totentanz`
- Resource root: `/data/data/io.kamihama.totentanz/files/madomagi/resource/`

The extractor starts `Nox.exe` when the established device is not connected, waits for ADB, verifies root access, then reads the private app data without modifying it.

## Reusable tools

### Extract model, scenario and HCA voices

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\probes\Extract-MagirecoCharacter.ps1 `
  -CharacterId 100300 `
  -ScenarioId 100300
```

The extractor copies locally:

- `image_native/live2d_v4/<CharacterId>/`
- `scenario/json/general/<ScenarioId>.json`
- character voice HCA files referenced by the scenario's `vo_char_XXXX_...` prefix

It validates `model.model3.json`, all file references from that model, and records a SHA-256 fingerprint.

Local output root:

```text
%LOCALAPPDATA%\live2d-agent\magireco-assets\<CharacterId>\<runKey>\
  live2d\
  scenario\
  voice-hca\
  manifest.json
```

Current extraction state:

```text
%LOCALAPPDATA%\live2d-agent\magireco-character-<CharacterId>.json
```

### Decode HCA voices to WAV

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\probes\Decode-MagirecoCharacterVoices.ps1 `
  -CharacterId 100300
```

The decoder uses the same pinned `vgmstream` r2117 route used for the Madoka voice verification. Decoded files remain under the character's local asset root in `voice-wav\`.

## Operational request

The private `live2d-agent-notifications` repository contains:

```text
requests/magireco-character.json
.github/workflows/windows-magireco-character-extract.yml
```

Changing the request IDs triggers the Windows self-hosted runner to perform the same extraction and optional voice decoding.

Request format:

```json
{
  "character_id": "100300",
  "scenario_id": "100300",
  "decode_voice": true
}
```

Known default targets currently used by this project:

| Character | Character ID | General scenario ID |
|---|---:|---:|
| Yui Tsuruno | `100300` | `100300` |
| Mami Tomoe | `200500` | `200500` |
| Tart | `402100` | `402100` |

## Safety boundary

- Never commit or upload extracted model, texture, motion, expression, scenario, HCA, WAV, or other game data to GitHub.
- Do not modify files inside the Nox app data directory.
- Build/runtime normalization must operate on copied local data, not on the extracted source snapshot.
- A character extraction is accepted only when all model references resolve and the manifest/fingerprint is produced.
