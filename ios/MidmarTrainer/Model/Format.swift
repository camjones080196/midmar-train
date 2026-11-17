import Foundation

enum Fmt {
    /// 1600 -> "1 600" (non-breaking space as the thousands separator)
    static func num(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    /// 800 -> "800 m", 1250 -> "1.25 km", 2000 -> "2 km"
    static func dist(_ metres: Int) -> String {
        guard metres >= 1000 else { return "\(num(metres)) m" }
        let km = (Double(metres) / 10).rounded() / 100
        var s = String(format: "%.2f", km)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return "\(s) km"
    }

    /// 95 -> "1:35", 3725 -> "1:02:05"
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = s % 3600 / 60, x = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
    }

    /// 1930 -> "32 min", 4000 -> "1 h 07"
    static func minutes(_ seconds: Double) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        return m < 60 ? "\(m) min" : String(format: "%d h %02d", m / 60, m % 60)
    }

    /// "2:10" -> 130, "1:02:05" -> 3725. Nil when it is not minutes and seconds.
    static func parseTime(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let n = parts.compactMap { Int($0) }
        guard n.count == parts.count, n.last! < 60 else { return nil }
        if n.count == 3 { guard n[1] < 60 else { return nil }; return n[0] * 3600 + n[1] * 60 + n[2] }
        return n[0] * 60 + n[1]
    }
}
