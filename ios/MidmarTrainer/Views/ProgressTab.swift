import Charts
import SwiftUI

struct ProgressTab: View {
    @Environment(TrainerStore.self) private var store
    @Environment(HealthService.self) private var health
    @State private var showNonStop = false

    var body: some View {
        let done = store.sessions.filter { store.isDone($0.key) }
        let metres = done.reduce(0) { $0 + store.swum($1) }
        let best = store.state.bestNonStop
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 0) {
                    stat("\(done.count)", "/\(store.sessions.count)", "Swims done")
                    Divider()
                    stat(metres >= 10000 ? String(format: "%.1f", Double(metres) / 1000) : Fmt.num(metres), metres >= 10000 ? " km" : " m", "From the plan")
                    Divider()
                    stat(best > 0 ? Fmt.num(best) : "–", best > 0 ? " m" : "", "Best non-stop")
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))

                PacesCard()

                Card {
                    Text("Weekly distance").font(.display(22))
                    WeeklyDistanceChart().frame(height: 170)
                }

                Card {
                    HStack {
                        Text("Longest non-stop swims").font(.display(22))
                        Spacer()
                        Button { showNonStop = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a non-stop swim")
                    }
                    NonStopChart().frame(height: 200)
                    if store.state.nonstop.isEmpty {
                        Text("Nothing logged yet. Your watch adds your longest continuous set from each swim, or add one with +.")
                            .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    }
                }

                MilestonesCard()

                if !store.swims.isEmpty || health.status == .connected { HealthSwimsCard() }
            }
            .padding(16)
        }
        .background(Palette.bg)
        .navigationTitle("Progress")
        .refreshable { await health.sync(into: store) }
        .sheet(isPresented: $showNonStop) { NonStopSheet() }
    }

    private func stat(_ v: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(v).font(.display(32)) + Text(unit).font(.display(16, weight: .semibold)).foregroundColor(Palette.muted))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

struct PacesCard: View {
    @Environment(TrainerStore.self) private var store
    @State private var dist = 100
    @State private var time = ""
    @State private var date = Date()
    @State private var error: String?

    var body: some View {
        let thr = store.thr
        Card {
            Text("Your paces").font(.display(22))
            if let thr, let range = Paces.raceRange(thr: thr), let last = store.state.latestTrial {
                (Text("\(Int((range.lo / 60).rounded())) to \(Int((range.hi / 60).rounded()))").font(.display(44))
                 + Text(" min predicted for the Mile").font(.display(20, weight: .semibold)).foregroundColor(Palette.muted))
                Text("From your \(last.dist) m in \(Fmt.time(Double(last.secs))) on \(Days.date(last.date).map(Days.short) ?? last.date)\(last.source == "watch" ? ", timed by your watch" : ""). Open water is usually slower than the pool, so the range allows for that.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
                VStack(spacing: 0) {
                    ForEach(Zone.editable) { z in
                        HStack(alignment: .firstTextBaseline) {
                            EffortPips(level: z.level)
                            Text(z.name).font(.system(size: 15, weight: .semibold)).frame(width: 82, alignment: .leading)
                            Text(z.cue).font(.system(size: 13)).foregroundStyle(Palette.muted)
                            Spacer()
                            Text(Fmt.time(thr * z.factor)).font(.display(22)).monospacedDigit()
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
                    }
                }
                Text("Target time per 100 m. Every set in your plan uses these.").font(.system(size: 13)).foregroundStyle(Palette.muted)
            } else {
                Text("Swim 100, 200 or 400 m as fast as you can hold evenly, time it, and add it here. The plan then shows a target time for every set and predicts your race time. Time-trial swims from your watch fill this in for you.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
            }

            HStack(spacing: 10) {
                Picker("Distance", selection: $dist) {
                    ForEach([100, 200, 400, 800, 1500], id: \.self) { Text("\(Fmt.num($0)) m").tag($0) }
                }
                .pickerStyle(.menu)
                TextField("e.g. 2:10", text: $time).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
            }
            if let error { Text(error).font(.system(size: 14)).foregroundStyle(Palette.buoy) }
            Button("Add timed swim", action: add).buttonStyle(GhostButtonStyle())

            ForEach(store.state.trials.sorted { $0.date > $1.date }.prefix(8)) { t in
                HStack {
                    Text("\(Fmt.num(t.dist)) m in \(Fmt.time(Double(t.secs)))").font(.display(20)).monospacedDigit()
                    Text(Days.date(t.date).map(Days.withWeekday) ?? t.date).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    if t.source == "watch" { Image(systemName: "applewatch").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                    Spacer()
                    Button("Remove") { store.deleteTrial(t.id) }.font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func add() {
        guard let secs = Fmt.parseTime(time), (40...600).contains(Double(secs) / Double(dist) * 100) else {
            error = "Enter the time as minutes and seconds, like 2:10."
            return
        }
        store.addTrial(dist: dist, secs: secs, date: date)
        error = nil
        time = ""
    }
}

struct NonStopChart: View {
    @Environment(TrainerStore.self) private var store

    var body: some View {
        let items = store.state.nonstop.compactMap { n in Days.date(n.date).map { (n, $0) } }.sorted { $0.1 < $1.1 }
        let top = max(2000, store.plan.peak)
        Chart {
            ForEach(items, id: \.0.id) { n, d in
                LineMark(x: .value("Date", d), y: .value("Metres", n.metres)).foregroundStyle(Palette.water)
                PointMark(x: .value("Date", d), y: .value("Metres", n.metres))
                    .foregroundStyle(n.openWater ? Palette.buoy : Palette.water)
            }
            RuleMark(y: .value("Race", Catalog.raceDistance))
                .foregroundStyle(Palette.buoy)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Race 1.6 km").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.buoy)
                }
        }
        .chartXScale(domain: store.plan.begin...store.plan.race)
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(stride(from: 0, through: top, by: 500))) { v in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel { if let m = v.as(Int.self) { Text(m == 0 ? "0" : Fmt.dist(m)) } }
            }
        }
        .accessibilityLabel("Longest non-stop swims over time, with the 1.6 km race distance marked")
    }
}

struct MilestonesCard: View {
    @Environment(TrainerStore.self) private var store

    var body: some View {
        let best = store.state.bestNonStop
        let ow = store.state.nonstop.filter(\.openWater).count
        Card {
            Text("Milestones").font(.display(22))
            ForEach(store.plan.milestones, id: \.metres) { m in
                row(ok: best >= m.metres, "\(Fmt.num(m.metres)) m non-stop\(m.metres == Catalog.raceDistance ? " (race distance)" : "")",
                    "By \(Days.short(Days.add(store.plan.weekStart(m.week), 6)))")
            }
            row(ok: ow >= Catalog.openWaterGoal, "Open-water swims", "\(min(ow, 99)) of \(Catalog.openWaterGoal)")
        }
    }

    private func row(ok: Bool, _ title: String, _ trailing: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(ok ? Palette.water : Palette.line)
            Text(title)
            Spacer()
            Text(trailing).font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 3)
    }
}

struct HealthSwimsCard: View {
    @Environment(TrainerStore.self) private var store
    @Environment(HealthService.self) private var health

    var body: some View {
        Card {
            HStack {
                Text("From Apple Health").font(.display(22))
                Spacer()
                if health.isSyncing { ProgressView() }
            }
            if store.swims.isEmpty {
                Text("No swims found yet. Record a Pool Swim or Open Water Swim on your watch and it shows up here.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
            }
            ForEach(store.swims.prefix(10)) { sw in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(Fmt.num(sw.metres)) m").font(.display(20)).monospacedDigit()
                        Text(sw.openWater ? "open water" : "pool").font(.system(size: 13)).foregroundStyle(Palette.muted)
                        Spacer()
                        Text(Days.withWeekday(sw.day)).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text([Fmt.time(sw.duration),
                              sw.longestNonStop.map { "longest non-stop \(Fmt.num($0)) m" },
                              store.linkedSession(for: sw.id).map { "counted for \($0.title), \(Days.short($0.at))" }
                                ?? (store.state.ignored.contains(sw.id) ? "not counted" : nil)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                        Spacer()
                        Menu {
                            ForEach(store.sessionCandidates(for: sw)) { s in
                                Button {
                                    store.link(sw.id, to: s.key)
                                } label: {
                                    Text("\(s.title), \(Days.withWeekday(s.at))\(store.linkedSession(for: sw.id)?.key == s.key ? " ✓" : store.isDone(s.key) ? " (done)" : "")")
                                }
                            }
                            Divider()
                            Button("Don't count it", role: .destructive) { store.link(sw.id, to: nil) }
                        } label: {
                            Label("Link", systemImage: "link").font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if let t = health.lastSync {
                Text("Checked \(t.formatted(date: .omitted, time: .shortened)). Pull down to check again.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }
    }
}

struct NonStopSheet: View {
    @Environment(TrainerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var metres = 400
    @State private var date = Date()
    @State private var openWater = false

    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(Fmt.num(metres)) m", value: $metres, in: 25...10000, step: 25)
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                Toggle("Swam in open water", isOn: $openWater)
            }
            .navigationTitle("Non-stop swim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { store.addNonStop(metres: metres, date: date, openWater: openWater); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
