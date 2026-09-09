# Radio-noise defect — 2026-09-09

## Confirmed cause and fix

On the development M5 Max, MLX 0.30.2's NAX accelerated matrix kernel returns
incorrect results for sufficiently long transposed convolutions. Kokoro uses
these to turn features into audio. The resulting WAV already contains noise;
neither playback nor Bluetooth is required to reproduce it.

This matches the [upstream NAX overflow fix](https://github.com/ml-explore/mlx/pull/3092)
and [Kokoro report](https://github.com/mlalma/kokoro-ios/pull/29). Corrupted
samples can be finite with peaks below 1, so the earlier checks passed.

Alto now sets `MLX_ENABLE_TF32=0` in the worker environment before launch and
again before the worker uses MLX. Model weights and voice embeddings are
converted to Float32 where necessary. With this pinned runtime, that bypasses
the faulty NAX path and retains ordinary GPU inference. No silence trimming,
attenuation, noise gate, or audio filter is applied. Other apps are unaffected.

An MLX 0.30.6 upgrade was investigated, but both Kokoro and Misaki 1.0.6 pin
0.30.2. The Kokoro PR alone cannot resolve that dependency graph. Attempted
dependency changes were reverted; no new fork is shipped. A coordinated
runtime upgrade must pass these checks before removing the safeguard.

## Before/after evidence

Exact tests use all-one inputs `[1, T, 384]` and weights `[192, 8, 384]`, stride 4.
The expected output is analytically 384 at the edges and 768 in the interior.

| Check | Faulty accelerated path | Fixed full-precision path |
| --- | --- | --- |
| Convolution T=1,000 | 0 incorrect values | 0 incorrect values |
| Convolution T=8,000 | 0 incorrect values | 0 incorrect values |
| Convolution T=9,000 | 626,688 / 6,912,768 incorrect | 0 incorrect values |
| Convolution T=15,840 | 5,879,808 / 12,165,888 incorrect | 0 incorrect values |
| Heart, 207 characters: first 200 ms RMS | 0.03338 | 0.000000114 |

The 207-character fixture fits the normal 220-character chunk size. The short
32-character fixture passed before the fix, explaining why short-only tests
were inadequate. The fixed bundle passes all 24 combinations of four voices,
three lengths (32, 207, 388 characters), and two model variants. These phrases
start with silence; the opening-RMS threshold is a fixture-specific regression,
not a filter or a rule applied to arbitrary user speech.

Tests passed with network access denied. Existing playback/coordinator checks
also passed: pause/resume, 2× speed, stop, replacement, and cancellation.
Human listening on the user's previously failing passage remains the final
acceptance check; this environment cannot listen to recordings directly.

## Repeatable native checks

Reuse an isolated test directory with both models already installed through
`--integration-test` (see [verification](verification.md)):

```sh
./scripts/build-app.sh
sandbox-exec -p '(version 1) (allow default) (deny network*)' \
  dist/Alto.app/Contents/MacOS/Alto --audio-regression /private/tmp/alto-transfer-check
```

This saves WAV fixtures and JSON measurements in a new `audio-regression-UUID`
subdirectory. It does not download, play sound, capture text, or use the clipboard.

To demonstrate the old kernel defect on affected hardware:

```sh
dist/Alto.app/Contents/Helpers/AltoSpeechWorker --check-convolution-unsafe
dist/Alto.app/Contents/Helpers/AltoSpeechWorker --check-convolution
```

The unsafe mode computes test tensors only and exits; it never generates or
plays speech. On the tested M5 the first command fails, the second passes.
On older hardware without NAX, both may pass.

The optional `scripts/diagnose-speech.mjs` developer tool accepts a bundle,
installed model folder, and new output folder for before/after comparisons.
Only that optional tool requires Node. The app and native regression command
require neither Node nor Python.
