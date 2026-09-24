# Alto

A native macOS menu-bar app that reads text aloud with local AI voices.
Works offline after downloading a model. No account, Python, or cloud speech service.

Requires **Apple Silicon and macOS 15+**. English US/UK only for now.

## Use

Open Alto and download a voice model in **Settings → Models**. Then read text
in any of three ways:

- **Right-click → Services → Listen with Alto.** Works in any app with a
  Services menu and needs no permissions. Tick it once in System Settings →
  Keyboard → Keyboard Shortcuts → Services. Whole-page selections are cleaned
  of navigation, captions, forms and footers before reading.
- **Select text and press Option–Space.** Needs Alto enabled in
  **System Settings → Privacy & Security → Accessibility**. The shortcut is
  configurable.
- **Read Text… or Read Clipboard** from the menu-bar icon. Paste or use what
  you copied.

The floating glass player has play/pause and X to stop. Voice, speed, player
position, size and glass appearance live in Settings.

Models: Kokoro (~329 MB), Kokoro Compact (~164 MB), and
[Chatterbox Nano](docs/chatterbox-nano.md) (~746 MB, beta, one English voice), plus compatible Kokoro v1
safetensors imported from local files or public Hugging Face repositories.
Markup and emojis are skipped. No reading history, no telemetry.

## Build

Use full Xcode with its Metal toolchain and Swift 6.2 or newer.

```sh
./scripts/install-app.sh   # build, install to /Applications, launch (removes dist/Alto.app)
./scripts/build-app.sh     # bundle only, in dist/Alto.app
swift test                 # silent unit tests
```

Builds sign with an available Apple Development certificate, otherwise ad-hoc,
which may require re-approving Accessibility after a rebuild. Local builds are
**not notarized**.

## More

[Guide: usage, models, formats, build](docs/guide.md) ·
[Verification and limitations](docs/verification.md) ·
[Implementation plan](docs/implementation-plan.md) ·
[Services plan](docs/listen-with-alto-service-plan.md) ·
[Third-party notices](Resources/THIRD_PARTY_NOTICES.md)

Player design adapted from [Clio](https://github.com/petit-software/clio).
