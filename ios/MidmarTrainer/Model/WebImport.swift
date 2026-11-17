import Foundation

/// Reads the data the web app copies with "Copy my data", so edits, ticks and times carry over.
enum WebImport {
    enum Failure: LocalizedError {
        case notWebData
        var errorDescription: String? { "That text is not from the web app. In the web app, open Setup and tap Copy my data, then paste here." }
    }

    struct Summary: Equatable {
        var done = 0, skipped = 0, moved = 0, edited = 0, trials = 0, nonstop = 0
        var text: String {
            "\(done) done, \(edited) edited, \(skipped) skipped, \(moved) moved, \(trials) timed swims and \(nonstop) non-stop swims."
        }
    }

    static func parse(_ text: String) throws -> (TrainerState, Summary) {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cfg = j["cfg"] as? [String: Any] else { throw Failure.notWebData }
        var st = TrainerState()
        var sum = Summary()

        var c = PlanConfig()
        if let v = cfg["start"] as? String, Days.isKey(v) { c.start = v }
        if let v = cfg["race"] as? String, Days.isKey(v) { c.race = v }
        if let v = int(cfg["level"]) { c.level = v }
        if let v = int(cfg["perWeek"]) { c.perWeek = v }
        if let v = cfg["days"] as? [Any] { c.days = v.compactMap(int) }
        if let v = int(cfg["pool"]) { c.pool = v }
        if let v = int(cfg["peak"]) { c.peak = v }
        c.setup = true
        st.config = c.normalized()

        let res = j["res"] as? [String: Any] ?? [:]
        for (k, v) in j["done"] as? [String: Any] ?? [:] {
            guard Days.isKey(k), let day = v as? String, Days.isKey(day) else { continue }
            let r = res[k] as? [String: Any] ?? [:]
            st.done[k] = DoneRecord(date: day, feel: min(5, max(0, int(r["feel"]) ?? 0)), time: max(0, int(r["t"]) ?? 0))
            sum.done += 1
        }
        for (k, v) in j["skip"] as? [String: Any] ?? [:] where Days.isKey(k) && (int(v) ?? 0) != 0 {
            st.skipped.insert(k); sum.skipped += 1
        }
        for (k, v) in j["moved"] as? [String: Any] ?? [:] {
            guard Days.isKey(k), let to = v as? String, Days.isKey(to) else { continue }
            st.moved[k] = to; sum.moved += 1
        }
        for (k, v) in j["edits"] as? [String: Any] ?? [:] {
            guard Days.isKey(k), let e = v as? [String: Any], let raw = e["steps"] as? [[String: Any]] else { continue }
            let steps: [SetStep] = raw.compactMap { x in
                guard let kind = (x["kind"] as? String).flatMap(StepKind.init), kind != .race,
                      let zone = (x["zone"] as? String).flatMap(Zone.init),
                      let reps = int(x["reps"]), let dist = int(x["dist"]), (1...60).contains(reps), (25...10000).contains(dist) else { return nil }
                return SetStep(kind, reps, dist, zone, rest: min(600, max(0, int(x["rest"]) ?? 0)), label: x["label"] as? String ?? "")
            }
            if steps.contains(where: { $0.kind == .main }) { st.edits[k] = steps; sum.edited += 1 }
        }
        for t in j["tt"] as? [[String: Any]] ?? [] {
            guard let d = t["date"] as? String, Days.isKey(d), let dist = int(t["dist"]), let secs = int(t["secs"]), dist > 0, secs > 0 else { continue }
            st.trials.append(TimeTrial(date: d, dist: dist, secs: secs)); sum.trials += 1
        }
        for l in j["log"] as? [[String: Any]] ?? [] {
            guard let d = l["date"] as? String, Days.isKey(d), let m = int(l["m"]), m > 0 else { continue }
            st.nonstop.append(NonStopSwim(date: d, metres: m, openWater: l["ow"] as? Bool ?? false)); sum.nonstop += 1
        }
        return (st, sum)
    }

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double, d.isFinite { return Int(d.rounded()) }
        if let s = v as? String { return Int(s) }
        return nil
    }
}
