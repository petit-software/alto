# Alto third-party notices

Alto's floating player adapts the capsule surface, dimensions, shadows and panel
behavior of Clio, supplied by the project owner at `../clio`. Alto also adapts
Clio's native menu header/switch and settings layout, and reuses its settings
icon paths and SVG path renderer in Alto-owned sources.

The speech runtime is bundled native Swift and C++ code. No Python interpreter
or external inference service is used. Full dependency license texts are in the
Notices directory alongside this file.

| Component | Version/revision | License |
| --- | --- | --- |
| KokoroSwift — mlalma/kokoro-ios | 4d6d1d8ff8cd012014180c9cd4cf0151e7682354 | MIT |
| MisakiSwift | 1.0.6 | Apache-2.0 (see included text) |
| MLX Swift and MLX | 0.30.2 | MIT |
| MLXUtilsLibrary | 0.0.6 | Apache-2.0 |
| Swift Numerics | 1.1.1 | Apache-2.0 with Runtime Library Exception |
| ZIPFoundation | 0.9.20 | MIT |

Model files download separately. Kokoro-82M by hexgrad and the curated MLX/Swift
conversions declare Apache-2.0 on their model cards. Original source cards and
pinned revisions are retained in each installation's `alto-model.json`; model
cards are included with downloads. All four bundled catalog voices originate
from the Kokoro-82M conversion, including the compact model's voice files.

Sources:

- https://github.com/mlalma/kokoro-ios
- https://github.com/mlalma/MisakiSwift
- https://github.com/ml-explore/mlx-swift
- https://github.com/mlalma/MLXUtilsLibrary
- https://github.com/apple/swift-numerics
- https://github.com/weichsel/ZIPFoundation
- https://huggingface.co/hexgrad/Kokoro-82M
- https://huggingface.co/mlx-community/Kokoro-82M-bf16
- https://huggingface.co/erildo/Kokoro-82M-fp16-Swift

The compact conversion uses different tensor names and omits ALBERT's unused
pooled output. Alto normalizes names in its worker, expands weights to Float32,
and supplies a zero pooler (the TTS path uses only sequence output). Therefore
the compact model reduces download size, not inference memory.
