# Alto implementation checklist

Updated: 2026-09-13. Radio-noise cause reproduced and fixed in the worker; 24 speech fixtures and exact kernel checks pass. User listening confirmation remains. Detailed architecture and original milestones: [implementation plan](../docs/implementation-plan.md). Test evidence and manual limitations: [verification](../docs/verification.md).

## Listen with Alto service — 2026-09-13

- [x] Add an `NSServices` entry (generated `Support/Info.plist` via `project.yml`), a `ServiceProvider` set as `NSApp.servicesProvider`, and `AppModel.readService` that reads the private service pasteboard through the existing reading path. The general clipboard is never written.
- [x] Add `PageText`: plain-text block classification (navigation runs, menu phrases, dates, read times, captions, cookie and legal text), heading preservation, duplicate removal, a fallback guardrail, and RTF link density with attachment removal.
- [x] Add Settings → Reading → Skip page clutter (default on) governing the service, Read Clipboard and Paste; the shortcut path is unchanged.
- [x] Register the bundle in `install-app.sh` with `lsregister` and `pbs -update`. Installed copy verified: plist entry, `pbs -dump` listing, and an `NSPerformService` round trip with whitespace text. 36 silent tests pass.
- [ ] Right-click in Safari, Chrome, TextEdit, Notes, Mail, Preview and Slack; record which hosts show the item and send RTF. Listen once to the cleaned example page.

## Follow reading — 2026-09-13

- [x] Track per-buffer playback progress in `AudioPlayback` from the player node's sample clock (holds while paused, resets on stop, exact hand-off between queued buffers).
- [x] Add `ReadingFollow`: locate chunks in the preview text and snap a progress fraction to a word. Unit-tested at start, whitespace, middle and end positions.
- [x] Add a Follow reading switch to the developer preview; tint the passage, highlight the word, auto-scroll the paragraph. Setting persists; highlight clears on stop or completion.
- [ ] Listen once with the preview visible to judge how far the estimated word leads or trails actual speech at 1× and 2×.

## Worker memory and Models page

- [x] Trace the 49 GB `AltoSpeechWorker` footprint to MLX's unbounded Metal buffer pool: per-chunk tensor shapes defeat reuse, so freed buffers accumulate to the device limit while active model memory stays at 310 MB.
- [x] Cap the pool at 256 MB and empty it after each request. Same 16-chunk probe: 50.4 GB → under 1.7 GB, no measurable generation slowdown. Float32/TF32 safeguards untouched.
- [x] Record worker physical footprint per fixture in `--audio-regression`; fail above 4 GB. Fixed run: 569 MB–1.26 GB across 24 fixtures, all audio checks still pass.
- [x] Rebuild Models settings as a grouped form matching Clio's Model tab: radio selection, glyph controls with hover help, selected-model details, Import and On-disk sections. Removed the custom search field and All/Installed filter.
- [ ] Visually confirm the installed Models page in light and dark appearance and the Activity Monitor figure during a long reading; layout compiled and installed but not screenshotted here.

## Priority: radio-noise acceptance

- [x] Reproduce corruption in longer raw Kokoro output, independently of playback/Bluetooth.
- [x] Confirm MLX 0.30.2 NAX convolution overflow on M5 using exact expected results.
- [x] Disable the faulty path inside the worker and enforce Float32 weights/voices, without trimming or filtering speech.
- [x] Pass offline regression coverage: four voices × three lengths × two models, plus exact convolution size-boundary tests.
- [ ] Confirm the previously failing passage sounds clean to the user, including its beginning and chunk boundaries.

See [noise investigation](../docs/audio-noise-investigation.md) for measurements and repeatable commands.

## Accessibility recovery

- [x] Trace the shortcut error to `AXIsProcessTrusted()`: macOS denies the running copy access before capture/synthesis.
- [x] Replace script-built ad-hoc signatures with an available Apple Development identity; propagate manual signing/team to dependencies. Retain an explicit ad-hoc fallback with a warning.
  - Release build verifies with a certificate-backed designated requirement, no longer a per-build cdhash. 14 unit tests and silent offline integration synthesis pass. No speaker playback performed.
- [x] Add stale-entry recovery instructions and “Show This Copy of Alto in Finder” to General Settings; document manual Read Clipboard as an alternative.
- [ ] User grants the new signed copy Accessibility access, then verifies selection reading. Permission-dependent end-to-end behavior is not yet confirmed; Alto cannot grant itself access.

## Chrome selection and player lifecycle

- [x] Shorten the repository README and preserve detailed usage/model/build information in `docs/guide.md` for the GitHub handoff.
- [x] Replace the Models search field's rounded native bezel with an appearance-driven surface: dark fill in dark mode, white in light mode, semantic text/icons and outline. Preserve model filtering and add Clear search.
- [x] Make the editor follow system light/dark appearance: semantic canvas, text, caret and outline colors, no forced light scheme. Set editor Paste and X to 13pt at default scale. No screen sampling or Screen Recording permission added.
- [x] Apply native glass to the complete pill (foreground included), rather than an empty background shape, enabling regular Liquid Glass's adaptive vibrant text/symbols over changing backgrounds. Keep semantic foreground styles, opaque Reduce Transparency fallback and a contrast-protecting tint on older macOS. Explain Clear glass's weaker contrast protection in Settings.
- [ ] Visually verify the installed native foreground adaptation over light/dark/mixed moving backgrounds in light mode; layout tests alone do not establish composited contrast.
- [x] Inspect Clio's position/feedback controls and surface code; add Hidden, six edge positions and Near cursor plus segmented size, translucency and Clear glass to Reading → Player Appearance. Persist choices, use Clio's 64pt visible-edge spacing, clamp to the active display and keep near-cursor anchored during reading. Share the glass capsule between standalone/editor players; keep the editor placement fixed. No Clio files changed.
  - 29 silent tests pass, including negative-coordinate displays, edge placement, cursor clamping, saved appearance settings and Hidden preserving active work.
- [ ] Visually check all positions, glass levels, Clear glass, multiple displays and Reduce Transparency on the installed app. Do not infer surface quality from offscreen layout tests.
- [x] Increase the editor pill's Paste and X symbols to 17pt at default scale, keeping their matching gray/bold styling and scaled control frames.
- [x] Match editor Paste to X: secondary gray, 10pt bold symbol and 28pt control frame, scaled consistently with player size.
- [x] Give the editor pill untinted native Liquid Glass on macOS 26, removing the opaque fill/tint that obscured the content beneath. Use ultra-thin material on older systems and a solid Reduce Transparency fallback; keep Paste / Play / X and no added border.
- [x] Order editor pill controls Paste / Play / X and remove the editor X button's circular background. Preserve external floating player styling.
- [x] Record mandatory rebuild → install to `/Applications/Alto.app` → relaunch → process verification after every batch of app changes. Add `scripts/install-app.sh` with graceful quit, signature verification, preserved previous bundle and no automatic audio.
- [x] Move Paste beside Play inside the editor-only pill. Overlay the pill at the bottom of the text canvas instead of reserving a footer; add scroll-end clearance so final lines can be brought above it. External floating player has no Paste button.
- [x] Clean tags/emojis as text is pasted into the editor (native Paste, plain/rich Paste, and bottom-right Paste button), without modifying the clipboard. Remove the top toolbar/X; retain the player's X and keyboard close. 27 silent tests pass, including insertion at the caret, whitespace boundaries, read-only behavior and unchanged clipboard contents.
- [x] Skip HTML/XML tags/comments and emoji grapheme clusters before language detection/chunking for selection, clipboard and editor reading. Preserve enclosed text, ordinary digits/punctuation and the editor's source draft. Preview reflects filtered speech text; tags/emoji-only input reports no readable text. 26 silent tests pass, including flags/skin tones/joined emoji/keycaps, quoted tag attributes and empty output.
- [x] Remove the explicit pill border and reading/passage status column only inside the editor; keep play/pause and X. Floating player presentation remains unchanged.
  - 23 silent tests pass, including compact embedded layout at all three sizes.
- [x] Use `square.on.square` for Paste and auto-hide the reader's scroll indicator when content fits. 22 silent tests pass, including short → overflowing → short content with legacy scroll bars.
- [x] Restyle Read Text as a borderless pure-white canvas: no traffic lights/title/boxed input, 32pt corners, 0.5pt outline, 17pt system San Francisco text. Toolbar X stops/closes; opposite Paste uses the editor's native paste action. Preserve embedded player, keyboard focus, Command-W and Escape close.
- [x] Move menu “Read Text…” to a dedicated native rounded paste window. Reuse the pill at its bottom, including idle Play, pause/resume and X; suppress the floating player while the window is open. Window close and X stop/cancel reading and clear the in-memory draft. Keep validation errors inside the reader and replace Settings' duplicate editor with an Open Read Text button.
  - 21 silent tests pass, including reader open/reopen, inline errors and idempotent close/clear lifecycle. Release app rebuilt with verified signing.
- [ ] Manually verify paste-window playback, pause/resume, native close and X with a real model. No audible test performed for this change.
- [x] Add a scrollable developer preview above the pill showing the validated captured text, preserving its internal line breaks. It scales with the pill, stays in memory only, and clears on stop/completion; voice changes preview the remaining passages to be read.
  - 20 silent tests pass, including bounded preview layout for short and long text at all three player sizes.
- [x] Visually verify the developer preview with a real Chrome selection; no live reading or audible test performed for this change.
- [x] Remove the dotted drag handle; add persisted Default / 1.25× / 1.5× player size in Settings → Reading. Scale layout, text and hit areas together; resize an active panel around its horizontal center and clamp it to the display.
  - 19 silent tests pass, including layout dimensions at all three sizes, preference reload/invalid-value fallback, and no idle player presentation. Live multi-display resizing remains a manual check.
- [x] Skip empty AX range results so they reach clipboard fallback. Request Chrome's on-demand Accessibility tree; send fallback Copy to the original process, without showing a player before capture.
- [x] Wait through intermediate empty clipboard states; cancellation still allows clipboard restoration before returning. Regression tests use isolated named pasteboards, not the user's clipboard.
- [x] Show the pill only for a validated reading, never idle/capturing/model validation. Keep play/pause and X; voice/speed remain in Settings. Capture/setup errors use existing Settings instead of a player.
- [x] X cancels capture and generation, clears playback, unloads the worker and dismisses; late capture results cannot restart reading. 18 silent unit tests pass, including capture failure, cancellation and delayed clipboard restoration.
- [ ] Verify the reported Chrome selection in the rebuilt app, including play/pause and X during loading/playback. No live reading or audible acceptance claimed.

## Next: Clio-style native interface

- [x] Remove the old sidebar window entirely and consolidate every screen into native Settings.
  - General contains permissions/setup; Models contains browsing, download/import, switching and deletion; Reading contains voices/speed, clipboard fallback and manual text; About contains notices/storage access.
  - Models, Read Text, Finish Setup, first launch and player error actions now use the same Settings scene. Deleted `MainView.swift` and the AppDelegate's separate NSWindow creation path.
  - Added setup routing coverage; 14 unit tests pass. No automatic reading or audible verification.
  - Rebuilt app/DMG, verified signature, and checked the native Models pane on screen. The new build is running; no model files or user settings were deleted.
- [x] Review the code, remove duplicates and unused code and comments.
  - Removed four unused settings icons, obsolete comments/imports, and unused model-store error state.
  - Separated Settings into its own file; removed its unreachable embedded-window route; shared sidebar styling and Stop/Dismiss behavior.
  - Finish Setup opens the reading/setup page. Switching Settings tabs cancels shortcut recording.
  - Added three coordinator/navigation tests (13 total). Rechecked the General pane visually. Full manual interaction checks remain below.
- [x] Make verification silent by default and remove launch-time demo playback code.
  - Audible integration checks require `--audible-playback` and explicit user approval. Silent runs report those checks as skipped.
  - Recorded project verification rules in `AGENTS.md`; retained the numerical audio regressions and worker safeguards.
  - Final rebuilt app: 13 unit tests, 24 speech fixtures, four kernel checks, and silent offline synthesis pass. Audible checks are explicitly skipped. App signature verified; DMG rebuilt.
- [x] Make app settings look native like Clio, using the same icons where the actions match. Keep descriptions brief.
  - Inspect Clio's settings components before adapting Alto-owned code; leave the Clio checkout unchanged.
  - Native Settings scene with General, Reading, and About toolbar tabs; Clio's icon paths/renderer reused with attribution. General layout visually checked in the running app.
- [x] Replicate Clio's system-bar menu for Alto; omit History and Check for Updates.
  - Use its compact app-name/shortcut header, shortcut enable switch, native menu grouping, keyboard equivalents, and version footer.
  - Adapt actions to reading: read selection/clipboard, playback controls, player, voice/model access, Settings, and Quit.
  - Ensure toggling the shortcut releases/re-registers it correctly and preserves conflict reporting.
- [ ] Manually verify all menu actions, shortcut delivery after toggling, voice selection, and light/dark appearance. Settings' General layout has been checked; the full interaction/appearance matrix remains.
- [x] Use Apple's SF Symbol `play.circle` for the system-bar icon; replaced 2026-09-13 by the speech-bubble SVG glyph rendered as a template image.
- [x] Test shortcut registration, conflict handling, release, and re-enable; rebuild the app. All 10 unit tests pass.

## Earlier static investigation (superseded by confirmed cause above)

- [x] Inspect generated WAV beginnings and render the playback graph offline at 1× and 2×.
  - Short samples had near-silent leading audio. Longer samples later reproduced the defect; short-only testing was insufficient.
- [x] Reproduce the noise in raw generation on longer passages. Live listening acceptance remains above.
  - Live integration playback completes successfully. System inspection reports Bluetooth as both default input/output, with mono 24 kHz output. Headset mode is a hypothesis, not a confirmed cause. Alto has no microphone capture code. Do not change global audio settings or other apps without user direction.
  - Bluetooth was an early hypothesis, not the confirmed cause. The numerical defect reproduces without any playback device.
- [x] Compare playback with generated audio and identify the faulty generation path.
- [x] Fix the confirmed cause without clipping initial consonants or masking the problem with arbitrary trimming.
- [ ] Listen-test cold/warm playback, repeated reads, pause/resume, stop/restart, speed changes, and both model variants. Record results and any unresolved limitations.

## Implemented MVP baseline

- [x] Native menu-bar app and Clio-based floating player with playback, speed, and voice controls.
- [x] Configurable global shortcut, Accessibility selection capture, and clipboard-preserving fallback.
- [x] Bundled native Kokoro worker, chunked generation, cancellation, and bounded playback queue.
- [x] Two verified Kokoro model variants, model metadata, download progress, switching, deletion, and local/Hugging Face import.
- [x] Model validation and explanations for unsupported formats; runtime boundary for future model families.
- [x] Unit tests, real-model integration checks, and standalone offline verification with development directories blocked.
- [x] Build/run documentation, standalone app assembly, and DMG packaging.

## Remaining acceptance and release checks

- [ ] Manually verify selected-text reading and source focus in TextEdit, Safari, Preview, Electron, terminal, and full-screen apps with Accessibility enabled.
- [ ] Exercise permission revocation, secure fields, delayed Copy, and concurrent clipboard writers; document unsupported cases.
- [ ] Verify player keyboard/VoiceOver access, accessibility appearance settings, multiple displays, and sleep/output-device changes.
- [ ] Measure performance on an M1-class device before claiming that baseline; current measurements are on the development Mac.
- [ ] Sign and notarize for public distribution with owner approval. Local script builds now use Apple Development signing when available; this is not a notarized public release.

English US/UK is currently supported end to end. Additional languages and model families are future work, not verified MVP capabilities.
