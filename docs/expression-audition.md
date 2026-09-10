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

## Current validation status

Native expression build completed in run 34484339211; the subsequent launcher parse gate failed due to replacement-string expansion during source generation. The launcher source was corrected in commit 896a4f0348fd7858b8ffa1b25cc42f3f8b754e98.

Verification run 34484628263 / job 102895673864 ended cancelled. Its completed log records expression indices 0 through 8 evaluated, followed by an IOException reading a native status file while the native process had it open for appending. Launcher installation was not reached. This is a status-reader sharing failure, not evidence that expression rendering failed.

The user subsequently confirmed visible expression changes and previously confirmed body movement and recorded audio. This does not establish visual acceptance of all 22 expressions, expression meanings, or mouth appearance.

Commit becf15001dd4275a6f59212b410b80e1ac8af681 corrects the status reader to open append-only native status files with FileShare.ReadWrite and consume only newline-terminated records. This applies to both expression and audio status reads; no exception suppression or automatic replay is added.

Regression run 34485959766 is queued to evaluate every expression, reject an out-of-range index, complete one recorded voice playback, and install the launcher only after success. Runtime regression and installation remain pending.
