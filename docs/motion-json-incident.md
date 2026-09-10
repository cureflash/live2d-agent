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

## Windows verification and installation

Run 34483233080 / job 102890958995 succeeded:
- Numeric/string regression preserved fixture values and the literal ID.
- Nine Motion entries plus the copied Idle entry passed SDK JSON validity and motion consistency.
- Six motion starts succeeded; zero failed.
- 723 frames were observed. Motion-stage ranges included head Y 48.6317, head Z 41.077, body Y 17.6917, and arms 19.
- The test window closed normally with exit code 0.
- Launch-MadokaVoice.cmd now points to the corrected import launcher.
- CeVIO was not accessed.

The preceding run 34482850316 failed its combined normal-close check, which did not distinguish closure failure from exit status. Its cause remains undetermined; it did not install the launcher. The successful follow-up separately recorded the close request and exit code and retained the original parsing/motion gates.

User visual acceptance of the corrected body motion and mouth appearance is still pending. Expression selection remains unimplemented.
