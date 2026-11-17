import Foundation
import HealthKit
import Observation

/// Reads swim workouts from Apple Health. The app only reads; your Apple Watch records the swims.
@Observable
final class HealthService {
    enum Status: Equatable {
        case unavailable
        case notConnected
        case connected
        case failed(String)
    }

    private(set) var status: Status
    private(set) var isSyncing = false
    private(set) var lastSync: Date?

    private let store = HKHealthStore()
    private let askedKey = "healthAccessRequested"

    init() {
        if !HKHealthStore.isHealthDataAvailable() {
            status = .unavailable
        } else {
            status = UserDefaults.standard.bool(forKey: askedKey) ? .connected : .notConnected
        }
    }

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceSwimming), HKQuantityType(.swimmingStrokeCount)]
    }

    /// Shows the Health permission sheet. Health never says whether read access was granted,
    /// so after this the app simply finds swims or finds none.
    @MainActor
    func connect() async {
        guard status != .unavailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: askedKey)
            status = .connected
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Reads swims from Health and hands them to the store.
    @MainActor
    func sync(into trainer: TrainerStore) async {
        guard status == .connected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let since = Days.add(min(trainer.plan.begin, trainer.today), -28)
            let swims = try await fetchSwims(since: since)
            trainer.ingest(swims)
            lastSync = Date()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func fetchSwims(since: Date) async throws -> [SwimRecord] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .swimming),
            HKQuery.predicateForSamples(withStart: since, end: nil)
        ])
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                                            limit: 120)
        let workouts = try await query.result(for: store)
        var out: [SwimRecord] = []
        for w in workouts { out.append(await record(for: w)) }
        return out
    }

    private func record(for w: HKWorkout) async -> SwimRecord {
        let distanceType = HKQuantityType(.distanceSwimming)
        var distance = w.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
        if distance == 0, let total = w.totalDistance { distance = total.doubleValue(for: .meter()) }

        let locationRaw = (w.metadata?[HKMetadataKeySwimmingLocationType] as? NSNumber)?.intValue
        let openWater = locationRaw == HKWorkoutSwimmingLocationType.openWater.rawValue
        let lapLength = (w.metadata?[HKMetadataKeyLapLength] as? HKQuantity)?.doubleValue(for: .meter())

        let events = w.workoutEvents ?? []
        let laps = events.filter { $0.type == .lap }.map(\.dateInterval)
        let segments = events.filter { $0.type == .segment }.map(\.dateInterval)

        var sets: [SwimSet] = []
        if let lapLength, !laps.isEmpty {
            sets = SwimSegmenter.sets(laps: laps, lapLength: lapLength)
        } else if !segments.isEmpty {
            let samples = (try? await distanceSamples(for: w)) ?? []
            sets = SwimSegmenter.sets(segments: segments, samples: samples)
        }

        return SwimRecord(id: w.uuid.uuidString, start: w.startDate, end: w.endDate, duration: w.duration,
                          distance: distance, openWater: openWater, lapLength: lapLength, sets: sets,
                          source: w.sourceRevision.source.name)
    }

    private func distanceSamples(for w: HKWorkout) async throws -> [(DateInterval, Double)] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.distanceSwimming), predicate: HKQuery.predicateForObjects(from: w))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await query.result(for: store)
        return samples.map { (DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)), $0.quantity.doubleValue(for: .meter())) }
    }
}
