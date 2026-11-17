import Foundation
import HealthKit
import Observation
import WorkoutKit

/// Turns planned sessions into Apple Watch workouts, so the Workout app guides each set.
enum WatchWorkouts {
    /// Pool sessions become custom pool-swim workouts with a step per set and timed rests.
    /// Open-water sessions become a single distance goal.
    static func plan(for s: Session, pool: Int) -> WorkoutPlan? {
        guard !s.isRace else { return nil }
        if s.openWater, let cont = s.cont {
            let goal = SingleGoalWorkout(activity: .swimming, location: .outdoor, goal: .distance(Double(cont), .meters))
            return WorkoutPlan(.goal(goal))
        }
        let wu = s.steps.first { $0.kind == .wu }
        let cd = s.steps.last { $0.kind == .cd }
        let middle = s.steps.filter { $0.kind != .wu && $0.kind != .cd }
        guard !middle.isEmpty else { return nil }

        let blocks: [IntervalBlock] = middle.map { st in
            var work = IntervalStep(.work)
            work.step.goal = .distance(Double(st.dist), .meters)
            work.step.displayName = stepName(st)
            var steps = [work]
            if st.rest > 0 {
                var rest = IntervalStep(.recovery)
                rest.step.goal = .time(Double(st.rest), .seconds)
                steps.append(rest)
            }
            return IntervalBlock(steps: steps, iterations: st.reps)
        }

        let workout = CustomWorkout(
            activity: .swimming,
            location: .indoor,
            displayName: s.title,
            warmup: wu.map { WorkoutStep(goal: .distance(Double($0.reps * $0.dist), .meters)) },
            blocks: blocks,
            cooldown: cd.map { WorkoutStep(goal: .distance(Double($0.reps * $0.dist), .meters)) }
        )
        return WorkoutPlan(.custom(workout))
    }

    /// Changes whenever what the watch would show for this swim changes.
    static func signature(_ s: Session) -> String {
        ([s.title, s.openWater ? "ow" : "pool", String(s.cont ?? 0)] + s.steps.map { "\($0.kind.rawValue)\($0.reps)x\($0.dist)\($0.zone.rawValue)r\($0.rest)\($0.label)" })
            .joined(separator: "|")
    }

    static func stepName(_ st: SetStep) -> String {
        if st.kind == .drill { return st.label.isEmpty ? "Drill" : st.label }
        return st.zone.name
    }
}

/// Keeps the Workout app on your watch in step with the plan: the next two weeks of swims are
/// scheduled for their days, and a swim that is changed, moved, skipped or done is updated or removed.
@Observable
final class WatchScheduler {
    private(set) var authorization: WorkoutScheduler.AuthorizationState = .notDetermined
    private(set) var message: String?
    private(set) var isSyncing = false
    private(set) var scheduledCount = 0

    private let autoKey = "autoSendToWatch"
    private let sigKey = "watchScheduleSignatures"

    var isSupported: Bool { WorkoutScheduler.isSupported }

    var autoSend: Bool {
        get { access(keyPath: \.autoSend); return UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }
        set { withMutation(keyPath: \.autoSend) { UserDefaults.standard.set(newValue, forKey: autoKey) } }
    }

    @MainActor
    func refresh() async {
        guard isSupported else { return }
        authorization = await WorkoutScheduler.shared.authorizationState
        scheduledCount = await WorkoutScheduler.shared.scheduledWorkouts.count
    }

    @MainActor
    func requestAccess() async {
        guard isSupported else { return }
        authorization = await WorkoutScheduler.shared.requestAuthorization()
    }

    /// Brings the watch's scheduled swims in line with `sessions`, the swims still to do in the next two weeks.
    /// Only days whose workout changed are touched. With `force`, every day is sent again.
    @MainActor
    func sync(_ sessions: [Session], pool: Int, force: Bool = false) async {
        guard isSupported, !isSyncing else { return }
        if authorization == .notDetermined { await requestAccess() }
        guard authorization == .authorized else {
            message = "Allow workout scheduling in Setup to send swims to your watch."
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        var wanted: [String: (plan: WorkoutPlan, sig: String, at: Date)] = [:]
        let limit = max(1, min(WorkoutScheduler.maxAllowedScheduledWorkoutCount, 14))
        for s in sessions.prefix(limit) {
            guard let plan = WatchWorkouts.plan(for: s, pool: pool) else { continue }
            wanted[Days.key(s.at)] = (plan, WatchWorkouts.signature(s), s.at)
        }

        var sigs = (UserDefaults.standard.dictionary(forKey: sigKey) as? [String: String]) ?? [:]
        var kept = Set<String>()
        for old in await WorkoutScheduler.shared.scheduledWorkouts {
            guard let d = Days.calendar.date(from: old.date) else { continue }
            let k = Days.key(d)
            if !force, let w = wanted[k], sigs[k] == w.sig, !kept.contains(k) {
                kept.insert(k)
            } else {
                await WorkoutScheduler.shared.remove(old.plan, at: old.date)
            }
        }
        var added = 0
        var newSigs: [String: String] = [:]
        for (k, w) in wanted {
            newSigs[k] = w.sig
            guard !kept.contains(k) else { continue }
            var when = Days.calendar.dateComponents([.year, .month, .day], from: w.at)
            when.hour = 6
            await WorkoutScheduler.shared.schedule(w.plan, at: when)
            added += 1
        }
        sigs = newSigs
        UserDefaults.standard.set(sigs, forKey: sigKey)
        scheduledCount = wanted.count
        if added > 0 || force {
            message = wanted.isEmpty ? "No swims to send in the next two weeks."
                : "Your watch has the next \(wanted.count) \(wanted.count == 1 ? "swim" : "swims")."
        }
    }

    /// Takes every scheduled swim off the watch.
    @MainActor
    func clear() async {
        guard isSupported, authorization == .authorized else { return }
        for old in await WorkoutScheduler.shared.scheduledWorkouts {
            await WorkoutScheduler.shared.remove(old.plan, at: old.date)
        }
        UserDefaults.standard.removeObject(forKey: sigKey)
        scheduledCount = 0
        message = "Removed the scheduled swims from your watch."
    }
}
