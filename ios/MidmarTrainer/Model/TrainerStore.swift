import Foundation
import Observation

/// The app's single source of truth: saved state, the plan built from it, and the swims read from Health.
@Observable
final class TrainerStore {
    private(set) var state: TrainerState
    private(set) var plan: Plan
    /// Planned sessions with the swimmer's edits and moves applied, in date order.
    private(set) var sessions: [Session] = []
    /// Recent swims read from Apple Health, newest first.
    private(set) var swims: [SwimRecord] = []

    private let fileURL: URL?
    private let now: () -> Date

    init(fileURL: URL? = TrainerStore.defaultURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
        var loaded = TrainerState()
        if let fileURL, let data = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(TrainerState.self, from: data) {
            loaded = s
        }
        loaded.config = loaded.config.normalized()
        state = loaded
        plan = PlanEngine.build(loaded.config)
        freshStart()
        resolve()
    }

    static var defaultURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("MidmarTrainer", isDirectory: true).appendingPathComponent("state.json")
    }

    // MARK: Derived

    var today: Date { Days.today(now()) }
    var thr: Double? { state.threshold }
    var currentWeek: Int { plan.weekIndex(of: today) }
    var hasStarted: Bool { today >= plan.begin }

    func session(_ key: String) -> Session? { sessions.first { $0.key == key } }
    func sessions(inWeek i: Int) -> [Session] { sessions.filter { plan.weekIndex(of: $0.at) == i } }
    func isDone(_ key: String) -> Bool { state.done[key] != nil }
    func isSkipped(_ key: String) -> Bool { state.skipped.contains(key) && state.done[key] == nil }
    func isMissed(_ s: Session) -> Bool { !isDone(s.key) && !isSkipped(s.key) && s.at < today }

    func plannedMetres(week i: Int) -> Int { sessions(inWeek: i).filter { !isSkipped($0.key) }.reduce(0) { $0 + $1.metres } }
    func swumMetres(week i: Int) -> Int { sessions(inWeek: i).reduce(0) { $0 + swum($1) } }
    /// Metres actually swum for a session: the recorded distance if there is one, otherwise the plan.
    func swum(_ s: Session) -> Int {
        guard let r = state.done[s.key] else { return 0 }
        return r.distance ?? s.metres
    }

    /// Today's swim if it is still to do, otherwise the next one.
    func nextUp() -> (session: Session, label: String)? {
        let t = today
        let todays = sessions.first { Days.start($0.at) == t }
        if let s = todays, !isDone(s.key), !isSkipped(s.key) { return (s, "Today · \(Days.withWeekday(t))") }
        guard let next = sessions.first(where: { $0.at > t && !isDone($0.key) && !isSkipped($0.key) }) else { return nil }
        let doneToday = todays.map { isDone($0.key) } ?? false
        return (next, (doneToday ? "Done for today · next swim " : "Next swim · ") + Days.withWeekday(next.at))
    }

    /// Swims to keep on the watch: still to do, from today for the next two weeks.
    func watchQueue(days: Int = 14) -> [Session] {
        let t = today, end = Days.add(t, days)
        return sessions.filter { !$0.isRace && $0.at >= t && $0.at < end && !isDone($0.key) && !isSkipped($0.key) }
    }

    /// Changes whenever the watch's swims need updating.
    var watchToken: String {
        watchQueue().map { "\(Days.key($0.at)):\(WatchWorkouts.signature($0))" }.joined(separator: "#")
    }

    /// No swims ticked in the last two weeks, while the plan is under way.
    var isStale: Bool {
        let t = today
        guard t >= Days.add(plan.begin, 14), t <= plan.race else { return false }
        let from = Days.add(t, -14)
        return !sessions.contains { $0.at >= from && $0.at <= t && isDone($0.key) }
    }

    /// Health swims during the plan that are not linked to a session and not ignored.
    var unmatchedSwims: [SwimRecord] {
        swims.filter { state.links[$0.id] == nil && !state.ignored.contains($0.id) && $0.day >= plan.begin && $0.day <= plan.race }
    }

    func swim(for sessionKey: String) -> SwimRecord? {
        guard let id = state.done[sessionKey]?.workoutID else { return nil }
        return swims.first { $0.id == id }
    }

    // MARK: Actions

    func markDone(_ key: String, feel: Int, time: Int, trialSeconds: Int?, nonStop: Bool, openWater: Bool) {
        guard let s = session(key) else { return }
        let day = Days.key(today)
        update { st in
            st.done[key] = DoneRecord(date: day, feel: feel, time: time)
            st.skipped.remove(key)
            if let secs = trialSeconds, let d = s.tt { st.trials.append(TimeTrial(date: day, dist: d, secs: secs)) }
            if nonStop, let m = s.cont, !st.nonstop.contains(where: { $0.date == day && $0.metres == m }) {
                st.nonstop.append(NonStopSwim(date: day, metres: m, openWater: openWater))
            }
        }
    }

    /// Changes a finished swim's result. Distance nil means "as planned".
    func updateResult(_ key: String, feel: Int, time: Int, date: Date, distance: Int?) {
        update { st in
            st.done[key]?.feel = feel
            st.done[key]?.time = time
            st.done[key]?.date = Days.key(date)
            st.done[key]?.distance = distance
        }
    }

    /// Marks a session not done. A swim that came from Health is not matched to it again.
    func undo(_ key: String) {
        update { st in
            if let id = st.done[key]?.workoutID {
                st.links[id] = nil
                st.ignored.insert(id)
            }
            st.done[key] = nil
        }
    }

    func skip(_ key: String) { update { $0.skipped.insert(key) } }
    func unskip(_ key: String) { update { $0.skipped.remove(key) } }

    /// Days a session can move to: from the plan start to the day before the race, without another swim.
    func canMove(_ key: String, to date: Date) -> Bool {
        let d = Days.start(date)
        guard d >= plan.begin, d < plan.race else { return false }
        return !sessions.contains { $0.key != key && Days.start($0.at) == d }
    }

    func move(_ key: String, to date: Date?) {
        update { st in
            if let date, Days.key(date) != key { st.moved[key] = Days.key(date) } else { st.moved[key] = nil }
        }
    }

    func saveEdit(_ key: String, steps: [SetStep]) { update { $0.edits[key] = steps } }
    func resetEdit(_ key: String) { update { $0.edits[key] = nil } }

    func addTrial(dist: Int, secs: Int, date: Date) {
        update { $0.trials.append(TimeTrial(date: Days.key(date), dist: dist, secs: secs)) }
    }
    func deleteTrial(_ id: UUID) { update { $0.trials.removeAll { $0.id == id } } }

    func addNonStop(metres: Int, date: Date, openWater: Bool) {
        update { $0.nonstop.append(NonStopSwim(date: Days.key(date), metres: metres, openWater: openWater)) }
    }
    func deleteNonStop(_ id: UUID) { update { $0.nonstop.removeAll { $0.id == id } } }

    /// Saves new settings, plus an optional timed swim from setup.
    func applyConfig(_ config: PlanConfig, trial: (dist: Int, secs: Int)?) {
        var c = config
        c.setup = true
        let day = Days.key(today)
        update { st in
            st.config = c.normalized()
            if let trial { st.trials.append(TimeTrial(date: day, dist: trial.dist, secs: trial.secs)) }
        }
    }

    /// Counts a Health swim for a session, or for nothing.
    func link(_ swimID: String, to key: String?) {
        guard let swim = swims.first(where: { $0.id == swimID }) else { return }
        update { st in
            if let key {
                st.ignored.remove(swimID)
                apply(swim, to: key, in: &st)
            } else {
                st.ignored.insert(swimID)
            }
        }
    }

    /// Replaces everything with data copied from the web app. Swim links from Health are kept,
    /// so watch swims are not matched twice.
    func importFromWeb(_ imported: TrainerState) {
        update { st in
            var n = imported
            n.links = [:]
            n.ignored = st.ignored.union(st.links.keys)
            st = n
        }
    }

    func eraseAll() {
        update { st in st = TrainerState() }
        freshStart()
    }

    // MARK: Health

    /// Takes swims read from Health, links new ones to sessions and records their results.
    func ingest(_ swims: [SwimRecord]) {
        self.swims = swims.sorted { $0.start > $1.start }
        let matches = SwimMatcher.match(swims: swims, sessions: sessions, state: state, begin: plan.begin, race: plan.race)
        let needsNonStop = swims.contains { sw in
            state.links[sw.id] != nil && (sw.longestNonStop ?? 0) >= 100 && !state.nonstop.contains { $0.workoutID == sw.id }
        }
        guard !matches.isEmpty || needsNonStop else { return }
        update { st in
            for (id, key) in matches {
                if let swim = swims.first(where: { $0.id == id }) { apply(swim, to: key, in: &st) }
            }
            for sw in swims where st.links[sw.id] != nil { recordNonStop(sw, in: &st) }
        }
    }

    private func apply(_ swim: SwimRecord, to key: String, in st: inout TrainerState) {
        if let old = st.links.first(where: { $0.value == key && $0.key != swim.id })?.key { st.links[old] = nil }
        if let previous = st.links[swim.id], previous != key, st.done[previous]?.workoutID == swim.id { st.done[previous] = nil }
        st.links[swim.id] = key
        let feel = st.done[key]?.feel ?? 0
        st.done[key] = DoneRecord(date: Days.key(swim.day), feel: feel, time: Int(swim.duration.rounded()),
                                  source: .health, workoutID: swim.id, distance: swim.metres)
        st.skipped.remove(key)
        if let s = session(key), let d = s.tt, let secs = SwimMatcher.trialTime(in: swim, distance: d),
           !st.trials.contains(where: { $0.workoutID == swim.id }) {
            st.trials.append(TimeTrial(date: Days.key(swim.day), dist: d, secs: secs, source: "watch", workoutID: swim.id))
        }
        recordNonStop(swim, in: &st)
    }

    private func recordNonStop(_ swim: SwimRecord, in st: inout TrainerState) {
        guard let m = swim.longestNonStop, m >= 100, !st.nonstop.contains(where: { $0.workoutID == swim.id }) else { return }
        st.nonstop.append(NonStopSwim(date: Days.key(swim.day), metres: m, openWater: swim.openWater, workoutID: swim.id))
    }

    // MARK: Internals

    /// Until the plan is set up or used, it always begins today.
    func freshStart() {
        guard !state.hasActivity else { return }
        var c = state.config
        c.start = Days.key(today)
        guard c.hasValidSpan, c.start != state.config.start else { return }
        state.config = c
        plan = PlanEngine.build(c)
        resolve()
    }

    private func update(_ change: (inout TrainerState) -> Void) {
        var s = state
        change(&s)
        let rebuild = s.config != state.config
        state = s
        if rebuild { plan = PlanEngine.build(s.config) }
        resolve()
        save()
    }

    private func resolve() { sessions = SessionResolver.effective(plan: plan, state: state) }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            try enc.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Could not save: \(error)")
        }
    }
}
