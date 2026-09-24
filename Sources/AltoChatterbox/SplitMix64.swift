// Adapted from FluidAudio (Apache-2.0); see Resources/Notices/FluidAudio.txt.
import Foundation

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextUniform() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

extension SplitMix64 {
    /// Standard normal via Box–Muller.
    mutating func nextGaussian() -> Float {
        let u1 = max(nextUniform(), 1e-12)
        let u2 = nextUniform()
        return Float((-2.0 * Foundation.log(u1)).squareRoot() * Foundation.cos(2.0 * .pi * u2))
    }
}
