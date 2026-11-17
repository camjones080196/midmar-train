import SwiftUI

struct TodayView: View {
    @Environment(TrainerStore.self) private var store
    @Environment(HealthService.self) private var health
    @Binding var tab: AppTab
    @State private var week: Int?

    var body: some View {
        let shown = week ?? store.currentWeek
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CountdownHeader()
                LaneRope()
                nudges
                if let adj = store.latestAdjustment { AdjustmentCard(change: adj) }
                if let w = store.plan.warning { Card { Text("Behind the build").font(.display(22)); Text(w).foregroundStyle(Palette.muted) } }
                if !store.unmatchedSwims.isEmpty { UnmatchedSwimsCard() }
                NextSwimCard()
                WeekSection(index: shown, onStep: { week = min(store.plan.weekCount - 1, max(0, shown + $0)) })
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .navigationTitle("Today")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await health.sync(into: store) }
    }

    @ViewBuilder private var nudges: some View {
        if !store.state.config.setup {
            Card {
                Text("Set up your coach").font(.display(22))
                Text("Tell the plan how far you can swim now, a recent time if you have one, and which days you train. It builds every session from that.")
                    .foregroundStyle(Palette.muted)
                Button("Build my plan") { tab = .setup }.buttonStyle(PrimaryButtonStyle())
            }
        } else if store.isStale {
            Card {
                Text("Pick up where you are").font(.display(22))
                Text("No swims are ticked in the last two weeks. Re-plan from today in Setup so the sessions match your fitness now.")
                    .foregroundStyle(Palette.muted)
                Button("Open Setup") { tab = .setup }.buttonStyle(GhostButtonStyle())
            }
        }
        if health.status == .notConnected {
            Card {
                Text("Connect Apple Health").font(.display(22))
                Text("Swims you record on your Apple Watch tick off the plan, fill in your times and track your longest non-stop swim.")
                    .foregroundStyle(Palette.muted)
                Button("Connect") {
                    Task { await health.connect(); await health.sync(into: store) }
                }.buttonStyle(PrimaryButtonStyle())
            }
        } else if store.thr == nil && store.state.config.setup {
            Card {
                Text("Get your target paces").font(.display(22))
                Text("Add one timed swim and every set shows a target time. Your Apple Watch fills this in when you swim a time trial.")
                    .foregroundStyle(Palette.muted)
                Button("Add a timed swim") { tab = .progress }.buttonStyle(GhostButtonStyle())
            }
        }
    }
}

struct CountdownHeader: View {
    @Environment(TrainerStore.self) private var store

    var body: some View {
        let d = Days.between(store.today, store.plan.race)
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Midmar Mile · \(Days.withYear(store.plan.race))")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(d > 0 ? Fmt.num(d) : d == 0 ? "Today" : "Done").font(.display(60)).monospacedDigit()
                    Text(d > 1 ? "days to go" : d == 1 ? "day to go" : d == 0 ? "is race day" : "race complete")
                        .font(.display(22, weight: .semibold)).foregroundStyle(Palette.muted)
                }
            }
            Spacer()
            Text(store.hasStarted ? "Week \(store.currentWeek + 1) of \(store.plan.weekCount)" : "Plan starts\n\(Days.withWeekday(store.plan.begin))")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.muted).multilineTextAlignment(.trailing)
        }
        .padding(.top, 8)
    }
}

struct NextSwimCard: View {
    @Environment(TrainerStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let next = store.nextUp() {
                let s = next.session
                Eyebrow(text: next.label, color: Palette.poolMuted)
                Text(s.title).font(.display(44)).foregroundStyle(Palette.poolInk)
                TypeChip(type: s.type, onPool: true)
                Text("\(Fmt.num(s.metres)) m · about \(Fmt.minutes(Paces.estimate(s, thr: store.thr)))")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.poolMuted)
                VStack(spacing: 0) {
                    ForEach(s.steps.filter { $0.kind != .wu && $0.kind != .cd }) { st in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(st.reps > 1 ? "\(st.reps) × " : "")\(Fmt.num(st.dist)) m").font(.display(26)).monospacedDigit()
                                .foregroundStyle(Palette.poolInk)
                            Text(st.kind == .drill ? st.label : st.zone.name + (st.label.isEmpty ? "" : ", \(st.label)"))
                                .font(.system(size: 14)).foregroundStyle(Palette.poolMuted)
                            Spacer()
                            if st.rest > 0 { Text("rest \(st.rest) s").font(.system(size: 13)).foregroundStyle(Palette.poolMuted) }
                        }
                        .padding(.vertical, 9)
                        .overlay(alignment: .top) { Rectangle().fill(Palette.poolLine).frame(height: 1) }
                    }
                }
                NavigationLink(value: s.key) {
                    Text("View workout")
                }.buttonStyle(PrimaryButtonStyle(fill: Palette.pop, text: Palette.onPop))
                if !s.isRace {
                    Button("Skip this swim") { store.skip(s.key) }
                        .font(.system(size: 15)).underline().foregroundStyle(Palette.poolMuted)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Eyebrow(text: "Plan complete", color: Palette.poolMuted)
                Text("Every swim is ticked").font(.display(40)).foregroundStyle(Palette.poolInk)
                Text("Open Setup to build your next plan.").foregroundStyle(Palette.poolMuted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.pool, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct WeekSection: View {
    @Environment(TrainerStore.self) private var store
    let index: Int
    let onStep: (Int) -> Void

    var body: some View {
        let w = store.plan.weeks[index]
        let start = store.plan.weekStart(index)
        let list = store.sessions(inWeek: index)
        let planned = store.plannedMetres(week: index), swum = store.swumMetres(week: index)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { onStep(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(index == 0)
                Spacer()
                VStack(spacing: 2) {
                    Eyebrow(text: "Phase \(w.phase + 1) · \(store.plan.phases[w.phase].name)", color: Palette.water)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Week \(index + 1)").font(.display(34))
                        Text("of \(store.plan.weekCount)").font(.display(18, weight: .semibold)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer()
                Button { onStep(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(index == store.plan.weekCount - 1)
            }
            .buttonStyle(.bordered)
            Text(w.focus).font(.system(size: 15)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)

            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    let d = Days.add(start, i)
                    DayCell(date: d, session: list.first { Days.start($0.at) == d })
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(swum), total: Double(max(planned, 1))).tint(Palette.water)
                Text("\(Fmt.num(swum)) of \(Fmt.num(planned)) m swum this week").font(.system(size: 13)).foregroundStyle(Palette.muted).monospacedDigit()
            }

            ForEach(list) { s in SessionRow(session: s) }
        }
    }
}

struct DayCell: View {
    @Environment(TrainerStore.self) private var store
    let date: Date
    let session: Session?

    var body: some View {
        let isToday = date == store.today
        let content = VStack(spacing: 2) {
            Text(Days.dow[Days.weekday(date)].uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
            Text("\(Days.dayNumber(date))").font(.display(22)).monospacedDigit().foregroundStyle(Palette.ink)
            Circle()
                .strokeBorder(session?.type.color ?? .clear, style: StrokeStyle(lineWidth: 2, dash: session.map { store.isSkipped($0.key) } == true ? [2, 2] : []))
                .background(Circle().fill(session.map { store.isDone($0.key) } == true ? session!.type.color : .clear))
                .frame(width: 9, height: 9)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(session != nil ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isToday ? Palette.ink : session != nil ? Palette.line : .clear))

        if let s = session {
            NavigationLink(value: s.key) { content }.buttonStyle(.plain)
                .accessibilityLabel("\(Days.withWeekday(date)), \(s.title)\(store.isDone(s.key) ? ", done" : "")")
        } else {
            content
        }
    }
}

struct SessionRow: View {
    @Environment(TrainerStore.self) private var store
    let session: Session

    var body: some View {
        let s = session
        let done = store.isDone(s.key), skipped = store.isSkipped(s.key), missed = store.isMissed(s)
        NavigationLink(value: s.key) {
            HStack(spacing: 12) {
                Rectangle().fill(s.type.color).frame(width: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.display(22)).foregroundStyle(Palette.ink)
                    Text("\(Days.withWeekday(s.at)) · \(Fmt.num(s.metres)) m · about \(Fmt.minutes(Paces.estimate(s, thr: store.thr)))\(s.edited ? " · edited" : "")\(s.isMoved ? " · moved" : "")")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).monospacedDigit()
                }
                .opacity(skipped ? 0.5 : 1)
                Spacer()
                Group {
                    if done {
                        Label(store.state.done[s.key]?.source == .health ? "Watch" : "Done", systemImage: "checkmark").foregroundStyle(Palette.water)
                    } else if skipped {
                        Text("Skipped").foregroundStyle(Palette.muted)
                    } else if missed {
                        Text("Missed").foregroundStyle(Palette.buoy)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.muted).padding(.trailing, 12)
            }
            .frame(minHeight: 64)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
        }
        .buttonStyle(.plain)
    }
}

/// Swims from Health that were not matched to a session, with a way to count them.
struct UnmatchedSwimsCard: View {
    @Environment(TrainerStore.self) private var store

    var body: some View {
        Card {
            Text("Swims to sort").font(.display(22))
            Text("These swims from your watch did not land on a planned day. Count each for a session, or leave it out.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted)
            ForEach(store.unmatchedSwims.prefix(4)) { sw in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Fmt.num(sw.metres)) m \(sw.openWater ? "open water" : "pool")").font(.system(size: 16, weight: .semibold))
                        Text("\(Days.withWeekday(sw.day)) · \(Fmt.time(sw.duration))").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Menu("Count it") {
                        ForEach(store.sessionCandidates(for: sw)) { s in
                            Button("\(s.title), \(Days.withWeekday(s.at))\(store.isDone(s.key) ? " (done)" : "")") { store.link(sw.id, to: s.key) }
                        }
                        Divider()
                        Button("Don't count it", role: .destructive) { store.link(sw.id, to: nil) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// Tells the swimmer what the coach changed and why.
struct AdjustmentCard: View {
    @Environment(TrainerStore.self) private var store
    let change: Rebase

    var body: some View {
        let w = store.plan.weeks[min(change.week, store.plan.weekCount - 1)]
        Card {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Palette.water)
                Eyebrow(text: "Plan adjusted · from week \(change.week + 1)", color: Palette.water)
            }
            Text(change.reason)
            Text("Week \(change.week + 1)'s long swim is now \(Fmt.dist(w.long)), and the weeks after build from there to reach your longest swim before the taper.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.water))
    }
}
