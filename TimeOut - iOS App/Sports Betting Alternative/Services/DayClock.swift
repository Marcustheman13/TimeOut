import Foundation

/// Local-calendar day keys ("yyyy-MM-dd"). Everything in the app resets at local midnight.
nonisolated enum DayClock {
    static func key(for date: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func key(_ key: String, offsetBy days: Int, calendar: Calendar = .current) -> String {
        guard let date = date(for: key, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return self.key(for: shifted, calendar: calendar)
    }

    static func date(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func nextMidnight(after date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
    }
}
