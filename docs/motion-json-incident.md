# Motion and mouth rendering incident — 2026-09-10

## User observations

Recorded voice and lip movement were audible/visible. Motion index 2 still showed no perceived face/body gesture. The user also supplied a close-up showing unwanted marks/overlapping outlines around the mouth. Do not mark either body motion or mouth appearance accepted.

Expression playback was not implemented in the local recorded-voice launcher: loading expression files alone does not activate them.

## Verified diagnosis

An isolated native diagnostic instance observed:
- A motion start attempt failed; all parameters were constant immediately after the motion stage.
- The configured motion parameter IDs all exist in the loaded model.
- Later parameter changes came from the sample's breath/blink processing, not the selected motion.
- All nine motion files reached the loader with nonempty buffers, but the SDK JSON parser rejected all nine.
- UTF-8 BOM was absent; declared point and segment counts matched their actual contents.

The pinned CubismNativeFramework 5-r.5 [ParseNumeric implementation](https://github.com/Live2D/CubismNativeFramework/blob/5-r.5/src/Utils/CubismJson.cpp) terminates numeric tokens on comma or newline. It rejects a directly following closing bracket/brace, space, or exponent notation. The locally exported compact JSON uses numeric array endings that this parser cannot read.

## Fix under validation

`probes/CubismJsonImport.psm1` adapts JSON at the private runtime import boundary:
- Validate ordinary JSON first.
- Tokenize strings and numbers separately; leave strings/IDs unchanged.
- Expand exponent notation mechanically without floating-point recomputation.
- Insert newline immediately after numeric tokens.
- Validate output JSON and write UTF-8 without BOM.
- Apply only to the runtime copy, never original exports.

`Start-LocalVoiceMotion.ps1` applies this before starting the renderer. SDK validation remains enabled; the SDK parser and model parameter values are not patched.

Private workflow `windows-json-import-fix.yml` checks a numeric/string regression fixture and then requires all motion buffers to pass actual SDK parsing/consistency checks, successful motion starts, and changing parameters at the motion stage before replacing the launcher.

## Remaining limits

Mouth appearance has no established cause yet. Recheck after successful motion import, because the previous run never applied the motion's initial parameter state. Do not edit textures, hide mouth drawables, guess expression meanings or force extra mouth parameters without evidence.

No CeVIO calls occur in any of these tests. Native diagnostics close only their own test instance.
