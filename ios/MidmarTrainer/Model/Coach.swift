import Foundation

/// Reviews recent training and decides whether next week's plan should change.
/// It never touches this week, the taper or race week, and only one change is pending at a time:
/// the one for next week, which is re-decided as new swims come in until that week starts.
enum Coach {
    struct Signals: Equatable {
        var due = 0
        var done = 0
        var gapDays = 0
        var recentFeel: [Int] = []
        var bestNonStop = 0
        var completion: Double { due == 0 ? 1 : Double(done) / Double(due) }
    }

    /// The full list of plan changes after reviewing up to `today`.
    static func review(state: TrainerState, today: Date) -> [Rebase] {
        let first = PlanEngine.build(state.config, rebases: state.adapt)
        guard today >= first.begin else { return state.adapt }
        let current = first.weekIndex(of: today)
        let target = current + 1
        var kept = state.adapt.filter { $0.week < target }
        guard target < first.buildWeeks else { return kept }

        let base = PlanEngine.build(state.config, rebases: kept)
        let sessions = SessionResolver.effective(plan: base, state: state)
        let signals = gather(plan: base, sessions: sessions, state: state, today: today)
        if var change = decide(plan: base, current: current, target: target, signals: signals) {
            if let old = state.adapt.first(where: { $0.week == target }), old.long == change.long, old.scale == change.scale, old.reason == change.reason {
                change.date = old.date
            } else {
                change.date = Days.key(today)
            }
            kept.append(change)
        }
        return kept
    }

    static func gather(plan: Plan, sessions: [Session], state: TrainerState, today: Date) -> Signals {
        var s = Signals()
        let from = Days.add(today, -13)
        let window = sessions.filter { !$0.isRace && $0.at <= today && $0.at >= max(from, plan.begin) }
        s.due = window.count
        s.done = window.filter { state.done[$0.key] != nil }.count
        let lastDone = state.done.values.compactMap { Days.date($0.date) }.filter { $0 <= today }.max()
        s.gapDays = Days.between(lastDone ?? plan.begin, today)
        s.recentFeel = state.done.values.filter { $0.feel > 0 }.sorted { $0.date > $1.date }.prefix(3).map(\.feel)
        let cutoff = Days.key(Days.add(today, -21))
        s.bestNonStop = state.nonstop.filter { $0.date >= cutoff }.map(\.metres).max() ?? 0
        return s
    }

    static func decide(plan: Plan, current: Int, target: Int, signals s: Signals) -> Rebase? {
        let planned = Double(plan.weeks[target].buildLong)
        let now = Double(plan.weeks[current].buildLong)
        let established = Days.between(plan.begin, Days.add(plan.weekStart(current), 6)) >= 10
        func r(_ x: Double) -> Int { max(100, Int((x / 25).rounded()) * 25) }
        func change(_ long: Double, _ scale: Double, _ reason: String) -> Rebase? {
            let l = r(min(long, Double(plan.peak)))
            guard abs(Double(l) - planned) >= max(50, planned * 0.05) || scale != 1 else { return nil }
            return Rebase(week: target, long: l, scale: scale, reason: reason, date: "")
        }

        if established && s.gapDays >= 14 {
            return change(max(200, min(now, planned) * 0.7), 0.85,
                          "It's been \(s.gapDays) days since your last swim, so the next weeks ease back in.")
        }
        if established && s.due >= 2 && s.completion < 0.5 {
            return change(min(now, planned), 1,
                          "Most swims in the last two weeks were missed, so next week repeats this week's long swim instead of building.")
        }
        if s.recentFeel.filter({ $0 >= 4 }).count >= 2 {
            return change(planned * 0.9, 0.9, "Your last swims felt hard, so next week eases off by about 10%.")
        }
        if s.bestNonStop >= 200, Double(s.bestNonStop) >= planned * 1.1 {
            return change(Double(s.bestNonStop), 1,
                          "Your \(Fmt.num(s.bestNonStop)) m non-stop swim is ahead of the plan, so the long swim builds from there.")
        }
        if established, s.recentFeel.count >= 3, s.recentFeel.allSatisfy({ $0 <= 2 }), s.completion >= 0.8 {
            return change(planned * 1.08, 1, "Your swims have felt easy, so the plan builds a little faster.")
        }
        return nil
    }
}
