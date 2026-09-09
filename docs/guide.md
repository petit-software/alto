# Alto

A native macOS menu-bar reader. Select text, press **Option–Space**, and listen
with Kokoro voices generated entirely on your Mac. The floating player adapts
Clio's tinted glass capsule and nonactivating panel.

## Run

Requires **Apple Silicon and macOS 15 or later**. No Python, Terminal setup,
account, or hosted inference is required to use the built app.

The worker includes a full-precision safeguard for an MLX defect that caused
radio-like noise on M5 with longer passages. Existing model downloads can be
reused; quit an older running Alto and open the rebuilt app. See the
[diagnosis and regression checks](audio-noise-investigation.md).

1. Open `dist/Alto.app` (or copy it to Applications).
2. In **Settings → Models**, download **Kokoro** (~329 MB) or **Kokoro Compact** (~164 MB).
3. Enable Alto in **System Settings → Privacy & Security → Accessibility**.
4. Select English text in another app and press **Option–Space**. Change the
   shortcut in Alto → Settings if another app uses it.

The pill appears only after text is captured and validated for reading. It has
play/pause and **X**, which cancels capture/generation, stops audio and dismisses
the player. **Settings → Reading → Player Appearance** offers Clio-style position
choices (Hidden, six edge positions, Near cursor), Default/1.25×/1.5× sizing,
Translucency and Clear glass. Position affects the standalone player; size and
glass apply to both. Hidden keeps playback running with controls in the menu.
A scrollable developer preview above the pill shows the captured text being read.
The preview stays in memory only and clears when reading stops or completes.
Speech skips HTML/XML markup and emojis, while keeping the text inside tags.
The preview shows the filtered speech text. Pasting into the editor also removes
tags and emojis; the original source app and clipboard are not changed. Paste is
beside Play in the editor's floating pill; use the player's X to close. The pill
overlays the text canvas, with scroll clearance for the final lines. Hashtags such as `#topic` are
ordinary text, not markup tags.
Voice and 0.5×–2× speed are also in **Settings → Reading**.
**Show Player** is available only during a reading and
gives the pill keyboard focus. Changing voice restarts the current
passage. Switching models stops reading and checks the new model before saving
your choice. If loading fails, the previous preference is preserved.

**Read Text…** in the menu opens a dedicated paste window with the player at the
bottom. Press Play to read; X or closing the window stops reading and clears the
draft. Voice, speed and player size remain in Settings. You can also choose
**Read Clipboard** from the menu. These routes don't require selection access.

General, Models, Reading, and About all live in the native Settings window.
There is no separate sidebar window. **Models…** and **Finish Setup…** open
Settings; **Read Text…** opens its dedicated editor.

## Build from source

Tested with Xcode 26.6 / Swift 6.3.3. The pinned speech dependencies require Swift
6.2 or later. Use full Xcode, including Metal toolchain support; command-line
SwiftPM alone cannot compile the MLX Metal shaders.

Open **Alto.xcodeproj**, select the **Alto** scheme and **My Mac**, then Run.
Swift packages resolve automatically on the first build. The project uses local
ad-hoc signing by default; a consistent Apple Development identity is preferable
when testing Accessibility across rebuilds.

To produce the standalone bundle:

```sh
./scripts/build-app.sh
open dist/Alto.app
```

For a Debug bundle, use `./scripts/build-app.sh Debug`. `project.yml` is the source
of the checked-in Xcode project; regenerate with `xcodegen generate` only when
changing its structure. XcodeGen is a developer convenience, not a user dependency.

The build script uses an available Apple Development certificate to keep the
app's Accessibility identity stable across rebuilds. Without one, it warns and
falls back to ad-hoc signing. Override with `ALTO_CODE_SIGN_IDENTITY` and, if
needed, `ALTO_DEVELOPMENT_TEAM`; use `ALTO_CODE_SIGN_IDENTITY=-` for ad-hoc builds.
Direct Xcode runs still use the project's ad-hoc default unless you configure
Signing & Capabilities with your development identity and team.

If macOS denies selection access even though Alto is listed as enabled, remove
the old entry in System Settings → Privacy & Security → Accessibility and add
the current `dist/Alto.app`, then quit and reopen Alto. Settings → General →
Show This Copy of Alto in Finder identifies the exact running copy. macOS must
receive your approval; Alto cannot grant itself access. Manually copying text
and choosing Read Clipboard works without Accessibility access.

`./scripts/package-dmg.sh` makes `dist/Alto-0.1.0.dmg`. Local builds are
**not notarized**. Public distribution requires Developer ID signing of
the embedded frameworks, worker, and app, followed by notarization and stapling.
Do not treat this local DMG as a completed public release.

## Models and formats

Both curated entries use the Kokoro v1 family and include Heart, Michael, Emma,
and George. Their cards show pinned sources, download bytes, licenses, languages,
and hardware guidance. All runtime resources and English phonemizer dictionaries
ship in the app. After a complete download, playback and model switching work
offline; model browsing uses the bundled catalog.

Kokoro Compact uses a community half-precision conversion. Alto normalizes its
tensor names and prepares full-precision weights inside the native worker. It
saves download/storage space, **not runtime memory**; allow another 400 MB of
temporary disk space during preparation. 8 GB system RAM is an initial
recommendation, not a measured minimum. See [verification](verification.md)
for the actual test machine and performance measurements.

Import from your Mac by choosing a folder or weight file with this structure:

```text
MyKokoro/
  kokoro-v1_0.safetensors
  voices/
    af_heart.safetensors
    bf_emma.safetensors
  README.md                 # optional model card
  LICENSE                   # optional source license
  config.json               # optional; runtime uses its pinned Kokoro v1 config
```

Weights must match the bundled Kokoro v1 tensor schema; voices must have shape
`[510, 1, 256]` in a single safetensors tensor. Only English `af_`, `am_`, `bf_`,
and `bm_` voices are supported. Imports copy assets; originals remain intact.
Models removed in the UI go to Trash and can be recovered.

Hugging Face import accepts `owner/repository` or its public repository URL,
plus a branch/tag/commit in the Revision field. It previews the required download
and license, resolves a fixed commit, and validates tensors before installation.
For example, `mlx-community/Kokoro-82M-bf16` offers additional English voices.

PyTorch `.pth`/`.pt`, `.onnx`, Core ML packages, GGUF, quantized/sharded weights,
NPY/NPZ voices, and other model families are not accepted by this runtime.
Renaming a file does not convert it. Alto never runs downloaded code or asks
users to install conversion tools. Gated/private repositories are outside this MVP.

Downloads report progress and support pause/retry. Completed files and available
URLSession resume data survive relaunch; a server may require restarting an
incomplete file. Checksums are verified when supplied by the source. A model is
only marked installed after all files and its tensor schema validate.

## Privacy and limits

- Accessibility is tried first. Clipboard fallback sends Copy to the originating
  app, snapshots materializable clipboard formats, and restores them when no newer
  write is detected. It declines promised files and snapshots over 64 MB.
- Clipboard operations are not atomic. Concurrent clipboard writers and delayed
  Copy handlers cannot be perfectly identified. Clipboard-history apps may see
  text copied during fallback. Disable fallback if that is unsuitable.
- Protected fields, inaccessible canvas text, and apps that suppress Copy cannot
  be read reliably. Use Read Clipboard as an explicit alternative.
- The bundled phonemizer supports English US/UK. Clearly non-English selections
  are rejected; mixed-language detection is imperfect. The upstream model's
  broader language list does not imply Alto supports those pipelines.
- Readings are limited to 100,000 characters. Text is chunked, with adaptive
  splitting for phoneme limits. There is no transcript history. Temporary audio
  is deleted as it is queued; the native worker releases idle models after a minute.
- Sleep/session deactivation pauses reading. An audio configuration change stops
  it, requiring a new selection. Voice cloning, OCR, seek/scrubbing, audio export,
  and automatic app/model updates are not included.

Installed assets live in `~/Library/Application Support/Alto/Models/`. Normal
reading never invokes a model download. Model imports/downloads use Hugging Face
HTTPS endpoints; there is no telemetry or remote speech fallback.

## Verification

```sh
swift test
```

Unit tests use a private named pasteboard and synthetic model files. They do not
touch the user's clipboard or download models. Test actual bundled inference:

```sh
dist/Alto.app/Contents/MacOS/Alto --integration-test /private/tmp/alto-integration
```

This explicitly downloads both curated models into the supplied test directory,
inspects a Hugging Face repository, verifies installation, generates WAV samples,
and imports a local model. It is **silent by default**. It writes measurements
and leaves its test artifacts for inspection.
Rerun with `--offline` to use installed test models without any Hub calls.

Speaker playback and audible coordinator checks are skipped unless you explicitly
add `--audible-playback`. That flag sends test speech to the current output device;
only use it when audible testing is wanted. Skipped checks are reported as skipped.
Normal launches never automatically read a demo passage.

See [docs/verification.md](verification.md) for completed checks and manual
checks still requiring Accessibility access. The implementation plan is in
[docs/implementation-plan.md](implementation-plan.md).

## Runtime extension

`AltoCore` owns model metadata/validation, downloads, selection, chunking, playback,
and the `SpeechEngine` protocol. `AltoUI` owns the coordinator and SwiftUI views.
`AltoSpeechWorker` is a persistent native process with JSON requests over stdin and
atomic PCM-file responses. It contains failures in third-party model loaders and
can be terminated when generation is cancelled.

A new model family needs a validator, a worker adapter and protocol dispatch,
capability metadata, catalog entries, and real offline integration fixtures.
Current family routing intentionally accepts only `kokoro-v1`; downloaded files
cannot register executable plugins. Models, voices, and playback stay separate.

Dependency and model notices are bundled in
[Resources/THIRD_PARTY_NOTICES.md](../Resources/THIRD_PARTY_NOTICES.md).
