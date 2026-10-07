import Foundation

nonisolated enum Stats {
    /// Standard normal CDF.
    static func phi(_ x: Double) -> Double {
        0.5 * erfc(-x / 2.squareRoot())
    }

    /// Rounds to the nearest "hook" (x.5) at or below `x` so lines never land on a whole number.
    static func hook(_ x: Double) -> Double {
        x.rounded(.down) + 0.5
    }
}

/// Deterministic hashing and randomness so odds and simulated games are stable across launches.
nonisolated enum Seeded {
    /// FNV-1a — Swift's `hashValue` is randomized per launch, so it can't be used here.
    static func hash(_ string: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }

    /// Uniform value in [-1, 1] derived from a string.
    static func unit(_ string: String) -> Double {
        Double(hash(string) % 20_001) / 10_000 - 1
    }
}

nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
