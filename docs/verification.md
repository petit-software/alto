# MVP verification

**Radio-noise update:** the generation defect is now reproduced and fixed.
See [audio-noise-investigation.md](audio-noise-investigation.md) for exact
before/after measurements and the new native regression command. All 24 speech
fixtures, four convolution lengths, 13 unit tests, and prior offline playback checks
pass. User listening confirmation on the previously failing passage remains.

Tested on 2026-09-09 with macOS 26.6.2, Xcode 26.6 / Swift 6.3.3, Apple M5 Max,
64 GB unified memory. The deployment target is macOS 15 / Apple Silicon; an M1
and the minimum OS have not been tested on physical hardware.

## Completed

### Chrome capture and pill lifecycle

- 18 silent unit tests pass, including failed capture without a player, cancelled
  capture ignoring late text, and delayed/cancelled Copy restoring an isolated
  named pasteboard. These do not establish live Chrome behavior.
- Empty AX range strings now fall through to Copy; intermediate empty clipboard
  states are allowed to finish. Copy events target the original PID.
- Chrome's on-demand Accessibility activation follows
  [Chromium's documentation](https://www.chromium.org/developers/design-documents/accessibility/).
- Pill presentation requires validated reading state. Play/pause and X remain;
  voice/speed are in Settings. X unloads the worker and cancels capture/generation.
- Live Chrome capture and user playback acceptance remain pending. No audio was
  played during this change.

### Unified Settings window

- Deleted the old `MainView.swift` sidebar, its navigation types, and the separate
  NSWindow construction path. The floating player is the only separate app panel.
- General/Models/Reading/About now share the native Settings scene. Models retains
  download/import/switch/delete controls; Reading includes an initially empty
  manual-text editor. Setup and menu/player links route to Settings tabs.
- 14 unit tests pass, including setup-tab routing. Release signature verifies;
  app and DMG rebuilt. The running Models pane was visually checked, and the
  diagnostic Reading route opened a native window titled Reading. Full interactive
  and appearance acceptance remains manual. No audible tests were run.

### Cleanup and silent verification

- Removed unused settings icons/imports/error state and the embedded Settings
  route; moved Settings to its own file and shared Stop/Dismiss behavior.
- Fixed shortcut recording remaining active after a Settings tab change.
- Added coordinator tests for disabled-shortcut editing/conflicts/persistence,
  explicit dismissal versus internal stop, and main-window destinations.
- Current `swift test`: 13 tests pass. The rebuilt release passes all 24 speech
  fixtures and four exact convolution checks, with network access denied.
- The rebuilt integration command passes silent synthesis checks and explicitly
  reports speaker/coordinator playback as skipped. No audible tests were run
  for this final verification. Startup demo playback code has been removed.
- Release app signature verifies and the DMG is rebuilt. General Settings was
  visually checked after extraction. Full menu/tab interactions and light/dark
  coverage remain manual: this automation process lacks Accessibility permission.

- Release Xcode build and standalone `dist/Alto.app`; embedded framework/worker
  signatures pass `codesign --verify --deep --strict` with local ad-hoc signing.
- `dist/Alto-0.1.0.dmg` built successfully (approximately 25 MB); `hdiutil verify`
  reports a valid image checksum. Fresh bundle assembly prevents stale resources
  from invalidating the code-signing seal.
- Nine offline unit tests: long-text tail/Unicode preservation, empty/unbroken
  chunking, rich-text/image/multi-item and empty clipboard restoration,
  intervening clipboard writes, safetensors header/shape/offset checks, corrupt
  checksums, path traversal/symlink rejection, and selection limits.
- Real model downloads through the app's `URLSession` implementation, including
  an interrupted download that remained uninstalled and then resumed successfully.
- Required file sizes and available SHA-256 checksums validated before atomic
  installation. Both curated models subsequently synthesized real PCM audio.
- Compatible local-folder import copies a complete model into its own installation;
  installed metadata survives creating a new model manager.
- Hugging Face inspection resolves the pinned repository and discovers 28 English
  voice files. Full Hub import, installation and synthesis passed using that model.
- AVAudioEngine playback at 2×, pause before playback, resume to completion, and
  immediate queue flushing on Stop.
- Coordinator pause during generation, reading replacement, completion after the
  playback queue drains, and cancellation without stale work restarting playback.
- Release app copied to `/private/tmp/alto-offline-check/Alto.app`, then both
  curated models synthesized and played with network access denied and file reads
  of the repository's `build` and `.build` directories denied. No external Python
  or model cache was needed.
- Final packaged build repeated that restricted offline check at
  `/private/tmp/alto-final-offline/Alto.app`, including the separately imported Hub
  model and coordinator cancellation/replacement tests; all passed.
- Running Models window and floating player inspected visually. The player uses
  Clio's capsule proportions, tinted glass, hairline and shadows; it displays real
  reading state, voice selection, speed, pause and stop.

## Model artifacts

| Entry | Pinned weight source | Required download bytes | Voices |
| --- | --- | ---: | --- |
| Kokoro | `mlx-community/Kokoro-82M-bf16` at `a71e4d38b236d968966a2002c4c895dbd12b1c3c` | 329,207,319 | Heart, Michael, Emma, George |
| Kokoro Compact | `erildo/Kokoro-82M-fp16-Swift` at `1232dd6943839fc037378b8e5312600fe75ce29c` | 164,498,253 | Same voices from the first pinned source |

Despite the first repository's name, the inspected standard weights contain F32
tensors. The compact weights use different names and omit the unused ALBERT
pooler. Alto normalizes the names, expands them to F32 in the worker, and fills
the unused pooler with zero tensors. It does not claim lower inference memory.

Full license texts ship with the app; downloaded model cards and source/revision
metadata remain with each installation. UI memory guidance is labeled as an
estimate or as a measurement on this specific Mac.

## Performance observations

Short Release integration samples, not a standardized benchmark:

| Model | First request in one run | Subsequent request | Audio generated by subsequent request | Short-sample worker peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Kokoro | 2.35 s | 0.42 s | 5.0 s | ~497 MB |
| Kokoro Compact | 0.53 s | 0.17 s | 5.0 s | ~670 MB |

First-request latency varied with OS/Metal caches (roughly 0.5–2.9 seconds in
observed runs). The compact sample ran after the standard sample and should not
be interpreted as a fair cold-start comparison. Peak RSS was measured in separate
short worker invocations using `/usr/bin/time -l`; the compact measurement includes
weight preparation. Longer passages can require more memory.

## Worker memory growth — 2026-09-11

Activity Monitor showed the persistent worker at 49 GB after ordinary reading.
MLX's Metal allocator keeps every freed buffer in a pool whose limit defaults to
the device memory limit (about 62 GB on this 64 GB Mac) and only reuses a pooled
buffer of nearly the same size. Each chunk has its own tensor shapes, so the pool
almost never hit and grew by roughly 3–5 GB per chunk. Active model memory stayed
at 310 MB throughout; the rest was pool.

Measured with an opt-in worker log (`ALTO_MEMORY_LOG=1` on stderr) over the same
16 varied chunks:

| Worker configuration | Physical footprint after 16 chunks | Per-chunk generation |
| --- | ---: | ---: |
| Unbounded pool (before) | 50.4 GB | 0.4–2.0 s |
| 256 MB pool, cleared after each request (now) | 0.8–1.7 GB | 0.4–1.4 s |

Bounding the pool cost no measurable time. `--audio-regression` now records the
worker's physical footprint per fixture and fails if it exceeds 4 GB, so the
regression is caught silently. The fixed run stayed between 569 MB and 1.26 GB
across all 24 fixtures.

Warm short-text synthesis is comfortably faster than real time on this test Mac.
The plan's M1 latency target, precise shortcut-to-player latency and stop latency
have not been measured. No equivalent M1 performance claim is made.

## Still requires manual verification

The automation process was denied Accessibility access by macOS (`osascript is
not allowed assistive access`). The app exposes permission onboarding, but this
does not constitute a verified permission grant or cross-app selection test.

- Grant Alto Accessibility, then select and read in TextEdit, Safari, Preview,
  an Electron app, and a terminal. Confirm the source stays focused.
- Exercise the registered global shortcut, shortcut conflicts, and re-granting
  Accessibility after an ad-hoc rebuild.
- Exercise real Copy handlers, delayed Copy, clipboard-history apps and concurrent
  writers. Unit tests prove restoration decisions; macOS offers no atomic clipboard
  transaction or reliable copy-writer identity.
- VoiceOver/keyboard traversal of player controls and popovers, full-screen Spaces,
  multi-display movement, Reduce Motion/Transparency, and display disconnection.
- Sleep/lock, permission revocation and real audio-output device changes.
- Model deletion/recovery through Trash, low-disk conditions, relaunch during a
  partial transfer, and offline first launch on a separate clean Mac.
- Listen to a broader quality corpus: dialogue, dates, decimal numbers, URLs,
  abbreviations, long paragraphs, mixed-language selections, and playback speeds.
  Existing checks establish valid generated audio and working playback, not a
  comprehensive pronunciation or listening-quality assessment.

### Listen with Alto service — 2026-09-13

Verified silently on the installed copy: the Info.plist `NSServices` entry is
present with the app version intact, `pbs -dump` lists “Listen with Alto” with
`public.rtf` and `public.utf8-plain-text` send types, and `NSPerformService`
from a separate process delivered a whitespace-only pasteboard to the running
app (return value true, general clipboard change count unchanged). Unit tests
cover the clutter classifier on a flattened whole-page selection, prose
pass-through, guardrail fallback, list and footnote survival, a real RTF
pasteboard round trip with links and an attachment, and the service handoff
into `AppModel`. No speech was produced.

Still manual:

- Right-click selected text in Safari, Chrome, TextEdit, Notes, Mail, Preview
  and Slack; confirm the Services submenu shows the item, note which hosts send
  RTF versus plain text only, and which show no Services submenu at all.
- Select all on the Sentiers example page in Safari and Chrome, choose the
  service, and compare the developer preview with the article body.
- Invoke the service while Alto is not running and while it is mid reading.
- Listen to the cleaned page once for heading pauses and dropped content.

Signing/notarization for public distribution remains separate. The delivered app
is a local MVP build, not a notarized public release.

## Reproduce

```sh
swift test
./scripts/build-app.sh Release
dist/Alto.app/Contents/MacOS/Alto --integration-test /private/tmp/alto-integration
```

Integration explicitly downloads models and generates samples, silently by
default. It never reads the user's selection or clipboard. It leaves WAV files
and JSON measurements in the test directory. Reuse it with `--offline` after setup.
Speaker playback and coordinator playback checks require the additional
`--audible-playback` flag and explicit user approval before an agent runs them.
Without that flag they are reported as skipped, not passed. `--audio-regression`
always checks generated audio numerically without playing it.

To verify a relocated app without network or development resources:

```sh
ditto dist/Alto.app /private/tmp/alto-offline-check/Alto.app
/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*) (deny file-read* (subpath "/Users/bigb/Repo/alto/build") (subpath "/Users/bigb/Repo/alto/.build"))' \
  /private/tmp/alto-offline-check/Alto.app/Contents/MacOS/Alto \
  --integration-test /private/tmp/alto-integration --offline
```

Adjust the two denied build paths for another checkout. `sandbox-exec` here is a
developer verification tool; normal app operation does not require it.

## Follow-up verification — 2026-09-09

- Clio-style native menu implemented without History or Updates; status icon is the template SF Symbol `play.circle`.
- Settings uses a native SwiftUI Settings scene with General/Reading/About toolbar tabs and Clio's code-native icons. Running General pane captured and visually inspected; full light/dark and interaction checks remain manual.
- `swift test`: 10 passing tests, including hotkey conflict, release, and re-registration coverage. Actual shortcut event delivery after toggling remains a manual check.
- Release rebuild and bundled offline integration passed for standard, compact, and imported Kokoro models, including playback, pause/resume, 2× speed, stop, and coordinator cancellation/replacement.
- Initial investigation, superseded by the noise report linked above: short generated samples and offline pitch rendering had near-silent starts. Live playback checks verified completion, not subjective absence of noise. Longer samples subsequently exposed the MLX numerical defect.
- Read-only device inspection showed Bluetooth selected for both input/output, mono 24 kHz output. This suggests headset mode as a possible contributor; it is not proof. [Apple documents reduced Bluetooth playback quality while its microphone is used](https://support.apple.com/en-us/102217). Alto contains no microphone-capture path. No global audio settings were changed.
