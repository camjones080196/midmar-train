import Foundation

/// One swim workout read from Apple Health, reduced to what the plan needs.
struct SwimRecord: Identifiable, Hashable {
    let id: String
    let start: Date
    let end: Date
    let duration: TimeInterval
    /// Metres
    let distance: Double
    let openWater: Bool
    let lapLength: Double?
    /// Continuous swims between rests, in order.
    let sets: [SwimSet]
    let source: String

    var day: Date { Days.start(start) }
    var metres: Int { Int(distance.rounded()) }

    /// Seconds per 100 m over the whole workout, rests included.
    var pacePer100: Double? { distance > 0 ? duration / distance * 100 : nil }

    /// The longest distance swum without stopping, if it can be told.
    var longestNonStop: Int? {
        if let m = sets.map(\.distance).max() { return Int(m.rounded()) }
        return openWater && distance > 0 ? metres : nil
    }
}

struct SwimSet: Hashable {
    let distance: Double
    let duration: TimeInterval
}

enum SwimSegmenter {
    /// Splits a pool swim into continuous sets from its lengths. A gap longer than `restGap`
    /// seconds between two lengths counts as a rest.
    static func sets(laps: [DateInterval], lapLength: Double, restGap: TimeInterval = 10) -> [SwimSet] {
        guard lapLength > 0, !laps.isEmpty else { return [] }
        let sorted = laps.sorted { $0.start < $1.start }
        var out: [SwimSet] = []
        var first = sorted[0], last = sorted[0], count = 1
        for lap in sorted.dropFirst() {
            if lap.start.timeIntervalSince(last.end) > restGap {
                out.append(SwimSet(distance: Double(count) * lapLength, duration: last.end.timeIntervalSince(first.start)))
                first = lap
                count = 0
            }
            last = lap
            count += 1
        }
        out.append(SwimSet(distance: Double(count) * lapLength, duration: last.end.timeIntervalSince(first.start)))
        return out
    }

    /// Sets from segment intervals, adding up the distance samples that fall inside each one.
    static func sets(segments: [DateInterval], samples: [(DateInterval, Double)]) -> [SwimSet] {
        segments.sorted { $0.start < $1.start }.compactMap { seg in
            let d = samples.filter { seg.contains($0.0.start.addingTimeInterval($0.0.duration / 2)) }.reduce(0) { $0 + $1.1 }
            return d > 0 ? SwimSet(distance: d, duration: seg.duration) : nil
        }
    }
}

enum SwimMatcher {
    /// Pairs Health swims with planned sessions that are not done, skipped or already linked.
    /// A swim matches a session on the same day first, then one a day or two either side,
    /// preferring a session the swim came after. Returns workout id to session key.
    static func match(swims: [SwimRecord], sessions: [Session], state: TrainerState, begin: Date, race: Date) -> [String: String] {
        var taken = Set(state.done.keys).union(state.skipped).union(state.links.values)
        var out: [String: String] = [:]
        for swim in swims.sorted(by: { $0.start < $1.start }) {
            guard state.links[swim.id] == nil, !state.ignored.contains(swim.id),
                  swim.day >= begin, swim.day <= race else { continue }
            let best = sessions
                .filter { !taken.contains($0.key) && abs(Days.between($0.at, swim.day)) <= 2 }
                .min { score(Days.between($0.at, swim.day)) < score(Days.between($1.at, swim.day)) }
            if let best {
                out[swim.id] = best.key
                taken.insert(best.key)
            }
        }
        return out
    }

    /// 0 same day, 1 the day after the session, 2 the day before, and so on.
    static func score(_ d: Int) -> Int { d == 0 ? 0 : d > 0 ? 2 * d - 1 : -2 * d }

    /// The time for a timed effort of `distance` metres inside a swim: the fastest set within one
    /// length of that distance, scaled to exactly `distance`.
    static func trialTime(in swim: SwimRecord, distance: Int) -> Int? {
        let tol = max(swim.lapLength ?? 25, 25) + 1
        let near = swim.sets.filter { abs($0.distance - Double(distance)) <= tol && $0.distance > 0 && $0.duration > 0 }
        guard let fastest = near.min(by: { $0.duration / $0.distance < $1.duration / $1.distance }) else { return nil }
        return Int((fastest.duration / fastest.distance * Double(distance)).rounded())
    }
}
