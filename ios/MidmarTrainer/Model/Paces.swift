import Foundation

struct TimeTrial: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: String
    var dist: Int
    var secs: Int
    /// "manual" or "watch"
    var source = "manual"
    var workoutID: String?
}

enum Paces {
    /// Seconds per 100 m at threshold, from one timed swim. Longer swims are slower per 100 m,
    /// so the time is scaled to a 1500 m effort.
    static func threshold(_ t: TimeTrial) -> Double {
        Double(t.secs) / Double(t.dist) * 100 * pow(1500 / Double(t.dist), 0.07)
    }

    static func pace(_ zone: Zone, thr: Double?) -> Double? {
        guard let thr else { return nil }
        return thr * zone.factor
    }

    /// A sensible pace for estimates when there is no timed swim yet.
    private static func estPace(_ zone: Zone, thr: Double?) -> Double { (thr ?? 170) * zone.factor }

    /// Predicted Midmar Mile time range in seconds. Open water is slower than the pool, hence the spread.
    static func raceRange(thr: Double?) -> (lo: Double, hi: Double)? {
        guard let thr else { return nil }
        let lo = thr * pow(1600.0 / 1500.0, 0.07) * 16
        return (lo, lo * 1.08)
    }

    /// Estimated session duration in seconds, including rests and short changeovers.
    static func estimate(_ s: Session, thr: Double?) -> Double {
        if s.isRace { return estPace(.thr, thr: thr) * pow(1600.0 / 1500.0, 0.07) * 16 * 1.04 }
        var t = 0.0
        for (i, st) in s.steps.enumerated() {
            t += Double(st.reps * st.dist) / 100 * estPace(st.zone, thr: thr) + Double((st.reps - 1) * st.rest)
            if i + 1 < s.steps.count {
                let next = s.steps[i + 1]
                t += Double(next.kind == st.kind && st.rest > 0 ? st.rest : 30)
            }
        }
        return t
    }

    /// Target time for one rep of a step, or nil for best-effort steps or with no timed swim.
    static func target(_ st: SetStep, thr: Double?) -> Double? {
        guard st.zone != .max, let p = pace(st.zone, thr: thr) else { return nil }
        return p * Double(st.dist) / 100
    }
}
