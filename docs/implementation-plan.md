# Alto: local read-aloud MVP plan

Date: 2026-09-09. Status: MVP implemented; verification and remaining manual checks are recorded in [verification.md](verification.md).

## Outcome

Build a native SwiftUI menu-bar app for Apple Silicon. Select text in another app, press a configurable global shortcut, and hear local AI speech. Kokoro is the default. A floating player based on `/Users/bigb/Repo/clio` provides playback controls; a separate native window manages models and settings. After downloading a complete model, reading works offline without Python, Terminal, an account, or an inference service.

This was the initial plan. The following implementation decisions supersede its provisional runtime choices; the original milestones remain below for context.

## Decisions resolved during implementation

- UI consolidation: all setup, model management, manual text reading and preferences use one native Settings scene with General/Models/Reading/About tabs. The former sidebar window is removed; only the floating player remains separate.
- A radio-noise defect was reproduced in MLX 0.30.2's NAX path on M5. The worker disables TF32 before runtime initialization and ensures Float32 model/voice tensors, retaining ordinary GPU inference. Exact convolution and 24-fixture audio regressions verify the workaround; see [noise investigation](audio-noise-investigation.md).
- The Swift Kokoro loader uses force-unwrapped weights. Inference therefore runs in a persistent bundled native worker, isolating loader failures and allowing Stop to terminate inference. No Python or external service is involved.
- The two verified models are Kokoro full precision and a compact FP16 conversion. The latter needs tensor-name normalization and expansion to Float32; its benefit is a smaller download, not lower runtime memory. A second model family is deferred behind the speech-engine boundary.
- Generation and playback have independent states. Reading replacements invalidate previous requests, pause intent survives generation, and cancellation flushes queued audio. Automated integration exercises these transitions.
- English US/UK is supported end to end. Clearly non-English passages receive an explanatory error; mixed-language detection remains imperfect. The upstream model's full language list is not advertised as app support.
- Clipboard restoration is conditional and best effort. Materializable formats are preserved, promised files and oversized snapshots decline fallback, and newer detected writes are not overwritten. Quitting waits for an in-flight capture transaction to finish.
- Changing voices restarts the current passage. Changing models stops reading and validates the new runtime before updating the saved preference. Deleting the preferred model selects another installed model or returns to model setup.
- The audio queue applies backpressure at 20 seconds, plus at most one generated chunk (rejected above 120 seconds). Selection length is capped at 100,000 characters. Sleep/session deactivation pauses; output configuration changes stop reading. Idle weights unload after 60 seconds.
- Stop also dismisses the player. Show Player reopens it with keyboard focus. The player uses Clio's surface and panel conventions, with separate interactive controls rather than Clio's whole-pill cancellation hit target.
- Release packaging uses Xcode to compile Metal shaders and explicitly embeds native frameworks, resources and the helper. The standalone app was exercised with network access and reads of both development build directories blocked.

## Product decisions

- Target macOS 15+, Apple Silicon M1 or newer, Swift 6. Use a current Xcode toolchain compatible with the pinned dependencies.
- Distribute a standalone `.app`, with a DMG packaging path. Use `LSUIElement` to avoid a persistent Dock icon. Direct distribution is the initial target because cross-app Accessibility and synthetic copy are central features.
- Default shortcut: Option–Space, configurable in Settings. Detect registration failure and provide an inline conflict message. One press reads the current selection and replaces the previous session; player controls handle pause/resume separately.
- Default voice: Kokoro `af_heart`, subject to runtime validation. Start with verified English US/UK support. Show additional languages only when both the model and bundled text-to-phoneme pipeline have been tested for them.
- Speed range: 0.5×–2.0×, default 1.0×, applied immediately through pitch-preserving audio playback.
- No saved text history by default. Text and audio are transient; network access is confined to explicit model setup/import/download actions. No automatic cloud speech fallback.
- MVP includes at least two verified model installations and real switching between them. Prefer a second family to exercise the runtime boundary; voice presets alone do not count as different models.

## Player: use Clio as the actual UI base

Adapt these existing components into Alto-owned sources, preserving attribution where applicable and avoiding a build dependency on the sibling checkout:

| Clio source | Alto adaptation |
| --- | --- |
| `Sources/ClioUI/UI/OverlayView.swift` | Capsule proportions, typography, light/dark surfaces, shadow padding, and entrance/exit transitions |
| `Sources/ClioUI/UI/OverlayController.swift` | Nonactivating `NSPanel`, screen placement, active hover tracking, separate measurement view, and coordinated resizing |
| `Sources/ClioCore/PillSurface.swift` | Surface settings and material fallback; availability-gate newer glass APIs |
| `Sources/ClioUI/UI/HotkeyRecorder.swift` | Shortcut recording interaction, adapted to Alto's shortcut registration |

Start with Clio's 52-point base capsule height and 14-point shadow padding. Default to bottom-center on the originating display, outside the menu-bar menu. Support dragging with position persistence and visible-frame clamping after display changes.

The compact player shows play/pause, a small output waveform or status, voice name, speed, and stop. Voice and speed open small anchored controls. Preparing and buffering show activity; paused playback stays visible; completion fades the player out. Errors provide a brief action such as “Open Models” or “Enable Accessibility.” Keep detailed error text in an expanded surface or Settings.

Preserve Clio's nonactivating presentation, disabled window shadow, and offscreen measurement strategy. Do not reuse its whole-pill `mouseDown` cancellation handler: Alto needs independent working buttons, sliders, and popovers. Do not use Clio's `FloatingWindow` settings helper for the player, since it explicitly activates the app.

Validate actual glass over real windows, not only rendered previews. Cover light/dark appearance, Reduce Motion, Increase Contrast, VoiceOver labels, keyboard access to controls, full-screen Spaces, multiple displays, and display disconnection. Showing the player must preserve the source app's selection and focus; intentional keyboard interaction with player controls must have a clear focus path.

## Runtime choice and feasibility gate

Use Kokoro through an in-process Swift adapter, provisionally [KokoroSwift](https://github.com/mlalma/kokoro-ios), whose documented macOS minimum is 15 and whose default phonemizer is MisakiSwift. It requires separately supplied weights and voice assets. Pin a tested revision and the complete dependency graph after the first working build.

The default weights are [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), published under Apache-2.0. A converted file must match the selected Swift loader; a `.safetensors` extension alone does not establish compatibility. [Another native Kokoro implementation](https://github.com/mweinbach/kokoro-swift) exposes MLX and Core ML paths and can be evaluated if the first adapter has a blocking packaging or correctness issue.

For the second family, evaluate Soprano through [MLX Audio Swift](https://github.com/Blaizzy/mlx-audio-swift), which documents Soprano support. Its [current package manifest](https://raw.githubusercontent.com/Blaizzy/mlx-audio-swift/main/Package.swift) requires Swift 6.2, despite older requirements in its README. Verify compatibility with Kokoro's MLX dependency before committing to both packages.

The [documented Soprano conversion](https://huggingface.co/mlx-community/Soprano-80M-bf16) has an Apache-2.0 model card. The [original publisher](https://huggingface.co/ekwek/Soprano-80M) recommends a newer 1.1 model; evaluate that revision first if the Swift loader supports its converted artifacts. Do not label either candidate supported until it actually synthesizes correctly in Alto.

The first milestone must resolve exact model revisions, all required files, total download bytes, tested languages, license notices, memory use, and successful release-bundle inference. If Soprano cannot coexist with the chosen dependencies, validate another compatible Kokoro weight variant as the second installation and record that limitation. Do not ship an untested model entry as functional merely to populate the browser.

## Architecture

Use small modules with explicit boundaries:

| Module | Responsibilities |
| --- | --- |
| `Alto` | App entry point, lifecycle, bundle configuration |
| `AltoUI` | Menu bar, player, onboarding, model manager, settings, main-actor coordinator |
| `AltoCore` | Selection capture, clipboard transaction, shortcut registration, settings, session state, chunking, playback, model metadata and downloads |
| `AltoSpeech` | Engine protocols, adapter registry, Kokoro and second-model integration; no UI |

An engine adapter exposes identity, supported manifest versions, compatibility validation, voice/language capabilities, local loading, synthesis, cancellation, and unloading. Synthesis produces ordered PCM chunks with sample rate and source-text range. The playback layer does not depend on MLX tensor types. Additional families require an adapter, manifest validator, catalog entries, and integration fixtures; model downloads never execute remote code or load arbitrary plugins.

Use an explicit session state machine: idle, capturing, loading, generating/buffering, playing, paused, stopping, and failed. Generation and playback run concurrently. Tag every request and callback with a session ID so cancelled or replaced work cannot restart playback. Keep MLX work serialized away from the main actor, with tensor evaluation completed before handing audio across the boundary.

## Selected text and shortcut

1. Register a configurable global key combination, preferably using `RegisterEventHotKey`; avoid installing a broad keyboard monitor when registration suffices. Preserve the originating app PID before presenting UI.
2. Check Accessibility permission and read the focused element's selected text through [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement). Where supported, use selected ranges and string-for-range APIs. Bound AX messaging time and avoid unrestricted traversal or reading an entire document.
3. If AX cannot supply text, attempt a transactional Command-C fallback while the original app remains focused. Wait for shortcut modifiers to release before sending the copy events. Never copy from secure/password fields or when secure input prevents this workflow.
4. Snapshot every pasteboard item and every materializable data type, including images and rich text, through [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard). If a complete snapshot cannot be obtained, skip automatic fallback and explain how to read manually copied text.
5. Track pasteboard changes, send Command-C, and await a bounded change notification/poll. Never read stale clipboard text as the selected text. Capture the copied text, then restore the snapshot only if the pasteboard still matches the captured transaction state. Use cleanup on success, failure, timeout, and cancellation. Preserve an originally empty clipboard too.
6. If another process changes the clipboard during the operation, preserve that newer content and abandon ambiguous capture. macOS has no atomic clipboard transaction or reliable writer identity: document this race and test delayed copy handlers and clipboard managers explicitly.
7. Empty selection, unsupported app behavior, or denied permissions produces actionable feedback. Provide a separate “Read Clipboard” command as an explicit recovery path.

“Any app” means apps exposing selected text through AX or normal Copy behavior. Protected fields, inaccessible canvas text, and applications suppressing Copy cannot be guaranteed; explain these limits in onboarding and the README.

## Chunked generation and playback

Segment using sentence and paragraph boundaries, then enforce the adapter's actual phoneme/token limit. Preserve text order and punctuation; split oversized sentences safely without truncating the remainder. Use a shorter first chunk to reduce first-audio latency.

Schedule PCM buffers through `AVAudioEngine` and `AVAudioPlayerNode`, with `AVAudioUnitTimePitch` for speed. Generate ahead into a bounded queue, initially two or three chunks, with backpressure while paused. Treat sentence-level generation as chunking even if the engine lacks internal streaming; do not wait for the full selection before playback.

Pause retains playback position. Stop immediately flushes queued audio and invalidates the session; if an inference kernel cannot be interrupted, discard its result when it returns. Handle underruns, output-device changes, sleep/wake, and sample-rate conversion. Finish only after the last buffer has played, not when generation completes.

Changing voice restarts from the current sentence with the new voice and preserves paused/playing intent. Changing models stops the current reading before unloading and loading; explain that behavior in the model action. Only one model is resident at a time. Avoid crossfades that remove consonants; assess audible seams on real paragraphs.

## Model manager and import contract

Provide a native Models window with Available and Installed views, search, language filtering, detail pane, and clear default/active badges. Each entry shows download size, installed size, languages usable in Alto, voices, minimum OS/chip, recommended RAM, measured runtime memory when available, license, publisher, source, and revision. Distinguish estimated requirements from measured ones.

Bundle a versioned catalog so browsing and installed-model management work offline. Exact download size is the sum of the required files at a pinned revision, including phonemizers, tokenizers, vocabularies, voice embeddings, and auxiliary decoders. Do not derive it from parameter count or display the entire Hugging Face repository size as the install size.

Downloads use `URLSession`, with aggregate byte progress, cancel, retry, and resumable transfers where supported. Preflight disk space for staging plus installation. Download into a staging directory; verify expected lengths, hashes where supplied, file structure, and compatibility before atomic installation. Interrupted or corrupt downloads never appear as ready. Persist enough state to recover after relaunch.

Store models beneath `~/Library/Application Support/Alto/Models/`, with revision-specific directories and installation manifests. Settings and installed metadata remain separate. Delete only Alto-owned assets, with confirmation showing recoverable disk space; stop/unload an active model first. Imported originals remain untouched. Handle shared assets with reference tracking, or initially keep each installation self-contained.

Local import accepts a complete compatible folder or a selected recognized weight file with its required companion files. Copy validated assets into managed storage. Hugging Face import accepts a public repository URL or `owner/repo`, plus optional revision; resolve it to a commit, inspect its manifest/configuration and file metadata, and show a compatibility preview before downloading. MVP does not require gated/private repositories or Git/LFS tools.

Recognize installed adapter schemas, tensor layouts, quantization, configuration, and required voice/tokenizer resources. A missing companion file gets a specific explanation. A valid model for an uninstalled engine gets “This model requires a runtime Alto does not include.” Raw PyTorch `.pt`/`.pth`, arbitrary ONNX/Core ML/GGUF, and unrecognized safetensors are unsupported unless a corresponding adapter explicitly handles them. Never run a downloaded conversion script or require user-side Python. Enforce path containment and reasonable file limits for imports.

Retain license text and notices with each installed model. Curated entries must be freely downloadable and have verified terms permitting the planned distribution/use. For imported models with missing license metadata, show “License not provided” and the source instead of assuming permissive terms.

## Implementation milestones

1. **Prove bundled speech.** Create the app/library skeleton and Xcode project. Pin a working Kokoro adapter, synthesize actual text, bundle all native resources, and repeat with network access disabled and empty external caches. Validate a second model candidate. Record file manifests, dependency compatibility, and timing/memory results.
2. **Deliver the reading loop.** Implement shortcut capture, AX extraction, safe clipboard fallback, chunking, cancellable sessions, and queued audio. Acceptance: selected text in TextEdit and Safari plays before complete generation; pause, resume, speed, and stop work.
3. **Adapt the Clio player.** Port its surface and panel behavior, implement independent controls and voice switching, and add previews for every state. Acceptance: usable nonactivating player over other apps, stable resize transitions, keyboard/VoiceOver access, and correct full-screen/display behavior.
4. **Deliver model management.** Add catalog, resumable downloads, validation, installation, switching, deletion, and both import routes. Acceptance: two real models download and play; missing/unsupported assets have clear errors; interrupted installs recover.
5. **Finish onboarding and offline behavior.** Explain Accessibility, shortcut, model size, and local processing. Provide permission recovery, launch-at-login preference, and settings persistence with backward-compatible decoding. Acceptance: a new user can complete setup through the UI and read after network disconnection and app restart.
6. **Package and document.** Produce a relocatable Release `.app`, DMG build path, notices, and clear README. Test from outside the repository without developer caches. Record remaining limitations and observed performance.

## Verification and completion criteria

Automated tests cover text chunk ordering/token limits, no dropped long-text tail, clipboard snapshot restoration and intervening writes, session replacement/cancellation, bounded playback buffering, manifest validation/path containment, interrupted downloads/checksum failures, model deletion, and settings migration. Use fixtures for normal test runs; isolate real-model integration tests so they never download implicitly.

Manual acceptance covers TextEdit, Safari, Preview PDF selections, an Electron app, a terminal, full-screen apps, and secure fields. Exercise rich-text/image/multi-item/empty clipboards, failed and delayed Copy, permission revocation, a concurrent clipboard write, and source focus changes. Mark unsupported cases honestly.

Test a long selection, rapid repeated shortcuts, pause during generation, voice/model changes, stop during model load, low disk space, corrupt model files, relaunch after interrupted download, output-device change, and sleep/wake. Listen for skipped/repeated sentences and chunk seams.

Performance goals, to measure rather than advertise as proven: player appears within 150 ms; warm Kokoro first audio within 1 second for a short sentence on an M1-class Mac; generation sustains faster than playback at normal speed; stop silences queued playback within 150 ms. Record cold-load latency separately, peak resident memory, and results at 2× speed. If no M1-class test device is available, report the actual test machine and leave that baseline unverified.

Completion requires actual Kokoro speech, a second working model installation, the Clio-based player, both import routes, clipboard preservation tests, and offline playback after relaunch. Mock audio and model cards without working inference do not satisfy the MVP.

## Build/run handoff

Commit an Xcode project with shared Alto scheme, Swift package resolution, app resources, and suitable signing configuration. The README will give an Xcode-first route: open the project, select a signing team if needed, build/run, grant Accessibility, and download Kokoro in the app. Document the exact tested Xcode/macOS versions once the dependency spike is complete.

Provide developer scripts for tests, Release app assembly, and optional DMG/signing/notarization. Package Metal libraries, phonemizer data, tokenizer assets, native frameworks, and notices in the app or verified model installation; no absolute paths into `.build` or the developer's home directory. Developer tools may be needed to build from source; end users only install the app and select models in its UI.

Signing and notarization require the owner's Apple credentials. A local MVP build must remain possible without distribution credentials; document its signing status clearly. Publishing a release is outside this planning deliverable.
