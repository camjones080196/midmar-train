import Foundation

/// Calendar-day helpers. Plan dates are whole local days, keyed as "yyyy-MM-dd".
enum Days {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard let d = calendar.date(from: c), Days.key(d) == key else { return nil }
        return d
    }

    static func isKey(_ s: String) -> Bool { date(s) != nil }

    static func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func today(_ now: Date = Date()) -> Date { start(now) }
    static func add(_ date: Date, _ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: start(date))! }
    static func between(_ a: Date, _ b: Date) -> Int { calendar.dateComponents([.day], from: start(a), to: start(b)).day ?? 0 }
    /// 0 = Sunday ... 6 = Saturday
    static func weekday(_ date: Date) -> Int { calendar.component(.weekday, from: date) - 1 }
    static func monday(of date: Date) -> Date { add(date, -((weekday(date) + 6) % 7)) }
    static func weeksBetween(_ a: Date, _ b: Date) -> Int { Int(floor(Double(between(a, b)) / 7)) }

    static let dow = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func dayNumber(_ date: Date) -> Int { calendar.component(.day, from: date) }
    /// "16 Nov"
    static func short(_ date: Date) -> String { "\(dayNumber(date)) \(mon[calendar.component(.month, from: date) - 1])" }
    /// "Mon 16 Nov"
    static func withWeekday(_ date: Date) -> String { "\(dow[weekday(date)]) \(short(date))" }
    /// "16 Nov 2026"
    static func withYear(_ date: Date) -> String { "\(short(date)) \(calendar.component(.year, from: date))" }
}
