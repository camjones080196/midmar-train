import Charts
import SwiftUI

struct PlanView: View {
    @Environment(TrainerStore.self) private var store
    @Environment(WatchScheduler.self) private var watch
    @State private var sending = false

    var body: some View {
        let plan = store.plan
        let km = Double(plan.weeks.reduce(0) { $0 + $1.metres }) / 1000
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(plan.weekCount) weeks, \(store.sessions.count) swims, \(Int(km.rounded())) km").font(.display(24))
                    Text("The long swim builds from \(Fmt.dist(plan.weeks.first?.long ?? 0)) to \(Fmt.dist(plan.peak)), with a lighter week and a time trial every fourth week.")
                        .font(.system(size: 15)).foregroundStyle(Palette.muted)
                    WeeklyDistanceChart().frame(height: 170)
                }
                .padding(.vertical, 6)
                Button {
                    sending = true
                    Task {
                        let w = store.currentWeek
                        let upcoming = store.sessions.filter {
                            let i = store.plan.weekIndex(of: $0.at)
                            return (i == w || i == w + 1) && $0.at >= store.today && !store.isDone($0.key) && !store.isSkipped($0.key) && !$0.isRace
                        }
                        _ = await watch.schedule(upcoming, pool: store.plan.pool)
                        sending = false
                    }
                } label: {
                    Label(sending ? "Sending…" : "Send this week and next to Apple Watch", systemImage: "applewatch")
                }
                .disabled(sending)
                if let m = watch.message { Text(m).font(.system(size: 13)).foregroundStyle(Palette.muted) }
            }
            ForEach(Array(plan.phases.enumerated()), id: \.offset) { pi, ph in
                Section {
                    ForEach(plan.weeks.filter { $0.phase == pi }) { w in
                        NavigationLink(value: WeekRoute(index: w.index)) { WeekRow(week: w) }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phase \(pi + 1) · \(ph.name)").font(.display(22)).foregroundStyle(Palette.ink).textCase(nil)
                        Text("\(ph.range) · \(ph.goal)").font(.system(size: 13)).foregroundStyle(Palette.muted).textCase(nil)
                    }
                }
            }
        }
        .navigationTitle("Plan")
    }
}

struct WeekRow: View {
    @Environment(TrainerStore.self) private var store
    let week: PlanWeek

    var body: some View {
        let ws = store.plan.weekStart(week.index)
        let list = store.sessions(inWeek: week.index)
        let done = list.filter { store.isDone($0.key) }.count
        HStack(spacing: 12) {
            Text("\(week.index + 1)").font(.display(30)).foregroundStyle(Palette.water).frame(width: 38)
                .overlay(alignment: .bottom) {
                    if week.index == store.currentWeek && store.hasStarted { Circle().fill(Palette.buoy).frame(width: 6, height: 6).offset(y: 8) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Days.short(ws)) to \(Days.short(Days.add(ws, 6)))").font(.system(size: 15, weight: .semibold))
                Text(week.focus).font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(done)/\(list.count)").font(.system(size: 15, weight: .semibold))
                Text("\(Fmt.num(store.plannedMetres(week: week.index))) m").font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            .monospacedDigit()
        }
    }
}

struct WeekView: View {
    @Environment(TrainerStore.self) private var store
    let index: Int

    var body: some View {
        ScrollView {
            WeekSection(index: index, onStep: { _ in }).padding(16)
        }
        .background(Palette.bg)
        .navigationTitle("Week \(index + 1)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WeeklyDistanceChart: View {
    @Environment(TrainerStore.self) private var store

    var body: some View {
        let weeks = store.plan.weeks
        Chart {
            ForEach(weeks) { w in
                BarMark(x: .value("Week", w.index + 1), yStart: .value("Start", 0), yEnd: .value("Planned", store.plannedMetres(week: w.index)), width: .ratio(0.7))
                    .foregroundStyle(Palette.line)
                let swum = store.swumMetres(week: w.index)
                if swum > 0 {
                    BarMark(x: .value("Week", w.index + 1), yStart: .value("Start", 0), yEnd: .value("Swum", swum), width: .ratio(0.7))
                        .foregroundStyle(Palette.water)
                }
            }
            if store.hasStarted {
                RuleMark(x: .value("This week", store.currentWeek + 1))
                    .foregroundStyle(Palette.buoy.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel { if let m = v.as(Int.self) { Text(m == 0 ? "0" : Fmt.dist(m)) } }
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
        .accessibilityLabel("Planned and swum distance for each week")
    }
}
