import Foundation

struct DoneRecord: Codable, Hashable {
    enum Source: String, Codable { case manual, health }

    /// The day it was swum or ticked, "yyyy-MM-dd"
    var date: String
    var feel = 0
    var time = 0
    var source = Source.manual
    var workoutID: String?
    var distance: Int?

    init(date: String, feel: Int = 0, time: Int = 0, source: Source = .manual, workoutID: String? = nil, distance: Int? = nil) {
        self.date = date; self.feel = feel; self.time = time; self.source = source; self.workoutID = workoutID; self.distance = distance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        feel = try c.decodeIfPresent(Int.self, forKey: .feel) ?? 0
        time = try c.decodeIfPresent(Int.self, forKey: .time) ?? 0
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .manual
        workoutID = try c.decodeIfPresent(String.self, forKey: .workoutID)
        distance = try c.decodeIfPresent(Int.self, forKey: .distance)
    }
}

struct NonStopSwim: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: String
    var metres: Int
    var openWater = false
    var workoutID: String?
}

/// Everything the app saves. Plans are rebuilt from `config`; this holds what the swimmer did.
struct TrainerState: Codable {
    var config = PlanConfig()
    var done: [String: DoneRecord] = [:]
    var skipped: Set<String> = []
    /// session key -> day key it was moved to
    var moved: [String: String] = [:]
    /// session key -> edited sets
    var edits: [String: [SetStep]] = [:]
    var trials: [TimeTrial] = []
    var nonstop: [NonStopSwim] = []
    /// Health workout id -> session key
    var links: [String: String] = [:]
    /// Health workouts the swimmer chose not to count
    var ignored: Set<String> = []
    /// Changes the coach made to the plan, by the week they start
    var adapt: [Rebase] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        config = try c.decodeIfPresent(PlanConfig.self, forKey: .config) ?? PlanConfig()
        done = try c.decodeIfPresent([String: DoneRecord].self, forKey: .done) ?? [:]
        skipped = try c.decodeIfPresent(Set<String>.self, forKey: .skipped) ?? []
        moved = try c.decodeIfPresent([String: String].self, forKey: .moved) ?? [:]
        edits = try c.decodeIfPresent([String: [SetStep]].self, forKey: .edits) ?? [:]
        trials = try c.decodeIfPresent([TimeTrial].self, forKey: .trials) ?? []
        nonstop = try c.decodeIfPresent([NonStopSwim].self, forKey: .nonstop) ?? []
        links = try c.decodeIfPresent([String: String].self, forKey: .links) ?? [:]
        ignored = try c.decodeIfPresent(Set<String>.self, forKey: .ignored) ?? []
        adapt = try c.decodeIfPresent([Rebase].self, forKey: .adapt) ?? []
    }

    /// True once the swimmer has changed anything, which freezes the plan's start date.
    var hasActivity: Bool {
        config.setup || !done.isEmpty || !skipped.isEmpty || !moved.isEmpty || !edits.isEmpty
    }

    var latestTrial: TimeTrial? { trials.max { ($0.date, $0.secs) < ($1.date, $1.secs) } }
    var threshold: Double? { latestTrial.map(Paces.threshold) }
    var bestNonStop: Int { nonstop.map(\.metres).max() ?? 0 }
}

enum SessionResolver {
    /// Applies the swimmer's edits and moves to the planned sessions, sorted by the day they are on.
    static func effective(plan: Plan, state: TrainerState) -> [Session] {
        var out = plan.sessions.map { planned -> Session in
            var s = planned
            if !s.isRace, let e = state.edits[s.key], e.contains(where: { $0.kind == .main }) {
                s.steps = e
                s.edited = true
                let singles = e.filter { $0.kind == .main && $0.reps == 1 && $0.zone != .max }.map(\.dist)
                s.cont = planned.cont != nil ? singles.max() : nil
                s.tt = planned.tt != nil ? e.first { $0.zone == .max }?.dist : nil
                s.ladder = nil
            }
            return s
        }
        var occupied = Set(out.map(\.key))
        for i in out.indices {
            let s = out[i]
            guard !s.isRace, let target = state.moved[s.key], target != s.key, let d = Days.date(target),
                  d >= plan.begin, d < plan.race, !occupied.contains(target) else { continue }
            occupied.remove(s.key)
            occupied.insert(target)
            out[i].at = d
        }
        return out.sorted { $0.at < $1.at }
    }
}
