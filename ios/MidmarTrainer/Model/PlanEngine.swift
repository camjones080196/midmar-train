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
    let sessions: [Session]
    var metres: Int { sessions.reduce(0) { $0 + $1.metres } }
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

    var weekCount: Int { weeks.count }
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
        var drafts: [Draft]
    }

    private enum Quality { case tt, build, thr, speed, pyr, racePace }

    static func build(_ input: PlanConfig) -> Plan {
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
        func restFor(_ p: Double) -> Int { max(15, Int(((40 - 20 * p) / 5).rounded()) * 5) }
        func repDist(_ x: Double) -> Int {
            let d = x < 150 ? 50 : x < 300 ? 75 : x < 500 ? 100 : x < 1400 ? 200 : x < 1800 ? 300 : 400
            return max(pool, Int((Double(d) / Double(pool)).rounded(.up)) * pool)
        }
        func wc(_ a: Double) -> (Int, Int) { a < 1000 ? (100, 50) : (200, 100) }
        func drill(_ t: Int) -> (name: String, how: String) { Catalog.drills[t % Catalog.drills.count] }

        func tech(_ t: Int, _ a: Double, _ p: Double) -> Draft {
            let (w, c) = wc(a), total = min(800, 0.5 * a + 250), d = repDist(a * 0.5), dr = drill(t)
            return Draft(type: .tech, title: "Technique", steps: [
                SetStep(.wu, 1, w, .easy),
                SetStep(.drill, 4, pool, .easy, rest: 15, label: dr.name),
                SetStep(.main, max(2, Int((total / Double(d)).rounded())), d, .easy, rest: max(15, restFor(p) - 5), label: "long, smooth strokes"),
                SetStep(.cd, 1, c, .easy)
            ], note: "\(dr.name): \(dr.how)")
        }
        func buildSet(_ a: Double, _ p: Double) -> Draft {
            let (w, c) = wc(a), total = min(1600, 1.2 * a + 300), d = repDist(a)
            return Draft(type: .build, title: "Build intervals", steps: [
                SetStep(.wu, 1, w, .easy),
                SetStep(.main, max(2, Int((total / Double(d)).rounded())), d, .steady, rest: restFor(p)),
                SetStep(.cd, 1, c, .easy)
            ])
        }
        func threshold(_ a: Double, _ p: Double) -> Draft {
            let (w, c) = wc(a), total = min(1600, 1.2 * a + 300), d = repDist(a)
            return Draft(type: .thr, title: "Threshold reps", steps: [
                SetStep(.wu, 1, w, .easy),
                SetStep(.main, max(2, Int((total / Double(d)).rounded())), d, .thr, rest: max(20, restFor(p))),
                SetStep(.cd, 1, c, .easy)
            ])
        }
        func speed(_ a: Double) -> Draft {
            let (w, c) = wc(a), n = min(16, max(8, Int(((0.5 * a + 200) / 50).rounded())))
            return Draft(type: .speed, title: "Speed set", steps: [
                SetStep(.wu, 1, w, .easy),
                SetStep(.drill, 4, pool, .steady, rest: 15, label: "build each length"),
                SetStep(.main, n, 50, .fast, rest: 30),
                SetStep(.main, 1, 200, .easy, label: "loosen off"),
                SetStep(.cd, 1, c, .easy)
            ])
        }
        func pyramid(_ a: Double) -> Draft {
            let (w, c) = wc(a)
            let ds = a >= 1400 ? [100, 200, 300, 400, 300, 200, 100] : [100, 200, 300, 200, 100]
            return Draft(type: .pyr, title: "Pyramid",
                         steps: [SetStep(.wu, 1, w, .easy)] + ds.map { SetStep(.main, 1, $0, .steady, rest: 20) } + [SetStep(.cd, 1, c, .easy)],
                         ladder: ds)
        }
        func trial(_ a: Double) -> Draft {
            let (w, _) = wc(a), d = a >= 400 ? 400 : a >= 200 ? 200 : 100, dd = repDist(a * 0.5)
            return Draft(type: .tt, title: "Time trial", steps: [
                SetStep(.wu, 1, w, .easy),
                SetStep(.drill, 4, pool, .steady, rest: 20, label: "build each length"),
                SetStep(.main, 1, d, .max, label: "timed"),
                SetStep(.main, max(2, Int((0.6 * a / Double(dd)).rounded())), dd, .easy, rest: 20, label: "aerobic"),
                SetStep(.cd, 1, 100, .easy)
            ], note: "Push off from the wall, no dive. Swim the \(d) m evenly and check your time as you touch.", tt: d)
        }
        func longSwim(_ a: Double, _ p: Double, title: String?, note: String, ow: Bool) -> Draft {
            let (w, c) = wc(a)
            let ai = Int(a.rounded())
            if a >= 400 {
                return Draft(type: .long, title: title ?? "Long swim", steps: [
                    SetStep(.wu, 1, w, .easy), SetStep(.main, 1, ai, .easy, label: "non-stop"), SetStep(.cd, 1, c, .easy)
                ], note: note, cont: ai, ow: ow)
            }
            let d = max(pool, rnd(a * 0.5, pool)), n = max(3, Int((a * 2.5 / Double(d)).rounded(.up)))
            return Draft(type: .long, title: title ?? "Endurance set", steps: [
                SetStep(.wu, 1, w, .easy), SetStep(.main, n, d, .easy, rest: restFor(p)), SetStep(.cd, 1, c, .easy)
            ], note: note)
        }
        func easySwim(_ a: Double, _ p: Double) -> Draft {
            let ev = rnd(a * 0.6, stp(a * 0.6)), (w, c) = wc(Double(ev))
            if ev >= 400 {
                return Draft(type: .easy, title: "Easy swim", steps: [
                    SetStep(.wu, 1, w, .easy), SetStep(.main, 1, ev, .easy, label: "non-stop"), SetStep(.cd, 1, c, .easy)
                ])
            }
            let d = max(pool, rnd(Double(ev) * 0.5, pool)), n = max(3, Int((Double(ev) * 2.5 / Double(d)).rounded(.up)))
            return Draft(type: .easy, title: "Easy swim", steps: [
                SetStep(.wu, 1, w, .easy), SetStep(.main, n, d, .easy, rest: restFor(p)), SetStep(.cd, 1, c, .easy)
            ])
        }
        func lineup(_ t: Int, _ a: Double, _ p: Double, title: String?, note: String, ow: Bool, q: Quality) -> [Draft] {
            var long = longSwim(a, p, title: title, note: note, ow: ow)
            if cfg.perWeek == 1 {
                // One swim a week: the long swim carries a drill, and the time trial in trial weeks.
                if q == .tt {
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
                    let dr = drill(t)
                    long.steps.insert(SetStep(.drill, 4, pool, .easy, rest: 15, label: dr.name), at: 1)
                    long.note = [long.note, "\(dr.name): \(dr.how)"].filter { !$0.isEmpty }.joined(separator: " ")
                }
                return [long]
            }
            var quality: Draft
            switch q {
            case .tt: quality = trial(a)
            case .thr: quality = threshold(a, p)
            case .speed: quality = speed(a)
            case .pyr: quality = pyramid(a)
            case .racePace:
                quality = Draft(type: .thr, title: "Race-pace reps", steps: [
                    SetStep(.wu, 1, 200, .easy), SetStep(.main, 4, 200, .thr, rest: 30), SetStep(.cd, 1, 100, .easy)
                ])
            case .build: quality = buildSet(a, p)
            }
            if cfg.perWeek == 2 {
                if !quality.steps.contains(where: { $0.kind == .drill }) {
                    let dr = drill(t)
                    quality.steps.insert(SetStep(.drill, 4, pool, .easy, rest: 15, label: dr.name), at: 1)
                    quality.note = "\(dr.name): \(dr.how)"
                }
                return [quality, long]
            }
            return cfg.perWeek == 3 ? [tech(t, a, p), quality, long] : [tech(t, a, p), quality, easySwim(a, p), long]
        }

        // Long-swim ladder: geometric growth, with a lighter week every fourth week.
        let a0 = cfg.startLong
        var a = [Int](repeating: 0, count: max(tn, 0))
        var rec = [Bool](repeating: false, count: max(tn, 0))
        var bv = [Double](repeating: 0, count: max(tn, 0))
        for t in 0..<max(tn, 0) {
            let prog = tn > 1 ? Double(t) / Double(tn - 1) : 1
            bv[t] = a0 * pow(Double(peak) / a0, prog)
            rec[t] = t % 4 == 3 && t < tn - 1
            let v = rec[t] ? bv[t] * 0.75 : bv[t]
            a[t] = rnd(v, stp(v))
        }
        var firstFour = -1
        if cfg.level < 400 { firstFour = (0..<max(tn, 0)).first { !rec[$0] && a[$0] >= 400 } ?? -1 }

        // Open-water weeks, spread over the weeks where the long swim is 800 m or more.
        let cand = (0..<max(tn, 0)).filter { !rec[$0] && a[$0] >= 800 }
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

        var weeks: [DraftWeek] = []
        var qi = 0
        for t in 0..<max(tn, 0) {
            let prog = tn > 1 ? Double(t) / Double(tn - 1) : 1
            var title: String?
            var note = ""
            var focus: String
            let code = bv[t] < 400 ? "base" : "end"
            if t == tn - 1 {
                title = "Milestone swim"
                note = peak > 1600 ? "\(Fmt.dist(peak)) is \(peak - 1600) m more than the race." : "This is the full race distance."
                focus = "Milestone week: \(Fmt.dist(peak)) non-stop."
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
                q = .tt
            } else if bv[t] < 400 {
                q = .build
            } else {
                q = [Quality.thr, .speed, .pyr][qi % 3]
                if q == .pyr && a[t] < 600 { q = .thr }
                qi += 1
            }
            if t == 0 && q == .tt { focus = "Start with a time trial to set your paces." }
            weeks.append(DraftWeek(phase: phaseIndex(code), focus: focus, rec: rec[t], long: a[t],
                                   drafts: lineup(t, Double(a[t]), prog, title: title, note: note, ow: ow, q: q)))
        }

        // Taper week
        let taperLong = rnd(Double(peak) * 0.65, stp(Double(peak) * 0.65))
        weeks.append(DraftWeek(phase: phaseIndex("taper"), focus: "Taper. Less volume, same sharpness.", rec: false, long: taperLong,
                               drafts: lineup(tn, Double(taperLong), 1, title: nil, note: "", ow: false, q: .racePace)))

        // Race week
        let pre = Array(offs.filter { $0 <= raceOff - 2 }.suffix(2))
        var raceDrafts: [Draft] = pre.indices.map { i in
            i == 0 && pre.count == 2
                ? Draft(type: .easy, title: "Easy swim", steps: [SetStep(.wu, 1, 200, .easy), SetStep(.main, 4, 50, .fast, rest: 30, label: "quick, not flat out"), SetStep(.cd, 1, 100, .easy)])
                : Draft(type: .easy, title: "Shake-out", steps: [SetStep(.wu, 1, 200, .easy), SetStep(.main, 4, pool, .fast, rest: 30), SetStep(.cd, 1, 100, .easy)])
        }
        raceDrafts.append(Draft(type: .race, title: "Race day",
                                steps: [SetStep(.race, 1, Catalog.raceDistance, .thr, label: "open water at Midmar Dam")],
                                note: "Check your entry confirmation for the day and wave you swim, and tick this off on that day. Use the same goggles you trained in.",
                                ow: true, race: true))
        weeks.append(DraftWeek(phase: phaseIndex("taper"), focus: "Race week. Stay loose and rest.", rec: false, long: Catalog.raceDistance, drafts: raceDrafts))

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
            planWeeks.append(PlanWeek(index: w, phase: wk.phase, focus: wk.focus, isRecovery: wk.rec, long: wk.long, sessions: sessions))
        }

        let meta: [String: (String, String)] = [
            "base": ("Base", "Swim 400 m without stopping"),
            "end": ("Endurance", Double(cfg.level) >= Double(peak) * 0.8 ? "Hold \(Fmt.dist(peak)) non-stop and sharpen" : "Build to \(Fmt.dist(peak)) non-stop"),
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
                    milestones: milestones, sessions: all, startLong: Int(a0), growth: growth)
    }
}
