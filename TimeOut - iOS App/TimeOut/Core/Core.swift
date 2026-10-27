import Foundation

/// Milliseconds since 1970, like JavaScript's Date.now(). The whole app works in these so the
/// simulated feed, seeded hashes and day math match the web demo exactly.
typealias Ms = Double

/// TimeOut core helpers: demo clock, day keys, seeded randomness, odds math and formatting.
/// A port of the web demo's core.js; keep the two in step.
enum TO {
    static func now() -> Ms { (Date().timeIntervalSince1970 * 1000).rounded(.down) }

    static let MIN: Ms = 60_000
    static let HOUR: Ms = 60 * MIN
    static let DAY: Ms = 24 * HOUR

    private static var calendar: Calendar { Calendar.current }

    static func date(_ ts: Ms) -> Date { Date(timeIntervalSince1970: ts / 1000) }
    static func ms(_ date: Date) -> Ms { (date.timeIntervalSince1970 * 1000).rounded(.down) }

    // MARK: Days

    static func dayKey(_ ts: Ms = now()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date(ts))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parts(_ key: String) -> (Int, Int, Int) {
        let p = key.split(separator: "-").map { Int($0) ?? 0 }
        return (p.count > 0 ? p[0] : 1970, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }

    static func localDate(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        // DateComponents normalizes overflowing days (d + n) the same way JS Date does.
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour
        return calendar.date(from: c) ?? Date()
    }

    static func dayStart(_ key: String) -> Ms {
        let (y, m, d) = parts(key)
        return ms(localDate(y, m, d))
    }

    static func addDays(_ key: String, _ n: Int) -> String {
        let (y, m, d) = parts(key)
        guard let shifted = calendar.date(byAdding: .day, value: n, to: localDate(y, m, d, hour: 12)) else { return key }
        return dayKey(ms(shifted))
    }

    static func nextMidnight(_ ts: Ms = now()) -> Ms {
        let start = calendar.startOfDay(for: date(ts))
        return ms(calendar.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    static func weekKey(_ ts: Ms = now()) -> String {
        let d = date(ts)
        let weekday = calendar.component(.weekday, from: d) // Sunday = 1
        let mondayOffset = (weekday + 5) % 7 // Monday = 0
        let start = calendar.startOfDay(for: d)
        let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: start) ?? start
        return dayKey(ms(monday) + 12 * HOUR)
    }

    // MARK: Hashing / seeded randomness (bit-for-bit the same as the web demo)

    static func hash(_ str: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for unit in str.utf16 {
            h ^= UInt32(unit)
            h = h &* 0x01000193
        }
        return h
    }

    /// Stable value in [-1, 1] for a string.
    static func unit(_ str: String) -> Double { Double(hash(str) % 20001) / 10000 - 1 }
    /// Stable value in [0, 1).
    static func u01(_ str: String) -> Double { Double(hash(str) % 100_000) / 100_000 }

    /// mulberry32, seeded from a string.
    final class RNG {
        private var a: UInt32
        init(_ seed: String) { a = TO.hash(seed) }
        init(seed: UInt32) { a = seed }
        func next() -> Double {
            a = a &+ 0x6d2b79f5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
        func callAsFunction() -> Double { next() }
    }

    static func shuffle<T>(_ arr: [T], _ rand: RNG) -> [T] {
        var a = arr
        var i = a.count - 1
        while i > 0 {
            let j = Int((rand() * Double(i + 1)).rounded(.down))
            a.swapAt(i, j)
            i -= 1
        }
        return a
    }

    static func uid(_ prefix: String = "id") -> String {
        let time = String(UInt64(now()), radix: 36)
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let rand = String((0..<5).map { _ in chars[Int.random(in: 0..<chars.count)] })
        return "\(prefix)_\(time)\(rand)"
    }

    /// Password hashing for the offline demo only (accounts live on this device; this is not real security).
    static func pwHash(_ password: String, _ salt: String) -> String {
        var h1: UInt32 = 0xdeadbeef ^ 7
        var h2: UInt32 = 0x41c6ce57 ^ 7
        for ch in "\(salt):\(password):timeout".utf16 {
            h1 = (h1 ^ UInt32(ch)) &* 2_654_435_761
            h2 = (h2 ^ UInt32(ch)) &* 1_597_334_677
        }
        h1 = ((h1 ^ (h1 >> 16)) &* 2_246_822_507) ^ ((h2 ^ (h2 >> 13)) &* 3_266_489_909)
        h2 = ((h2 ^ (h2 >> 16)) &* 2_246_822_507) ^ ((h1 ^ (h1 >> 13)) &* 3_266_489_909)
        return String(format: "%08x%08x", h2, h1)
    }

    // MARK: Math

    /// Standard normal CDF (Abramowitz–Stegun erf approximation).
    static func phi(_ x: Double) -> Double {
        let z = abs(x) / 2.0.squareRoot()
        let t = 1 / (1 + 0.3275911 * z)
        let y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-z * z)
        return 0.5 * (1 + (x >= 0 ? y : -y))
    }

    /// Rounds down to the nearest hook (x.5) so lines never land on a whole number.
    static func hook(_ x: Double) -> Double { x.rounded(.down) + 0.5 }
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
}

/// JavaScript's Math.round: halves round up (toward +∞), unlike Swift's .rounded().
@inline(__always) func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
@inline(__always) func jsRoundInt(_ x: Double) -> Int { Int(jsRound(x)) }

// MARK: - Odds

enum OddsMath {
    static func decimal(_ american: Int) -> Double {
        american > 0 ? 1 + Double(american) / 100 : 1 + 100 / Double(abs(american))
    }

    static func fromDecimal(_ dec: Double) -> Int {
        if dec <= 1 { return -10000 }
        return dec >= 2 ? jsRoundInt((dec - 1) * 100) : jsRoundInt(-100 / (dec - 1))
    }

    /// Fair (no house edge) American price, rounded to sportsbook-looking steps.
    static func fromProb(_ raw: Double) -> Int {
        let p = TO.clamp(raw, 0.038, 0.962)
        let val = p >= 0.5 ? (-100 * p) / (1 - p) : (100 * (1 - p)) / p
        let step: Double = abs(val) >= 300 ? 25 : 5
        var r = jsRoundInt(val / step) * Int(step)
        if r > -100 && r < 100 { r = r < 0 ? -100 : 100 }
        return r
    }

    static func fmt(_ price: Int) -> String { price > 0 ? "+\(price)" : "\(price)" }

    static func fmtLine(_ line: Double, signed: Bool = true) -> String {
        let body = line == line.rounded() ? String(Int(line)) : String(format: "%.1f", line)
        if !signed { return body }
        return line > 0 ? "+\(body)" : body
    }
}

// MARK: - Formatting

enum Fmt {
    static func signedMin(_ n: Int) -> String { n > 0 ? "+\(n) min" : n < 0 ? "−\(abs(n)) min" : "0 min" }
    static func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : n < 0 ? "−\(abs(n))" : "0" }

    static func countdown(_ ms: Ms) -> String {
        let s = max(0, Int((ms / 1000).rounded(.down)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()
    private static let longDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    static func time(_ ts: Ms) -> String { timeFormatter.string(from: TO.date(ts)) }
    static func date(_ ts: Ms) -> String { dateFormatter.string(from: TO.date(ts)) }
    static func weekday(_ ts: Ms) -> String { weekdayFormatter.string(from: TO.date(ts)) }

    static func day(_ ts: Ms) -> String {
        let key = TO.dayKey(ts)
        let today = TO.dayKey()
        if key == today { return "Today" }
        if key == TO.addDays(today, 1) { return "Tomorrow" }
        if key == TO.addDays(today, -1) { return "Yesterday" }
        return longDayFormatter.string(from: TO.date(ts))
    }

    /// "under a minute", "12 min", "2 hr 5 min".
    static func inTime(_ ms: Ms) -> String {
        let m = max(0, jsRoundInt(ms / TO.MIN))
        if m < 1 { return "under a minute" }
        if m < 60 { return "\(m) min" }
        let h = m / 60
        return "\(h) hr\(m % 60 != 0 ? " \(m % 60) min" : "")"
    }

    static func ago(_ ts: Ms) -> String {
        let m = jsRoundInt((TO.now() - ts) / TO.MIN)
        if m < 1 { return "just now" }
        if m < 60 { return "\(m) min ago" }
        let h = jsRoundInt(Double(m) / 60)
        if h < 24 { return "\(h) hr ago" }
        return day(ts)
    }

    static func plural(_ n: Int, _ word: String, _ plural: String? = nil) -> String {
        "\(n) \(n == 1 ? word : plural ?? word + "s")"
    }

    static func ordinal(_ n: Int) -> String {
        let s = ["th", "st", "nd", "rd"]
        let v = n % 100
        let idx = (v - 20) % 10
        if idx >= 1 && idx <= 3 { return "\(n)\(s[idx])" }
        if v >= 1 && v <= 3 { return "\(n)\(s[v])" }
        return "\(n)th"
    }

    /// The multiplier as "×1.1" / "×1.25".
    static func mult(_ m: Double) -> String {
        if m == m.rounded() { return "×\(Int(m))" }
        var s = String(format: "%.2f", m)
        if s.hasSuffix("0") { s.removeLast() }
        return "×\(s)"
    }
}

/// A coded error with a user-facing message and optional field errors, like the web demo's AppError.
struct AppError: Error, LocalizedError {
    var code: String
    var message: String
    var fields: [String: String] = [:]
    var status: Int? = nil
    var changed: [String] = []
    var errorDescription: String? { message }
}
