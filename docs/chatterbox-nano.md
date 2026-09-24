# Chatterbox Nano

Settings → Models offers **Chatterbox Nano** as an optional 746 MB download.
Select it after downloading; Reading shows its single **Default · English**
voice. Speed, pause/resume, selection reading, Services and Read Text use the
same playback pipeline as Kokoro. Voice cloning is not included.

This is the beta Core ML conversion of ResembleAI's 110M English model from
[FluidInference](https://huggingface.co/FluidInference/chatterbox-nano-coreml).
It runs locally on Apple Silicon / macOS 15+, without Python or an account.
Model assets are pinned to `6eb3640c4f441139ccba33f1cf0998924dbd6718`.
Every downloaded file has a size and SHA-256 check; installation is atomic,
downloads can be paused/resumed, and deletion uses Alto's usual Trash action.
The worker loads only the selected installation, with no network/cache fallback.

The standard Core ML output bucket allows roughly 9.9 seconds per call after
reserving the reference voice and silence tokens. Alto initially splits text
at 140 characters, then halves and retries a passage if either the BPE input
budget or generated-audio budget is exceeded. It does not truncate the tail.
Native tags such as `[laugh]` and `[chuckle]` are understood by Nano; arbitrary
long text may split across tag boundaries. Ordinary narration is the primary use.

## Runtime provenance

`Sources/AltoChatterbox` adapts a narrow subset of
[FluidAudio](https://github.com/FluidInference/FluidAudio/tree/5c51c5c93afff0d89594a2a93c3103e790ba648c/Sources/FluidAudio/TTS/Chatterbox)
at revision `5c51c5c93afff0d89594a2a93c3103e790ba648c` (Apache-2.0).
The original license ships in `Resources/Notices/FluidAudio.txt`.

Adapted files: Nano constants, GPT-2 tokenizer, synthesizer, table reader,
Core ML stride/state helpers, errors, shared Float16 conversion, and SplitMix64
(from NeuTtsSynthesizer plus ChatterboxSynthesizer's Gaussian extension).
Unneeded multilingual helpers and logging were removed. Alto supplies a local,
verified loader in `ChatterboxNanoRuntime.swift` instead of the SDK's downloader
and global cache. This avoids adding its unrelated speech recognition runtimes
or changing Alto's pinned MLX/Kokoro dependency graph.

The synthesizer preserves upstream sampling order, seed 42, strided Float16
output handling, voice conditioning, standard bucket sizes and trim fade.
Core ML uses CPU/GPU. Kokoro's worker-local TF32 disable, Float32 conversion and
256 MB MLX cache cap remain intact. Only one speech model stays loaded at once.
The upstream Python Perth watermark postprocessor is not included in this
Core ML runtime.

## Verification

Unit coverage checks the pinned catalog, reload, tokenizer bounds, default
voice routing, audio budget, and padded Core ML output strides.
`--integration-test` downloads/tests all catalog models in an isolated directory,
including Nano short speech and a long passage with automatic limit retries.
`--audio-regression` retains the 24 Kokoro fixtures and exact convolution checks.
Both commands are silent unless integration is explicitly given
`--audible-playback`. Numerical checks do not establish listening quality.
