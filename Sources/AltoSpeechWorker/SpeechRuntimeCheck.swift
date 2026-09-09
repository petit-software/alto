import Foundation
import MLX

enum SpeechRuntimeCheck {
    // Kokoro-shaped transposed convolutions with an exact analytical answer.
    // The old NAX kernel passes short shapes but corrupts the longer ones.
    static func run() -> Bool {
        var passed = true
        for length in [1000, 8000, 9000, 15840] {
            let input = MLXArray.ones([1, length, 384])
            let weight = MLXArray.ones([192, 8, 384])
            let output = MLX.convTransposed1d(input, weight, stride: 4)
            let values = output.asArray(Float.self)
            let outputLength = (length - 1) * 4 + 8
            var mismatches = 0
            var maxError: Float = 0
            for (index, value) in values.enumerated() {
                let frame = index / 192
                let expected: Float = (frame < 4 || frame >= outputLength - 4) ? 384 : 768
                let error = abs(value - expected)
                if !value.isFinite || error > 0.1 { mismatches += 1 }
                maxError = max(maxError, error)
            }
            let valid = values.count == outputLength * 192 && mismatches == 0
            passed = passed && valid
            print("\(valid ? "PASS" : "FAIL") ConvTransposed1d T=\(length): \(mismatches)/\(values.count) incorrect samples, max error \(maxError)")
            fflush(stdout)
        }
        return passed
    }
}
