# Numbered expression audition

Body motion after the JSON import fix was visually confirmed by the user. Mouth appearance is explicitly deferred.

The recorded-voice launcher now supports an expression command, `e N`, alongside existing voice numbers. Expression names/numbers come from the private model configuration; emotional meanings are not assigned. This is console audition, not finalized tap behavior.

The renderer validates the index, loaded expression and its parameter IDs, then starts it through the official SDK expression manager. A bounded local status reports start and evaluation. SDK expression blending runs after the base motion, and audio mouth opening remains the existing later owner. No extra mouth corrections are included.

The console waits for the current voice clip to finish before accepting another command. Existing motion selection on launch is unchanged. No notification, multi-work or tap arbitration policy is added.

Implementation:
- native/AgentExpression.hpp
- native/expression-control.patch (application-source integration)
- probes/Start-LocalVoiceMotion.ps1

Private build workflow windows-expression-build.yml validates every model expression through the running SDK, rejects an out-of-range index, then checks recorded-audio playback completion before installing the launcher. GUI appearance requires separate user observation.

No CeVIO access; no game assets, model files or decoded voice files are committed or uploaded.
