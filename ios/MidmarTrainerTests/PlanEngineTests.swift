import XCTest
@testable import MidmarTrainer

final class PlanEngineTests: XCTestCase {
    private func config(start: String = "2026-11-17", race: String = "2027-02-13", level: Int = 200,
                        perWeek: Int = 3, days: [Int] = [1, 3, 6], pool: Int = 25, peak: Int = 2000) -> PlanConfig {
        var c = PlanConfig()
        c.start = start; c.race = race; c.level = level; c.perWeek = perWeek; c.days = days; c.pool = pool; c.peak = peak; c.setup = true
        return c
    }

    func testDefaultPlanShape() {
        let plan = PlanEngine.build(config())
        XCTAssertEqual(plan.weekCount, 13)
        XCTAssertEqual(plan.phases.map(\.name), ["Base", "Endurance", "Taper"])
        XCTAssertEqual(plan.sessions.last?.isRace, true)
        XCTAssertEqual(Days.key(plan.sessions.last!.date), "2027-02-13")
        XCTAssertEqual(plan.weeks[plan.weekCount - 3].long, 2000, "the last build week reaches the peak")
    }

    func testEverySessionFitsThePool() {
        for pool in [25, 50] {
            for per in 1...4 {
                for level in [0, 200, 900, 2400] {
                    let days = PlanConfig.presets[per]!
                    let plan = PlanEngine.build(config(level: level, perWeek: per, days: days, pool: pool))
                    for s in plan.sessions where !s.isRace {
                        XCTAssertEqual(s.metres % pool, 0, "\(s.title) on \(s.key) is \(s.metres) m in a \(pool) m pool")
                        XCTAssertTrue(s.steps.contains { $0.kind == .main }, "\(s.title) has a main set")
                    }
                    XCTAssertEqual(Set(plan.sessions.map(\.key)).count, plan.sessions.count, "no two swims on one day")
                }
            }
        }
    }

    func testSwimsPerWeek() {
        for per in 1...4 {
            let plan = PlanEngine.build(config(start: "2026-11-16", perWeek: per, days: PlanConfig.presets[per]!))
            for w in plan.weeks.dropLast() { XCTAssertEqual(w.sessions.count, per, "week \(w.index + 1)") }
        }
    }

    func testMidWeekStartFitsTheDaysLeft() {
        // Thursday start with Mon/Wed/Sat swims: the two later swims land Thursday onward.
        let plan = PlanEngine.build(config(start: "2026-11-19"))
        let first = plan.weeks[0].sessions
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.allSatisfy { $0.date >= plan.begin }, first.map(\.key).joined(separator: ","))
        XCTAssertEqual(Set(first.map(\.key)).count, first.count)
        XCTAssertEqual(first.last?.type, .long, "the long swim is kept")
    }

    func testOneSwimWeekCarriesTheTrial() {
        let plan = PlanEngine.build(config(perWeek: 1, days: [6]))
        let w1 = plan.weeks[0].sessions[0]
        XCTAssertEqual(w1.type, .tt)
        XCTAssertNotNil(w1.tt)
        XCTAssertTrue(w1.steps.contains { $0.zone == .max })
    }

    func testInvalidSpanFallsBack() {
        let c = config(start: "2026-11-17", race: "2026-12-01").normalized()
        XCTAssertTrue(c.hasValidSpan)
        XCTAssertEqual(c.race, PlanConfig().race)
    }

    func testPacesAndFormatting() {
        let t = TimeTrial(date: "2026-11-18", dist: 100, secs: 130)
        let thr = Paces.threshold(t)
        XCTAssertEqual(thr, 130 * pow(15, 0.07), accuracy: 0.001)
        XCTAssertEqual(Fmt.time(95), "1:35")
        XCTAssertEqual(Fmt.time(3725), "1:02:05")
        XCTAssertEqual(Fmt.dist(1250), "1.25 km")
        XCTAssertEqual(Fmt.dist(2000), "2 km")
        XCTAssertEqual(Fmt.dist(800), "800 m")
        XCTAssertEqual(Fmt.num(1600), "1\u{00A0}600")
        XCTAssertEqual(Fmt.parseTime("2:10"), 130)
        XCTAssertEqual(Fmt.parseTime("1:02:05"), 3725)
        XCTAssertNil(Fmt.parseTime("99"))
        XCTAssertNil(Fmt.parseTime("2:75"))
    }

    func testEditsAndMoves() {
        let plan = PlanEngine.build(config())
        let s = plan.sessions[1]
        var st = TrainerState()
        st.config = plan.config
        st.edits[s.key] = [SetStep(.wu, 1, 200, .easy), SetStep(.main, 3, 100, .thr, rest: 20)]
        let target = Days.add(s.date, 1)
        XCTAssertFalse(plan.sessions.contains { $0.date == target }, "test needs a free day")
        st.moved[s.key] = Days.key(target)
        let eff = SessionResolver.effective(plan: plan, state: st)
        let e = eff.first { $0.key == s.key }!
        XCTAssertTrue(e.edited)
        XCTAssertEqual(e.metres, 500)
        XCTAssertEqual(e.at, target)

        // A move onto another swim's day is ignored.
        st.moved[s.key] = plan.sessions[2].key
        XCTAssertEqual(SessionResolver.effective(plan: plan, state: st).first { $0.key == s.key }!.at, s.date)
    }

    func testStateDecodesOldAndPartialData() throws {
        let json = #"{"config":{"level":500,"perWeek":2},"done":{"2026-11-18":{"date":"2026-11-18"}}}"#
        let st = try JSONDecoder().decode(TrainerState.self, from: Data(json.utf8))
        XCTAssertEqual(st.config.level, 500)
        XCTAssertEqual(st.config.pool, 25)
        XCTAssertEqual(st.done["2026-11-18"]?.source, .manual)
        let round = try JSONDecoder().decode(TrainerState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(round.config, st.config)
    }
}

final class SwimMatchingTests: XCTestCase {
    private func swim(_ id: String, _ day: String, metres: Double = 1000, sets: [SwimSet] = [], openWater: Bool = false) -> SwimRecord {
        let d = Days.date(day)!.addingTimeInterval(7 * 3600)
        return SwimRecord(id: id, start: d, end: d.addingTimeInterval(1800), duration: 1800, distance: metres,
                          openWater: openWater, lapLength: 25, sets: sets, source: "Watch")
    }

    func testMatchesSameDayThenNearby() {
        var c = PlanConfig(); c.start = "2026-11-16"; c.race = "2027-02-13"; c.setup = true
        let plan = PlanEngine.build(c)
        let sessions = SessionResolver.effective(plan: plan, state: TrainerState())
        let mon = sessions[0], wed = sessions[1]
        let tue = Days.key(Days.add(mon.date, 1))
        let m = SwimMatcher.match(swims: [swim("a", mon.key), swim("b", tue)], sessions: sessions, state: TrainerState(),
                                  begin: plan.begin, race: plan.race)
        XCTAssertEqual(m["a"], mon.key)
        XCTAssertEqual(m["b"], wed.key, "Tuesday's swim counts for Wednesday once Monday is taken")
    }

    func testIgnoredAndOutOfPlanSwimsAreLeft() {
        var c = PlanConfig(); c.start = "2026-11-16"; c.setup = true
        let plan = PlanEngine.build(c)
        var st = TrainerState()
        st.ignored = ["a"]
        let m = SwimMatcher.match(swims: [swim("a", "2026-11-16"), swim("b", "2026-10-01")],
                                  sessions: SessionResolver.effective(plan: plan, state: st), state: st,
                                  begin: plan.begin, race: plan.race)
        XCTAssertTrue(m.isEmpty)
    }

    func testSetsFromLaps() {
        let t0 = Date(timeIntervalSince1970: 0)
        func lap(_ s: Double) -> DateInterval { DateInterval(start: t0.addingTimeInterval(s), duration: 30) }
        // 4 lengths, a 40 s rest, then 2 lengths.
        let laps = [lap(0), lap(31), lap(62), lap(93), lap(163), lap(194)]
        let sets = SwimSegmenter.sets(laps: laps, lapLength: 25)
        XCTAssertEqual(sets.map(\.distance), [100, 50])
        XCTAssertEqual(sets[0].duration, 123, accuracy: 0.01)
    }

    func testTrialTimeFromSets() {
        let s = swim("a", "2026-11-18", sets: [SwimSet(distance: 200, duration: 260), SwimSet(distance: 100, duration: 95), SwimSet(distance: 100, duration: 110)])
        XCTAssertEqual(SwimMatcher.trialTime(in: s, distance: 100), 95)
        XCTAssertEqual(s.longestNonStop, 200)
        XCTAssertNil(SwimMatcher.trialTime(in: s, distance: 400))
    }

    func testStoreIngestTicksAndRecords() {
        var now = Days.date("2026-11-20")!
        let store = TrainerStore(fileURL: nil, now: { now })
        var c = store.state.config
        c.start = "2026-11-16"; c.race = "2027-02-13"; c.level = 200
        store.applyConfig(c, trial: nil)
        let first = store.sessions[0]
        let sw = swim("w1", first.key, metres: 600, sets: [SwimSet(distance: 300, duration: 400), SwimSet(distance: 300, duration: 410)])
        store.ingest([sw])
        XCTAssertEqual(store.state.done[first.key]?.source, .health)
        XCTAssertEqual(store.state.links["w1"], first.key)
        XCTAssertEqual(store.state.bestNonStop, 300)

        store.undo(first.key)
        XCTAssertNil(store.state.done[first.key])
        store.ingest([sw])
        XCTAssertNil(store.state.done[first.key], "an undone watch swim is not matched again")
        now = Days.add(now, 1)
        XCTAssertTrue(store.unmatchedSwims.isEmpty)
    }

    func testWatchQueueFollowsChanges() {
        let store = TrainerStore(fileURL: nil, now: { Days.date("2026-11-17")! })
        var c = store.state.config
        c.start = "2026-11-16"; c.race = "2027-02-13"
        store.applyConfig(c, trial: nil)
        let queue = store.watchQueue()
        XCTAssertFalse(queue.isEmpty)
        XCTAssertTrue(queue.allSatisfy { $0.at >= store.today && $0.at < Days.add(store.today, 14) })
        XCTAssertFalse(queue.contains { $0.key == "2026-11-16" }, "yesterday's swim is not sent")
        let before = store.watchToken
        store.skip(queue[0].key)
        XCTAssertNotEqual(store.watchToken, before)
        XCTAssertFalse(store.watchQueue().contains { $0.key == queue[0].key })
        let tokenAfterSkip = store.watchToken
        store.saveEdit(queue[1].key, steps: [SetStep(.main, 2, 100, .easy, rest: 20)])
        XCTAssertNotEqual(store.watchToken, tokenAfterSkip, "an edit resends that swim")
    }

    func testFreshPlanStartsToday() {
        let store = TrainerStore(fileURL: nil, now: { Days.date("2026-11-19")! })
        XCTAssertEqual(store.state.config.start, "2026-11-19")
        XCTAssertTrue(store.sessions.allSatisfy { $0.at >= Days.date("2026-11-19")! })
    }
}
