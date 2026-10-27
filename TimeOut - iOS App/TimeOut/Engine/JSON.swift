import Foundation

/// Loosely-typed JSON for ESPN payloads, with JavaScript-style optional chaining:
/// a missing key or wrong type reads as `.null` instead of failing.
enum JSON: Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(_ any: Any?) {
        switch any {
        case nil, is NSNull: self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSON($0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSON($0) })
        default: self = .null
        }
    }

    init(data: Data) {
        self = JSON((try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull())
    }

    subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case .array(let a) = self, index >= 0, index < a.count { return a[index] }
        return .null
    }

    var isNull: Bool { if case .null = self { return true }; return false }
    /// JavaScript truthiness.
    var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        default: return true
        }
    }

    var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    var isArray: Bool { if case .array = self { return true }; return false }
    var isObject: Bool { if case .object = self { return true }; return false }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// A non-empty string, like `value || ''` in JS.
    var text: String? { truthy ? string : nil }

    /// JavaScript `Number(value)`: nil when the result would be NaN.
    var number: Double? {
        switch self {
        case .number(let n): return n.isNaN ? nil : n
        case .bool(let b): return b ? 1 : 0
        case .null: return nil
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return 0 }
            return Double(t.hasPrefix("+") ? String(t.dropFirst()) : t)
        default: return nil
        }
    }

    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }

    /// `a ?? b` in JS: the first value that isn't null/undefined.
    static func ?? (lhs: JSON, rhs: @autoclosure () -> JSON) -> JSON { lhs.isNull ? rhs() : lhs }

    func find(_ test: (JSON) -> Bool) -> JSON { array.first(where: test) ?? .null }
}
