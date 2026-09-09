# Alto

A native macOS menu-bar app that reads text aloud with local Kokoro AI voices.
Works offline after downloading a model—no account, Python, or cloud speech service.

## Use

Requires **Apple Silicon and macOS 15+**. Liquid Glass is available on macOS 26.

1. Open Alto and download a voice model in **Settings → Models**.
2. Enable Alto in **System Settings → Privacy & Security → Accessibility**.
3. Select English text in a supported app and press **Option–Space**.
   The shortcut is configurable.

Or choose **Read Text…** from the menu to paste into the editor. The glass player
provides play/pause and X to stop. Adjust voice, speed, player position, size,
and glass appearance in Settings.

- Kokoro (~329 MB) and Kokoro Compact (~164 MB).
- Compatible Kokoro v1 safetensors imports from local files or public Hugging Face repositories.
- Chunked audio generation, download progress, and offline playback.
- Tags and emojis skipped; pasted text cleaned in the editor.
- Light/dark editor, no saved reading history, and no telemetry.

English US/UK only for now. Accessibility capture uses a clipboard-preserving
fallback where needed; clipboard-history apps may retain the temporary copy.
Other model families and formats aren't supported yet.

## Build and run

Use full Xcode with its Metal toolchain and Swift 6.2 or newer.

```sh
./scripts/install-app.sh
```

This builds, installs to `/Applications/Alto.app`, and launches Alto.
For a bundle only, run `./scripts/build-app.sh`; output is `dist/Alto.app`.

Builds use an available Apple Development certificate, otherwise ad-hoc signing.
Ad-hoc rebuilds may require Accessibility re-approval. Local builds are **not notarized**.

Run silent tests with `swift test`.

## More

[Usage, model formats, and build details](docs/guide.md) ·
[Verification and limitations](docs/verification.md) ·
[Implementation plan](docs/implementation-plan.md) ·
[Third-party notices](Resources/THIRD_PARTY_NOTICES.md)

Player design adapted from [Clio](https://github.com/petit-software/clio).
