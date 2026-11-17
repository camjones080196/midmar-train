import Foundation

// MARK: - Plan types

struct SetStep: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: StepKind
    var reps: Int
    var dist: Int
    var zone: Zone
    var rest: Int = 0
    var label: String = ""

    var metres: Int { reps * dist }

    enum CodingKeys: String, CodingKey { case kind, reps, dist, zone, rest, label }

    init(_ kind: StepKind, _ reps: Int, _ dist: Int, _ zone: Zone, rest: Int = 0, label: String = "") {
        self.kind = kind; self.reps = reps; self.dist = dist; self.zone = zone; self.rest = rest; self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(StepKind.self, forKey: .kind)
        reps = try c.decode(Int.self, forKey: .reps)
        dist = try c.decode(Int.self, forKey: .dist)
        zone = try c.decode(Zone.self, forKey: .zone)
        rest = try c.decodeIfPresent(Int.self, forKey: .rest) ?? 0
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

struct Session: Identifiable, Hashable {
    /// The planned date as "yyyy-MM-dd". Stable across moves and edits.
    let key: String
    var id: String { key }
    let week: Int
    let date: Date
    /// The day it is actually on, after a move.
    var at: Date
    var type: SessionType
    var title: String
    var steps: [SetStep]
    let baseSteps: [SetStep]
    var note: String
    var cont: Int?
    var tt: Int?
    var ladder: [Int]?
    let openWater: Bool
    let isRace: Bool
    var edited = false

    var metres: Int { steps.reduce(0) { $0 + $1.metres } }
    var isMoved: Bool { Days.key(at) != key }
    /// The hardest, then longest, main set.
    var keyStep: SetStep? {
        steps.filter { $0.kind == .main || $0.kind == .race }
            .sorted { ($0.zone.level, $0.metres) > ($1.zone.level, $1.metres) }
            .first
    }
}

struct PlanWeek: Identifiable {
    let index: Int
    var id: Int { index }
    let phase: Int
    let focus: String
    let isRecovery: Bool
    let long: Int
    /// The long swim this week builds toward, before any recovery-week cut.
    let buildLong: Int
    let sessions: [Session]
    /// The coach's change that took effect this week, if any.
    let adjustment: Rebase?
    var metres: Int { sessions.reduce(0) { $0 + $1.metres } }
}

/// A change the coach made to the plan from one week on: the long swim restarts its build from
/// `long`, and the other sessions are scaled by `scale`.
struct Rebase: Codable, Hashable {
    var week: Int
    var long: Int
    var scale = 1.0
    var reason: String
    /// The day the change was made, "yyyy-MM-dd"
    var date: String
}

struct Phase: Hashable {
    let name: String
    let goal: String
    let range: String
}

struct Milestone: Hashable {
    let metres: Int
    let week: Int
}

struct Plan {
    let config: PlanConfig
    let start: Date
    let begin: Date
    let race: Date
    let weeks: [PlanWeek]
    let phases: [Phase]
    let milestones: [Milestone]
    let sessions: [Session]
    let startLong: Int
    let growth: Double
    /// The longest swim the last build week reaches.
    let finalLong: Int
    let rebases: [Rebase]

    var weekCount: Int { weeks.count }
    /// Weeks before the taper and race week.
    var buildWeeks: Int { max(0, weeks.count - 2) }

    /// Set when the plan can no longer reach the race distance in training.
    var warning: String? {
        guard finalLong < Catalog.raceDistance else { return nil }
        return "At this rate your longest swim before the race is \(Fmt.dist(finalLong)), short of the 1.6 km race. The plan builds as fast as is safe, so swimming the planned sessions is what closes the gap."
    }
    var pool: Int { config.pool }
    var peak: Int { config.peak }

    func weekStart(_ index: Int) -> Date { Days.add(start, index * 7) }
    func weekIndex(of date: Date) -> Int { min(weeks.count - 1, max(0, Days.weeksBetween(start, date))) }
}

struct PlanConfig: Codable, Equatable {
    var start = "2026-11-17"
    var race = "2027-02-13"
    var level = 200
    var perWeek = 3
    /// 0 = Sunday ... 6 = Saturday
    var days = [1, 3, 6]
    var pool = 25
    var peak = 2000
    var setup = false

    static let presets: [Int: [Int]] = [1: [6], 2: [3, 6], 3: [1, 3, 6], 4: [1, 2, 4, 6]]
    static let peaks = [1600, 2000, 2400]

    init() {}

    init(from decoder: Decoder) throws {
        let d = PlanConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? d.start
        race = try c.decodeIfPresent(String.self, forKey: .race) ?? d.race
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? d.level
        perWeek = try c.decodeIfPresent(Int.self, forKey: .perWeek) ?? d.perWeek
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? d.days
        pool = try c.decodeIfPresent(Int.self, forKey: .pool) ?? d.pool
        peak = try c.decodeIfPresent(Int.self, forKey: .peak) ?? d.peak
        setup = try c.decodeIfPresent(Bool.self, forKey: .setup) ?? d.setup
    }

    var startDate: Date? { Days.date(start) }
    var raceDate: Date? { Days.date(race) }

    /// Whole weeks from the Monday of the start week to race day.
    var raceWeeks: Int? {
        guard let s = startDate, let r = raceDate else { return nil }
        return Days.weeksBetween(Days.monday(of: s), r)
    }

    /// Plans run 6 to 40 weeks.
    var hasValidSpan: Bool {
        guard let w = raceWeeks, let s = startDate, let r = raceDate else { return false }
        return w >= 5 && w <= 39 && r > s
    }

    var startLong: Double { Double(min(peak, max(100, level >= 400 ? Int((Double(level) * 0.8).rounded()) : level))) }

    func normalized() -> PlanConfig {
        var o = self
        o.level = min(2400, max(0, level))
        if ![1, 2, 3, 4].contains(perWeek) { o.perWeek = 3 }
        var dd: [Int] = []
        for x in days where (0...6).contains(x) && !dd.contains(x) { dd.append(x) }
        o.days = dd.count == o.perWeek ? dd.sorted() : PlanConfig.presets[o.perWeek]!
        o.pool = pool == 50 ? 50 : 25
        if !PlanConfig.peaks.contains(peak) { o.peak = 2000 }
        if !o.hasValidSpan {
            let d = PlanConfig()
            o.start = d.start
            o.race = d.race
        }
        return o
    }

    /// One line describing the plan these settings would build.
    var preview: String? {
        guard hasValidSpan, let w = raceWeeks else { return nil }
        let n = w + 1, tn = n - 2, a0 = startLong
        let g = tn > 1 ? pow(Double(peak) / a0, 1 / Double(tn - 1)) - 1 : 0
        var s = "\(n) weeks. The long swim goes from \(Fmt.dist(Int(a0))) to \(Fmt.dist(peak)), about \(Int((g * 100).rounded()))% further each week."
        if g > 0.2 { s += " That is a steep build. An earlier start, or a shorter longest swim, makes it gentler." }
        return s
    }
}

// MARK: - Plan builder

enum PlanEngine {
    /// Every swim except race day is at least this long.
    static let minimumSession = 1000
    /// The long swim never grows faster than this from one week to the next.
    static let maxGrowth = 1.30

    private struct Draft {
        var type: SessionType
        var title: String
        var steps: [SetStep]
        var note = ""
        var cont: Int?
        var tt: Int?
        var ladder: [Int]?
        var ow = false
        var race = false
    }

    private struct DraftWeek {
        var phase: Int
        var focus: String
        var rec: Bool
        var long: Int
        var buildLong: Int
        var drafts: [Draft]
        var adjustment: Rebase?
    }

    private enum Quality: CaseIterable {
        case trial, build, descend, fartlek, threshold, brokenMile, negative, speed, pyramid, fastStart, racePace
    }
    private enum Skills { case technique, openWater, kickPull, breathing }

    /// The long swim for build week `t`, before any recovery-week cut, given the plan's start and
    /// any later changes. Each change restarts a steady climb toward the peak.
    static func ladder(_ t: Int, start a0: Double, peak: Int, buildWeeks tn: Int, rebases: [Rebase]) -> (value: Double, scale: Double, anchor: Rebase?) {
        var anchorWeek = 0, anchorLong = a0, scale = 1.0
        var anchor: Rebase?
        for r in rebases.sorted(by: { $0.week < $1.week }) where r.week > 0 && r.week < tn && r.week <= t {
            anchorWeek = r.week; anchorLong = Double(max(100, r.long)); scale = r.scale; anchor = r
        }
        let span = Double(tn - 1 - anchorWeek)
        var g = span > 0 && anchorLong < Double(peak) ? pow(Double(peak) / anchorLong, 1 / span) : 1
        g = min(max(g, 1), maxGrowth)
        let v = min(Double(peak), anchorLong * pow(g, Double(t - anchorWeek)))
        return (v, scale, anchor)
    }

    static func build(_ input: PlanConfig, rebases: [Rebase] = []) -> Plan {
        let cfg = input.normalized()
        let pool = cfg.pool, peak = cfg.peak
        let begin = cfg.startDate!, race = cfg.raceDate!
        let start = Days.monday(of: begin)
        let raceWeek = Days.weeksBetween(start, race)
        let weekCount = raceWeek + 1, tn = weekCount - 2
        let raceOff = Days.between(Days.add(start, raceWeek * 7), race)
        let offs = cfg.days.map { ($0 + 6) % 7 }.sorted()

        func stp(_ v: Double) -> Int { pool == 50 ? 50 : (v < 500 ? 25 : 50) }
        func rnd(_ x: Double, _ s: Int) -> Int { max(s, Int((x / Double(s)).rounded()) * s) }
        func rp(_ x: Double) -> Int { max(pool, Int((x / Double(pool)).rounded()) * pool) }
        func restFor(_ p: Double) -> Int { max(15, Int(((40 - 20 * p) / 5).rounded()) * 5) }
        func repDist(_ x: Double) -> Int {
            let d = x < 150 ? 50 : x < 300 ? 75 : x < 500 ? 100 : x < 1400 ? 200 : x < 1800 ? 300 : 400
            return max(pool, Int((Double(d) / Double(pool)).rounded(.up)) * pool)
        }
        func warm(_ a: Double) -> SetStep { SetStep(.wu, 1, a < 1000 ? 200 : 300, .easy) }
        func cool(_ a: Double) -> SetStep { SetStep(.cd, 1, a < 1000 ? 100 : 200, .easy) }
        func drill(_ t: Int) -> (name: String, how: String) { Catalog.drills[t % Catalog.drills.count] }
        func n(_ total: Double, _ d: Int, min lo: Int = 2, max hi: Int = 30) -> Int { min(hi, max(lo, Int((total / Double(d)).rounded()))) }

        /// Pads a session to the minimum with easy aerobic 100s before the cool down.
        func filled(_ d: Draft) -> Draft {
            var d = d
            guard !d.race else { return d }
            let total = d.steps.reduce(0) { $0 + $1.metres }
            guard total < minimumSession else { return d }
            let reps = Int((Double(minimumSession - total) / 100).rounded(.up))
            let i = d.steps.lastIndex { $0.kind == .cd } ?? d.steps.count
            d.steps.insert(SetStep(.main, reps, 100, .easy, rest: 15, label: "aerobic"), at: i)
            return d
        }

        // MARK: Sessions. `a` is the week's long swim, `p` progress through the plan, `s` the coach's scale.

        func technique(_ t: Int, _ a: Double, _ p: Double, _ s: Double) -> Draft {
            let dr = drill(t), d = repDist(a * 0.5)
            return Draft(type: .tech, title: "Technique", steps: [
                warm(a),
                SetStep(.drill, 6, 50, .easy, rest: 15, label: dr.name),
                SetStep(.main, n(min(900, 0.5 * a + 300) * s, d), d, .easy, rest: max(15, restFor(p) - 5), label: "long, smooth strokes"),
                SetStep(.main, 4, 50, .steady, rest: 15, label: "breathe every 3"),
                cool(a)
            ], note: "\(dr.name): \(dr.how) Then hold the same feel on the swims.")
        }
        func breathing(_ t: Int, _ a: Double, _ s: Double) -> Draft {
            Draft(type: .tech, title: "Breathing and rhythm", steps: [
                warm(a),
                SetStep(.drill, 4, 50, .easy, rest: 15, label: "6-kick switch"),
                SetStep(.main, n(400 * s, 100), 100, .easy, rest: 20, label: "breathe every 3, both sides"),
                SetStep(.main, n(300 * s, 50), 50, .steady, rest: 15, label: "long exhale underwater"),
                SetStep(.main, 1, rp(max(200, min(600, a * 0.4))), .easy, label: "continuous, relaxed rhythm"),
                cool(a)
            ], note: "Steady breathing is what lets you keep swimming. Breathe out slowly underwater so each breath in is easy.")
        }
        func openWaterSkills(_ a: Double, _ s: Double) -> Draft {
            Draft(type: .skills, title: "Open-water skills", steps: [
                warm(a),
                SetStep(.main, 6, 50, .steady, rest: 15, label: "sight forward every 6 strokes"),
                SetStep(.main, n(400 * s, 100), 100, .steady, rest: 20, label: "turn without touching the wall"),
                SetStep(.main, 4, 25, .fast, rest: 30, label: "start from treading water"),
                SetStep(.main, 1, rp(max(300, min(800, a * 0.5))), .steady, label: "sight every 8 strokes, no push-offs"),
                cool(a)
            ], note: "Midmar has no walls and no black line. Practise lifting your eyes to sight, turning without a push-off, and starting from treading water.")
        }
        func kickPull(_ a: Double, _ s: Double) -> Draft {
            Draft(type: .strength, title: "Kick and pull", steps: [
                warm(a),
                SetStep(.drill, n(400 * s, 100, min: 3, max: 8), 100, .steady, rest: 20, label: "pull with a buoy"),
                SetStep(.drill, n(300 * s, 50, min: 4, max: 8), 50, .easy, rest: 15, label: "kick with a board"),
                SetStep(.main, n(400 * s, 100, min: 3, max: 8), 100, .steady, rest: 20, label: "swim, strong catch"),
                cool(a)
            ], note: "A pull buoy builds your arms and catch; the kick set keeps your legs high, which matters in choppy water.")
        }
        func buildSet(_ a: Double, _ p: Double, _ s: Double) -> Draft {
            let d = repDist(a)
            return Draft(type: .build, title: "Build intervals", steps: [
                warm(a), SetStep(.main, n(min(1600, 1.2 * a + 300) * s, d), d, .steady, rest: restFor(p)), cool(a)
            ])
        }
        func descend(_ a: Double, _ s: Double) -> Draft {
            let rounds = a >= 800 ? 4 : 3
            return Draft(type: .build, title: "Descending set", steps: [
                warm(a),
                SetStep(.drill, 4, 50, .easy, rest: 15, label: "build each length"),
                SetStep(.main, Int((Double(rounds * 3) * s).rounded()), 100, .steady, rest: 15, label: "in rounds of 3, each 100 faster than the last"),
                cool(a)
            ], note: "Start each round easy and finish it strong. Learning to change pace is how you move through a crowd on race day.")
        }
        func fartlek(_ a: Double, _ s: Double) -> Draft {
            let d = a >= 600 ? 400 : 200
            return Draft(type: .build, title: "Fartlek", steps: [
                warm(a), SetStep(.main, n(min(1200, a + 200) * s, d), d, .steady, rest: 30, label: "every 4th length fast"), cool(a)
            ], note: "Surge for one length, then settle back into your steady rhythm without stopping.")
        }
        func threshold(_ a: Double, _ p: Double, _ s: Double) -> Draft {
            let d = repDist(a)
            return Draft(type: .thr, title: "Threshold reps", steps: [
                warm(a), SetStep(.drill, 4, 50, .steady, rest: 15, label: "build each length"),
                SetStep(.main, n(min(1600, 1.2 * a + 300) * s, d), d, .thr, rest: max(20, restFor(p))), cool(a)
            ])
        }
        func brokenMile(_ a: Double, _ p: Double, _ s: Double) -> Draft {
            let full = a >= 1000
            let reps = full ? 16 : 8
            return Draft(type: .thr, title: full ? "Broken mile" : "Half broken mile", steps: [
                warm(a), SetStep(.main, Int((Double(reps) * s).rounded()), 100, .thr, rest: p > 0.7 ? 10 : 15, label: "race pace"), cool(a)
            ], note: full ? "The whole race distance in 100s with short rests. Hold the same time on every rep; as the rests shrink, you are close to swimming it straight."
                         : "Half the race distance in 100s. Keep every rep the same speed.")
        }
        func negativeSplit(_ a: Double, _ s: Double) -> Draft {
            let d = a >= 900 ? 400 : 200
            return Draft(type: .thr, title: "Negative splits", steps: [
                warm(a), SetStep(.main, n(min(1200, a) * s, d, min: 2, max: 4), d, .steady, rest: 30, label: "second half faster than the first"),
                SetStep(.main, 4, 50, .fast, rest: 20), cool(a)
            ], note: "Start the Mile too fast and you pay for it at the end. These teach you to start controlled and finish strong.")
        }
        func speed(_ a: Double, _ s: Double) -> Draft {
            Draft(type: .speed, title: "Speed set", steps: [
                warm(a), SetStep(.drill, 4, pool, .steady, rest: 15, label: "build each length"),
                SetStep(.main, Int(Double(min(16, max(8, Int(((0.5 * a + 200) / 50).rounded())))) * s), 50, .fast, rest: 30),
                SetStep(.main, 1, 200, .easy, label: "loosen off"), cool(a)
            ])
        }
        func pyramid(_ a: Double) -> Draft {
            let ds = a >= 1400 ? [100, 200, 300, 400, 300, 200, 100] : [100, 200, 300, 200, 100]
            return Draft(type: .pyr, title: "Pyramid",
                         steps: [warm(a)] + ds.map { SetStep(.main, 1, $0, .steady, rest: 20) } + [cool(a)], ladder: ds)
        }
        func fastStart(_ a: Double, _ s: Double) -> Draft {
            Draft(type: .speed, title: "Fast-start practice", steps: [
                warm(a), SetStep(.main, Int(6 * s), 200, .steady, rest: 30, label: "first 50 fast, then settle"),
                SetStep(.main, 1, rp(max(300, min(600, a * 0.4))), .easy, label: "settle into race rhythm"), cool(a)
            ], note: "The mass start is a sprint for clear water. Practise going hard for 50 m, then settling into a pace you can hold.")
        }
        func racePace() -> Draft {
            Draft(type: .thr, title: "Race-pace reps", steps: [
                SetStep(.wu, 1, 300, .easy), SetStep(.main, 4, 200, .thr, rest: 30, label: "race pace"),
                SetStep(.main, 4, 50, .fast, rest: 30, label: "fast start"), cool(1000)
            ])
        }
        func trial(_ a: Double) -> Draft {
            let d = a >= 400 ? 400 : a >= 200 ? 200 : 100, dd = repDist(a * 0.5)
            return Draft(type: .tt, title: "Time trial", steps: [
                warm(a),
                SetStep(.drill, 4, pool, .steady, rest: 20, label: "build each length"),
                SetStep(.main, 1, d, .max, label: "timed"),
                SetStep(.main, max(2, Int((0.6 * a / Double(dd)).rounded())), dd, .easy, rest: 20, label: "aerobic"),
                cool(a)
            ], note: "Push off from the wall, no dive. Swim the \(d) m evenly and check your time as you touch.", tt: d)
        }
        func longSwim(_ a: Double, _ p: Double, title: String?, note: String, ow: Bool) -> Draft {
            let ai = Int(a.rounded())
            if a >= 400 {
                return Draft(type: .long, title: title ?? "Long swim", steps: [
                    warm(a), SetStep(.main, 1, ai, .easy, label: "non-stop"), cool(a)
                ], note: note, cont: ai, ow: ow)
            }
            let d = max(pool, rnd(a * 0.5, pool)), reps = max(3, Int((a * 2.5 / Double(d)).rounded(.up)))
            return Draft(type: .long, title: title ?? "Endurance set", steps: [
                warm(a), SetStep(.main, reps, d, .easy, rest: restFor(p)), cool(a)
            ], note: note)
        }
        func easySwim(_ a: Double, _ p: Double, _ s: Double) -> Draft {
            let ev = rnd(a * 0.6 * s, stp(a * 0.6))
            if ev >= 400 {
                return Draft(type: .easy, title: "Easy swim", steps: [warm(a), SetStep(.main, 1, ev, .easy, label: "non-stop, relaxed"), cool(a)])
            }
            let d = max(pool, rnd(Double(ev) * 0.5, pool)), reps = max(3, Int((Double(ev) * 2.5 / Double(d)).rounded(.up)))
            return Draft(type: .easy, title: "Easy swim", steps: [warm(a), SetStep(.main, reps, d, .easy, rest: restFor(p)), cool(a)])
        }

        func quality(_ q: Quality, _ a: Double, _ p: Double, _ s: Double) -> Draft {
            switch q {
            case .trial: return trial(a)
            case .build: return buildSet(a, p, s)
            case .descend: return descend(a, s)
            case .fartlek: return fartlek(a, s)
            case .threshold: return threshold(a, p, s)
            case .brokenMile: return brokenMile(a, p, s)
            case .negative: return negativeSplit(a, s)
            case .speed: return speed(a, s)
            case .pyramid: return pyramid(a)
            case .fastStart: return fastStart(a, s)
            case .racePace: return racePace()
            }
        }
        func skills(_ k: Skills, _ t: Int, _ a: Double, _ p: Double, _ s: Double) -> Draft {
            switch k {
            case .technique: return technique(t, a, p, s)
            case .openWater: return openWaterSkills(a, s)
            case .kickPull: return kickPull(a, s)
            case .breathing: return breathing(t, a, s)
            }
        }

        func lineup(_ t: Int, _ a: Double, _ p: Double, _ s: Double, title: String?, note: String, ow: Bool, q: Quality, k: Skills) -> [Draft] {
            var long = longSwim(a, p, title: title, note: note, ow: ow)
            if cfg.perWeek == 1 {
                // One swim a week: the long swim carries a skill set, and the time trial in trial weeks.
                if q == .trial {
                    let tr = trial(a)
                    long.steps.insert(contentsOf: [
                        SetStep(.drill, 4, pool, .steady, rest: 20, label: "build each length"),
                        SetStep(.main, 1, tr.tt!, .max, label: "timed")
                    ], at: 1)
                    long.type = .tt
                    long.tt = tr.tt
                    long.title = long.cont != nil ? "Time trial and long swim" : "Time trial and endurance set"
                    long.note = [tr.note, "Rest as long as you need after the trial.", long.note].filter { !$0.isEmpty }.joined(separator: " ")
                } else {
                    let extra: SetStep = k == .openWater ? SetStep(.main, 6, 50, .steady, rest: 15, label: "sight forward every 6 strokes")
                        : k == .kickPull ? SetStep(.drill, 4, 100, .steady, rest: 20, label: "pull with a buoy")
                        : SetStep(.drill, 6, 50, .easy, rest: 15, label: drill(t).name)
                    long.steps.insert(extra, at: 1)
                }
                return [filled(long)]
            }
            var qual = quality(q, a, p, s)
            if cfg.perWeek == 2 {
                if !qual.steps.contains(where: { $0.kind == .drill }) {
                    let dr = drill(t)
                    qual.steps.insert(SetStep(.drill, 6, 50, .easy, rest: 15, label: dr.name), at: 1)
                    qual.note = [qual.note, "\(dr.name): \(dr.how)"].filter { !$0.isEmpty }.joined(separator: " ")
                }
                return [filled(qual), filled(long)]
            }
            let sk = skills(k, t, a, p, s)
            return (cfg.perWeek == 3 ? [sk, qual, long] : [sk, qual, easySwim(a, p, s), long]).map(filled)
        }

        // Long-swim ladder, restarted from each of the coach's changes.
        let a0 = cfg.startLong
        let weeksIn = max(tn, 0)
        var a = [Int](repeating: 0, count: weeksIn)
        var rec = [Bool](repeating: false, count: weeksIn)
        var bv = [Double](repeating: 0, count: weeksIn)
        var scale = [Double](repeating: 1, count: weeksIn)
        var adjust = [Rebase?](repeating: nil, count: weeksIn)
        for t in 0..<weeksIn {
            let l = ladder(t, start: a0, peak: peak, buildWeeks: tn, rebases: rebases)
            bv[t] = l.value
            scale[t] = l.scale
            if let r = l.anchor, r.week == t { adjust[t] = r }
            rec[t] = t % 4 == 3 && t < tn - 1 && adjust[t] == nil
            let v = rec[t] ? bv[t] * 0.75 : bv[t]
            a[t] = rnd(v, stp(v))
        }
        var firstFour = -1
        if cfg.level < 400 { firstFour = (0..<weeksIn).first { !rec[$0] && a[$0] >= 400 } ?? -1 }

        // Open-water weeks, spread over the weeks where the long swim is 800 m or more.
        let cand = (0..<weeksIn).filter { !rec[$0] && a[$0] >= 800 }
        let picks = cand.count <= Catalog.openWaterGoal
            ? Array(cand.indices)
            : (0..<4).map { Int((Double($0) * Double(cand.count - 1) / 3).rounded()) }
        var owAt: [Int: Int] = [:]
        for (i, ci) in picks.enumerated() { owAt[cand[ci]] = i }
        let ow1 = "First open-water swim. Swim 10 to 15 minutes easy with a buddy, close to the shore, then finish the distance in the pool."
        let owNote = "Do this one in open water, in a dam or the sea, with a buddy and close to the shore. Never swim alone. Use the pool if conditions are unsafe."
        let sight = " Practise sighting: lift your eyes, find a landmark, then breathe."

        var codes: [String] = []
        func phaseIndex(_ code: String) -> Int {
            if let i = codes.firstIndex(of: code) { return i }
            codes.append(code)
            return codes.count - 1
        }

        let baseQuality: [Quality] = [.build, .descend, .fartlek]
        let enduranceQuality: [Quality] = [.threshold, .brokenMile, .negative, .speed, .pyramid, .fastStart]
        let baseSkills: [Skills] = [.technique, .breathing, .kickPull]
        let enduranceSkills: [Skills] = [.technique, .openWater, .kickPull, .breathing]

        var weeks: [DraftWeek] = []
        var bi = 0, ei = 0, si = 0
        var fullMileDone = false
        let mileWeek = (1..<max(1, tn - 1)).last { !rec[$0] && a[$0] >= 1000 } ?? -1
        for t in 0..<weeksIn {
            let prog = tn > 1 ? Double(t) / Double(tn - 1) : 1
            var title: String?
            var note = ""
            var focus: String
            let isBase = bv[t] < 400
            let code = isBase ? "base" : "end"
            if t == tn - 1 {
                title = "Milestone swim"
                note = a[t] > 1600 ? "\(Fmt.dist(a[t])) is \(a[t] - 1600) m more than the race." : a[t] == 1600 ? "This is the full race distance." : ""
                focus = "Milestone week: \(Fmt.dist(a[t])) non-stop."
            } else if t == firstFour {
                title = "Milestone swim"
                note = "Your first \(Fmt.num(a[t])) m without stopping. If you feel good at the end, keep going a little further."
                focus = "Milestone week: \(Fmt.num(a[t])) m non-stop."
            } else if rec[t] {
                focus = "Recovery week. Lower volume, and a time trial to reset your paces."
            } else if a[t] < 400 {
                focus = "Build with short reps. Focus on relaxed breathing."
            } else {
                focus = "\(Fmt.dist(a[t])) non-stop."
            }
            var ow = false
            if let i = owAt[t] {
                let on = i == 0 ? ow1 : owNote + (i == 2 ? sight : "")
                note = note.isEmpty ? on : note + " " + on
                ow = true
                focus += " Open-water swim this week."
            }
            var q: Quality
            if rec[t] || (t == 0 && cfg.level >= 100) {
                q = .trial
            } else if isBase {
                q = baseQuality[bi % baseQuality.count]; bi += 1
            } else {
                q = enduranceQuality[ei % enduranceQuality.count]; ei += 1
                if q == .pyramid && a[t] < 600 { q = .threshold }
                // The full broken mile is the key race-specific set: make sure it comes round late in the build.
                if t == mileWeek && !fullMileDone { q = .brokenMile }
                if q == .brokenMile && a[t] >= 1000 { fullMileDone = true }
            }
            var k = (isBase ? baseSkills : enduranceSkills)[si % (isBase ? baseSkills.count : enduranceSkills.count)]
            si += 1
            if ow { k = .openWater }
            if t == 0 && q == .trial { focus = "Start with a time trial to set your paces." }
            if let r = adjust[t] { focus = "Adjusted: \(r.reason) " + focus }
            weeks.append(DraftWeek(phase: phaseIndex(code), focus: focus, rec: rec[t], long: a[t], buildLong: rnd(bv[t], stp(bv[t])),
                                   drafts: lineup(t, Double(a[t]), prog, scale[t], title: title, note: note, ow: ow, q: q, k: k),
                                   adjustment: adjust[t]))
        }

        // Taper week
        let finalLong = a.last ?? Int(a0)
        let taperLong = rnd(Double(max(finalLong, 1000)) * 0.65, stp(Double(finalLong) * 0.65))
        weeks.append(DraftWeek(phase: phaseIndex("taper"), focus: "Taper. Less volume, same sharpness.", rec: false, long: taperLong, buildLong: taperLong,
                               drafts: lineup(tn, Double(taperLong), 1, 1, title: nil, note: "", ow: false, q: .racePace, k: .openWater)))

        // Race week
        let pre = Array(offs.filter { $0 <= raceOff - 2 }.suffix(2))
        var raceDrafts: [Draft] = pre.indices.map { i in
            filled(i == 0 && pre.count == 2
                ? Draft(type: .easy, title: "Easy swim", steps: [SetStep(.wu, 1, 300, .easy), SetStep(.main, 4, 50, .fast, rest: 30, label: "quick, not flat out"),
                                                                 SetStep(.main, 1, 400, .easy, label: "relaxed"), SetStep(.cd, 1, 100, .easy)])
                : Draft(type: .easy, title: "Shake-out", steps: [SetStep(.wu, 1, 300, .easy), SetStep(.main, 4, 50, .fast, rest: 30, label: "fast start, then settle"),
                                                                 SetStep(.main, 1, 400, .easy, label: "sight every 8 strokes"), SetStep(.cd, 1, 100, .easy)]))
        }
        raceDrafts.append(Draft(type: .race, title: "Race day",
                                steps: [SetStep(.race, 1, Catalog.raceDistance, .thr, label: "open water at Midmar Dam")],
                                note: "Check your entry confirmation for the day and wave you swim, and tick this off on that day. Use the same goggles you trained in.",
                                ow: true, race: true))
        weeks.append(DraftWeek(phase: phaseIndex("taper"), focus: "Race week. Stay loose and rest.", rec: false, long: Catalog.raceDistance, buildLong: Catalog.raceDistance, drafts: raceDrafts))

        // Dates
        let beginOff = Days.between(start, begin)
        var all: [Session] = []
        var planWeeks: [PlanWeek] = []
        for (w, wk) in weeks.enumerated() {
            let ws = Days.add(start, w * 7)
            var drafts = wk.drafts
            var days = w == weekCount - 1 ? pre + [raceOff] : offs
            if w == 0 && beginOff > 0 {
                // The plan starts mid-week: keep the later swims and fit them into the days that are left.
                let keep = min(drafts.count, 7 - beginOff)
                drafts = Array(drafts.suffix(keep))
                days = Array(days.suffix(keep))
                var used = days.filter { $0 >= beginOff }
                var free = beginOff
                days = days.map { d in
                    if d >= beginOff { return d }
                    while used.contains(free) { free += 1 }
                    used.append(free)
                    return free
                }
                let order = zip(days, drafts).sorted { $0.0 < $1.0 }
                days = order.map { $0.0 }
                drafts = order.map { $0.1 }
            }
            var sessions: [Session] = []
            for (i, d) in drafts.enumerated() {
                let date = Days.add(ws, days[i])
                let s = Session(key: Days.key(date), week: w, date: date, at: date, type: d.type, title: d.title,
                                steps: d.steps, baseSteps: d.steps, note: d.note, cont: d.cont, tt: d.tt, ladder: d.ladder,
                                openWater: d.ow, isRace: d.race)
                sessions.append(s)
                all.append(s)
            }
            planWeeks.append(PlanWeek(index: w, phase: wk.phase, focus: wk.focus, isRecovery: wk.rec, long: wk.long, buildLong: wk.buildLong,
                                      sessions: sessions, adjustment: wk.adjustment))
        }

        let meta: [String: (String, String)] = [
            "base": ("Base", "Swim 400 m without stopping"),
            "end": ("Endurance", Double(cfg.level) >= Double(peak) * 0.8 ? "Hold \(Fmt.dist(peak)) non-stop and sharpen" : "Build to \(Fmt.dist(min(peak, finalLong))) non-stop"),
            "taper": ("Taper", "Rest up and race")
        ]
        let phases: [Phase] = codes.enumerated().map { i, c in
            let idx = planWeeks.filter { $0.phase == i }.map(\.index)
            let first = idx.first ?? 0, last = idx.last ?? 0
            let range = first == last ? "Week \(first + 1)"
                : last == first + 1 ? "Weeks \(first + 1) and \(last + 1)" : "Weeks \(first + 1) to \(last + 1)"
            return Phase(name: meta[c]!.0, goal: meta[c]!.1, range: range)
        }
        let milestones: [Milestone] = [400, 800, 1200, 1600, 2000, 2400].filter { $0 <= peak }.map { m in
            var k = 0
            while k < tn && (rec[k] || a[k] < m) { k += 1 }
            return Milestone(metres: m, week: max(0, min(k, tn - 1)))
        }
        let growth = tn > 1 ? pow(Double(peak) / a0, 1 / Double(tn - 1)) - 1 : 0
        return Plan(config: cfg, start: start, begin: begin, race: race, weeks: planWeeks, phases: phases,
                    milestones: milestones, sessions: all, startLong: Int(a0), growth: growth,
                    finalLong: finalLong, rebases: rebases)
    }
}
