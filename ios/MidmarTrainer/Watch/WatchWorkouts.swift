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

    static func stepName(_ st: SetStep) -> String {
        if st.kind == .drill { return st.label.isEmpty ? "Drill" : st.label }
        return st.zone.name
    }
}

/// Schedules workouts so they appear in the Workout app on the planned day.
@Observable
final class WatchScheduler {
    private(set) var authorization: WorkoutScheduler.AuthorizationState = .notDetermined
    private(set) var message: String?

    var isSupported: Bool { WorkoutScheduler.isSupported }

    @MainActor
    func refresh() async {
        guard isSupported else { return }
        authorization = await WorkoutScheduler.shared.authorizationState
    }

    @MainActor
    func requestAccess() async {
        guard isSupported else { return }
        authorization = await WorkoutScheduler.shared.requestAuthorization()
    }

    /// Schedules each session at 6:00 on its day, replacing anything this app scheduled for that day.
    @MainActor
    func schedule(_ sessions: [Session], pool: Int) async -> Int {
        guard isSupported else { message = "Scheduling needs an iPhone paired with an Apple Watch."; return 0 }
        if authorization != .authorized { await requestAccess() }
        guard authorization == .authorized else {
            message = "Allow workout scheduling in Setup to send swims to your watch."
            return 0
        }
        let existing = await WorkoutScheduler.shared.scheduledWorkouts
        var count = 0
        for s in sessions {
            guard let plan = WatchWorkouts.plan(for: s, pool: pool) else { continue }
            var when = Days.calendar.dateComponents([.year, .month, .day], from: s.at)
            when.hour = 6
            for old in existing where sameDay(old.date, when) {
                await WorkoutScheduler.shared.remove(old.plan, at: old.date)
            }
            await WorkoutScheduler.shared.schedule(plan, at: when)
            count += 1
        }
        message = count == 1 ? "Sent to your watch for \(Days.withWeekday(sessions[0].at))." : "Sent \(count) swims to your watch."
        return count
    }

    private func sameDay(_ a: DateComponents, _ b: DateComponents) -> Bool {
        a.year == b.year && a.month == b.month && a.day == b.day
    }
}
