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
                        XCTAssertGreaterThanOrEqual(s.metres, PlanEngine.minimumSession, "\(s.title) on \(s.key) is only \(s.metres) m")
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

    func testEditingAFinishedSwim() {
        let store = TrainerStore(fileURL: nil, now: { Days.date("2026-11-20")! })
        var c = store.state.config
        c.start = "2026-11-16"; c.race = "2027-02-13"
        store.applyConfig(c, trial: nil)
        let s = store.sessions[0]
        store.markDone(s.key, feel: 3, time: 1800, trialSeconds: nil, nonStop: false, openWater: false)
        XCTAssertEqual(store.swumMetres(week: 0), s.metres)
        store.updateResult(s.key, feel: 4, time: 1700, date: Days.date("2026-11-17")!, distance: 600)
        XCTAssertEqual(store.state.done[s.key]?.date, "2026-11-17")
        XCTAssertEqual(store.state.done[s.key]?.feel, 4)
        XCTAssertEqual(store.swumMetres(week: 0), 600)
        store.saveEdit(s.key, steps: [SetStep(.main, 3, 100, .easy, rest: 20)])
        XCTAssertEqual(store.session(s.key)?.metres, 300)
        XCTAssertTrue(store.isDone(s.key), "editing sets keeps the swim done")
        store.updateResult(s.key, feel: 4, time: 1700, date: Days.date("2026-11-17")!, distance: nil)
        XCTAssertEqual(store.swumMetres(week: 0), 300, "as planned follows the edited sets")
    }

    func testWebImportKeepsEdits() throws {
        let json = #"""
        {"midmarTrainer":1,"cfg":{"start":"2026-11-17","race":"2027-02-13","level":200,"perWeek":3,"days":[1,3,6],"pool":25,"peak":2000,"setup":true},
         "done":{"2026-11-17":"2026-11-17"},"res":{"2026-11-17":{"feel":4,"t":1710,"g":0,"reps":[]}},
         "skip":{"2026-11-21":1},"moved":{"2026-11-18":"2026-11-19"},
         "edits":{"2026-11-17":{"steps":[{"kind":"wu","reps":1,"dist":200,"zone":"easy","rest":0,"label":""},{"kind":"main","reps":6,"dist":50,"zone":"fast","rest":30,"label":""}]}},
         "tt":[{"id":"x","date":"2026-11-17","dist":100,"secs":130}],"log":[{"id":"y","date":"2026-11-17","m":300,"ow":false}]}
        """#
        let (st, sum) = try WebImport.parse(json)
        XCTAssertEqual(sum, WebImport.Summary(done: 1, skipped: 1, moved: 1, edited: 1, trials: 1, nonstop: 1))
        XCTAssertEqual(st.done["2026-11-17"]?.time, 1710)
        let store = TrainerStore(fileURL: nil, now: { Days.date("2026-11-17")! })
        store.importFromWeb(st)
        let s = store.session("2026-11-17")!
        XCTAssertTrue(s.edited)
        XCTAssertEqual(s.metres, 500)
        XCTAssertTrue(store.isDone(s.key))
        XCTAssertEqual(store.session("2026-11-18")!.at, Days.date("2026-11-19")!)
        XCTAssertThrowsError(try WebImport.parse("hello"))
    }

    func testManualLinking() {
        let store = TrainerStore(fileURL: nil, now: { Days.date("2026-11-22")! })
        var c = store.state.config
        c.start = "2026-11-16"; c.race = "2027-02-13"; c.level = 200
        store.applyConfig(c, trial: nil)
        let mon = store.sessions[0], wed = store.sessions[1], sat = store.sessions[2]
        func sw(_ id: String, _ day: String, _ m: Double) -> SwimRecord {
            let d = Days.date(day)!.addingTimeInterval(7 * 3600)
            return SwimRecord(id: id, start: d, end: d.addingTimeInterval(1500), duration: 1500, distance: m,
                              openWater: false, lapLength: 25, sets: [SwimSet(distance: 100, duration: 95)], source: "Watch")
        }
        store.ingest([sw("a", mon.key, 700), sw("b", wed.key, 800)])
        XCTAssertEqual(store.state.links["a"], mon.key)
        XCTAssertEqual(store.state.links["b"], wed.key)

        // Move swim a onto Saturday: Monday goes back to not done.
        store.link("a", to: sat.key)
        XCTAssertNil(store.state.done[mon.key])
        XCTAssertEqual(store.state.done[sat.key]?.distance, 700)

        // Link b to Saturday: a is replaced and left alone from then on.
        store.link("b", to: sat.key)
        XCTAssertNil(store.state.done[wed.key])
        XCTAssertEqual(store.state.done[sat.key]?.workoutID, "b")
        XCTAssertTrue(store.state.ignored.contains("a"))
        store.ingest(store.swims)
        XCTAssertNil(store.state.links["a"], "a replaced swim is not matched again")

        // Unlink keeps the session done as a manual tick.
        store.unlinkSwim(from: sat.key)
        XCTAssertEqual(store.state.done[sat.key]?.source, .manual)
        XCTAssertNil(store.state.links["b"])

        // Don't count it
        store.link("a", to: mon.key)
        store.link("a", to: nil)
        XCTAssertNil(store.state.done[mon.key])
        XCTAssertTrue(store.state.ignored.contains("a"))
    }

    func testWorkoutVariety() {
        var c = PlanConfig(); c.start = "2026-11-16"; c.race = "2027-02-13"; c.level = 200; c.setup = true
        let titles = Set(PlanEngine.build(c).sessions.map(\.title))
        for t in ["Broken mile", "Open-water skills", "Negative splits", "Fast-start practice", "Kick and pull", "Long swim", "Time trial", "Technique"] {
            XCTAssertTrue(titles.contains(t), "plan has \(t): \(titles.sorted())")
        }
        XCTAssertGreaterThanOrEqual(titles.count, 12)
    }

    private func coachStore(today: String) -> TrainerStore {
        let store = TrainerStore(fileURL: nil, now: { Days.date(today)! })
        var c = store.state.config
        c.start = "2026-11-16"; c.race = "2027-02-13"; c.level = 200
        store.applyConfig(c, trial: nil)
        return store
    }

    func testCoachRaisesAfterALongNonStopSwim() {
        let store = coachStore(today: "2026-11-25")
        let before = store.plan.weeks[2].long
        let week0 = store.plan.weeks[0].sessions.map(\.metres)
        store.addNonStop(metres: 1200, date: Days.date("2026-11-24")!, openWater: false)
        let r = store.state.adapt.first
        XCTAssertEqual(r?.week, 2, "changes start next week")
        XCTAssertEqual(store.plan.weeks[2].long, 1200)
        XCTAssertGreaterThan(store.plan.weeks[2].long, before)
        XCTAssertEqual(store.plan.weeks[0].sessions.map(\.metres), week0, "past weeks do not change")
        XCTAssertNotNil(store.latestAdjustment)
        XCTAssertGreaterThanOrEqual(store.plan.weeks[store.plan.buildWeeks - 1].long, 2000, "still reaches the peak")
    }

    func testCoachEasesAfterHardSwims() {
        let store = coachStore(today: "2026-11-27")
        for s in store.sessions.filter({ $0.at <= Days.date("2026-11-27")! }) {
            store.markDone(s.key, feel: 4, time: 0, trialSeconds: nil, nonStop: false, openWater: false)
        }
        let r = store.state.adapt.first { $0.week == 2 }
        XCTAssertEqual(r?.scale, 0.9)
        XCTAssertTrue(r?.reason.contains("hard") ?? false)
    }

    func testCoachEasesBackInAfterTimeOff() {
        let store = coachStore(today: "2026-12-07")
        let r = store.state.adapt.first { $0.week == 4 }
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.scale, 0.85)
        XCTAssertTrue(r?.reason.contains("days since") ?? false)
    }

    func testCoachLeavesAnOnTrackPlanAlone() {
        let store = coachStore(today: "2026-11-27")
        for s in store.sessions.filter({ $0.at <= Days.date("2026-11-27")! }) {
            store.markDone(s.key, feel: 3, time: 0, trialSeconds: nil, nonStop: false, openWater: false)
        }
        XCTAssertTrue(store.state.adapt.isEmpty, "\(store.state.adapt)")
        XCTAssertNil(store.latestAdjustment)
    }

    func testReplanClearsCoachChanges() {
        let store = coachStore(today: "2026-11-25")
        store.addNonStop(metres: 1200, date: Days.date("2026-11-24")!, openWater: false)
        XCTAssertFalse(store.state.adapt.isEmpty)
        var c = store.state.config
        c.level = 1000
        store.applyConfig(c, trial: nil)
        XCTAssertFalse(store.state.adapt.contains { $0.reason.contains("non-stop") && $0.long == 1200 && $0.week == 2 } && store.plan.weeks[2].long != 1200)
    }

    func testFreshPlanStartsToday() {
        let store = TrainerStore(fileURL: nil, now: { Days.date("2026-11-19")! })
        XCTAssertEqual(store.state.config.start, "2026-11-19")
        XCTAssertTrue(store.sessions.allSatisfy { $0.at >= Days.date("2026-11-19")! })
    }
}
