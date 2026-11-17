import SwiftUI
import WorkoutKit

struct SessionDetailView: View {
    @Environment(TrainerStore.self) private var store
    @Environment(WatchScheduler.self) private var watch
    let key: String

    @State private var showFinish = false
    @State private var showEdit = false
    @State private var showMove = false
    @State private var showLink = false
    @State private var showWatchPreview = false
    @State private var watchPlan: WorkoutPlan?

    var body: some View {
        if let s = store.session(key) {
            content(s)
        } else {
            ContentUnavailableView("Swim not found", systemImage: "figure.pool.swim",
                                   description: Text("The plan changed and this swim is no longer in it."))
        }
    }

    private func content(_ s: Session) -> some View {
        let done = store.state.done[s.key]
        let thr = store.thr
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TypeChip(type: s.type)
                    Text(s.title).font(.display(44))
                    Text("\(Days.withWeekday(s.at)) · week \(store.plan.weekIndex(of: s.at) + 1) of \(store.plan.weekCount)\(s.isMoved ? " · moved from \(Days.withWeekday(s.date))" : "")")
                        .foregroundStyle(Palette.muted)
                }

                facts(s, thr: thr)

                Text(s.type.why).foregroundStyle(Palette.muted)

                VStack(spacing: 0) {
                    ForEach(s.steps) { st in StepRow(step: st, type: s.type, thr: thr) }
                }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))

                if !s.note.isEmpty { Text(s.note).font(.system(size: 14)).foregroundStyle(Palette.muted) }
                if s.edited { Text("You edited this swim. Use Edit swim to change it again or go back to the planned sets.").font(.system(size: 14)).foregroundStyle(Palette.muted) }

                if let done {
                    ResultCard(session: s, record: done, onEdit: { showFinish = true }, onEditSets: { showEdit = true }, onLink: { showLink = true })
                } else if store.isSkipped(s.key) {
                    Card {
                        Text("You skipped this swim. It does not count as missed.").foregroundStyle(Palette.muted)
                        Button("Bring it back") { store.unskip(s.key) }.buttonStyle(GhostButtonStyle())
                    }
                } else {
                    actions(s)
                }
            }
            .padding(16)
        }
        .background(Palette.bg)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFinish) { FinishSheet(session: s) }
        .sheet(isPresented: $showEdit) { EditSessionView(session: s) }
        .sheet(isPresented: $showMove) { MoveSheet(session: s) }
        .sheet(isPresented: $showLink) { LinkSwimSheet(session: s) }
        .workoutPreview(watchPlan ?? WorkoutPlan(.goal(SingleGoalWorkout(activity: .swimming, location: .indoor, goal: .open))), isPresented: $showWatchPreview)
    }

    private func facts(_ s: Session, thr: Double?) -> some View {
        let ks = s.keyStep
        let pace = ks.flatMap { Paces.target(SetStep(.main, 1, 100, $0.zone), thr: thr) }
        return HStack(spacing: 0) {
            fact(Fmt.num(s.metres) + " m", s.isRace ? "open water" : "\(s.metres / store.plan.pool) lengths")
            Divider()
            fact(Fmt.minutes(Paces.estimate(s, thr: thr)), "estimated")
            Divider()
            if let pace, let ks { fact(Fmt.time(pace), "\(ks.zone.name.lowercased()) pace per 100 m") } else { fact(ks?.zone.name ?? "Easy", "main effort") }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.display(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder private func actions(_ s: Session) -> some View {
        VStack(spacing: 10) {
            if !s.isRace {
                Button {
                    watchPlan = WatchWorkouts.plan(for: s, pool: store.plan.pool)
                    showWatchPreview = watchPlan != nil
                } label: { Label("Send to Apple Watch", systemImage: "applewatch") }
                .buttonStyle(PrimaryButtonStyle())
            }
            Button("Mark as done") { showFinish = true }
                .buttonStyle(s.isRace ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(GhostButtonStyle()))
            Button { showLink = true } label: { Label("Link a swim from Apple Health", systemImage: "link") }
                .buttonStyle(GhostButtonStyle())
            if !s.isRace {
                HStack(spacing: 10) {
                    Button("Edit swim") { showEdit = true }.buttonStyle(GhostButtonStyle())
                    Button("Move") { showMove = true }.buttonStyle(GhostButtonStyle())
                    Button("Skip") { store.skip(s.key) }.buttonStyle(GhostButtonStyle())
                }
                Text("Send to Apple Watch adds this workout to the Workout app, with each set as a step and your rests timed. When you finish, the swim comes back from Apple Health and ticks this off.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
        }
    }
}

/// Type-erases two button styles so one button can switch between them.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct StepRow: View {
    let step: SetStep
    let type: SessionType
    let thr: Double?

    var body: some View {
        let st = step
        HStack(spacing: 0) {
            Rectangle().fill(st.kind == .main || st.kind == .race ? type.color : .clear).frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: st.kind.title)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(st.reps > 1 ? "\(st.reps) × " : "")\(Fmt.num(st.dist)) m")
                        .font(.display(st.kind == .wu || st.kind == .cd ? 22 : 28)).monospacedDigit()
                    if !st.label.isEmpty { Text(st.label).font(.system(size: 14)).foregroundStyle(Palette.muted) }
                }
                HStack(spacing: 8) {
                    EffortPips(level: st.zone.level)
                    Text(st.zone.name).font(.system(size: 14, weight: .semibold))
                    Text(target).font(.system(size: 14)).foregroundStyle(Palette.muted).monospacedDigit()
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1).opacity(0.9) }
    }

    private var target: String {
        var parts: [String] = []
        if st.zone == .max {
            parts.append(st.zone.cue)
        } else if let t = Paces.target(st, thr: thr), let p = Paces.pace(st.zone, thr: thr) {
            parts.append(Fmt.time(t) + (st.reps > 1 ? " each" : ""))
            if st.dist != 100 { parts.append("\(Fmt.time(p)) per 100 m") }
        } else {
            parts.append(st.zone.cue)
        }
        if st.rest > 0 { parts.append("rest \(st.rest) s") }
        return parts.joined(separator: " · ")
    }

    private var st: SetStep { step }
}

struct ResultCard: View {
    @Environment(TrainerStore.self) private var store
    let session: Session
    let record: DoneRecord
    let onEdit: () -> Void
    let onEditSets: () -> Void
    let onLink: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if record.time > 0 { Text(Fmt.time(Double(record.time))).font(.display(32)).monospacedDigit() }
                Text("\(Fmt.num(store.swum(session))) m").font(.display(record.time > 0 ? 22 : 32)).monospacedDigit()
                    .foregroundStyle(record.time > 0 ? Palette.muted : Palette.ink)
            }
            Text(summary).foregroundStyle(Palette.muted)
            if let sw = store.swim(for: session.key) {
                Text("Apple Watch: \(Fmt.num(sw.metres)) m \(sw.openWater ? "open water" : "pool")\(sw.pacePer100.map { ", \(Fmt.time($0)) per 100 m with rests" } ?? "")")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
                if !sw.sets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(sw.sets.enumerated()), id: \.offset) { _, set in
                                Text("\(Fmt.num(Int(set.distance))) m \(Fmt.time(set.duration))")
                                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Palette.bg, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line))
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Edit result", action: onEdit).buttonStyle(GhostButtonStyle())
                Button("Edit sets", action: onEditSets).buttonStyle(GhostButtonStyle())
            }
            Button { onLink() } label: {
                Label(record.workoutID == nil ? "Link a swim from Apple Health" : "Change the linked swim", systemImage: "link")
            }
            .buttonStyle(GhostButtonStyle())
            HStack {
                if record.workoutID != nil { Button("Unlink swim") { store.unlinkSwim(from: session.key) } }
                Spacer()
                Button("Mark as not done") { store.undo(session.key) }
            }
            .font(.system(size: 15)).foregroundStyle(Palette.muted)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.water))
    }

    private var summary: String {
        var bits = [record.source == .health ? "From Apple Watch on \(Days.date(record.date).map(Days.short) ?? record.date)" : "Done on \(Days.date(record.date).map(Days.short) ?? record.date)"]
        if record.feel > 0 { bits.append("felt \(Catalog.feel[record.feel - 1].lowercased())") }
        return bits.joined(separator: " · ")
    }
}

struct FinishSheet: View {
    @Environment(TrainerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: Session

    @State private var feel = 3
    @State private var time = ""
    @State private var trial = ""
    @State private var nonStop = true
    @State private var openWater = false
    @State private var swumOn = Date()
    @State private var asPlanned = true
    @State private var distance = 0
    @State private var error: String?

    private var existing: DoneRecord? { store.state.done[session.key] }

    var body: some View {
        NavigationStack {
            Form {
                Section("How did it feel?") {
                    Picker("Feel", selection: $feel) {
                        ForEach(1...5, id: \.self) { Text(Catalog.feel[$0 - 1]).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let d = session.tt, existing == nil {
                    Section {
                        TextField("e.g. 4:30", text: $trial).keyboardType(.numbersAndPunctuation)
                    } header: { Text("Your time for the \(d) m trial") } footer: { Text("Minutes and seconds. This sets your target paces.") }
                }
                Section(session.isRace ? "Your race time" : "Total time (optional)") {
                    TextField(session.isRace ? "e.g. 42:30" : "e.g. 38:00", text: $time).keyboardType(.numbersAndPunctuation)
                }
                if let c = session.cont, existing == nil {
                    Section {
                        Toggle("I swam the \(Fmt.num(c)) m without stopping", isOn: $nonStop)
                        Toggle("It was in open water", isOn: $openWater)
                    }
                }
                if existing != nil {
                    Section {
                        DatePicker("Swum on", selection: $swumOn, in: ...Date(), displayedComponents: .date)
                        Toggle("Swam it as planned (\(Fmt.num(session.metres)) m)", isOn: $asPlanned)
                        if !asPlanned {
                            Stepper("Distance: \(Fmt.num(distance)) m", value: $distance, in: 0...10000, step: store.plan.pool)
                        }
                    } footer: {
                        Text("To change the sets themselves, use Edit sets on the workout.")
                    }
                }
                if let error { Text(error).foregroundStyle(Palette.buoy) }
            }
            .navigationTitle(existing == nil ? "Mark as done" : "Edit result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                if let existing {
                    feel = max(1, existing.feel == 0 ? 3 : existing.feel)
                    time = existing.time > 0 ? Fmt.time(Double(existing.time)) : ""
                    swumOn = Days.date(existing.date) ?? Date()
                    asPlanned = existing.distance == nil || existing.distance == session.metres
                    distance = existing.distance ?? session.metres
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        var trialSecs: Int?
        if let d = session.tt, existing == nil, !trial.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let v = Fmt.parseTime(trial), (40...600).contains(Double(v) / Double(d) * 100) else {
                error = "Enter your trial time as minutes and seconds, like 4:30."
                return
            }
            trialSecs = v
        }
        var secs = 0
        if !time.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let v = Fmt.parseTime(time), v > 0 else {
                error = "Enter the time as minutes and seconds, like 38:00."
                return
            }
            secs = v
        }
        if existing != nil {
            store.updateResult(session.key, feel: feel, time: time.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : secs,
                               date: swumOn, distance: asPlanned ? nil : distance)
        } else {
            store.markDone(session.key, feel: feel, time: secs, trialSeconds: trialSecs, nonStop: session.cont != nil && nonStop, openWater: openWater)
        }
        dismiss()
    }
}

struct MoveSheet: View {
    @Environment(TrainerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var day = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $day, in: store.plan.begin...Days.add(store.plan.race, -1), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text(store.canMove(session.key, to: day) || Days.start(day) == Days.start(session.at)
                         ? "Planned for \(Days.withWeekday(session.date))."
                         : "There is already a swim on \(Days.withWeekday(day)). Move that one first, or pick another day.")
                }
                if session.isMoved {
                    Button("Back to \(Days.withWeekday(session.date))") { store.move(session.key, to: nil); dismiss() }
                }
            }
            .navigationTitle("Move swim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { store.move(session.key, to: day); dismiss() }
                        .disabled(!store.canMove(session.key, to: day))
                }
            }
            .onAppear { day = session.at }
        }
    }
}

struct EditSessionView: View {
    @Environment(TrainerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var steps: [SetStep] = []
    @State private var error: String?

    var body: some View {
        let pool = store.plan.pool
        NavigationStack {
            Form {
                Section { Text("Change the sets for this day only. The rest of the plan stays as it is.").foregroundStyle(Palette.muted) }
                ForEach(steps) { st in
                    let b = binding(st.id)
                    Section(st.kind.title + (st.label.isEmpty ? "" : " · \(st.label)")) {
                        Stepper("Reps: \(st.reps)", value: b.reps, in: 1...60)
                        Stepper("Distance: \(Fmt.num(st.dist)) m", value: b.dist, in: pool...10000, step: pool)
                        Stepper("Rest: \(st.rest) s", value: b.rest, in: 0...600, step: 5)
                        Picker("Effort", selection: b.zone) {
                            ForEach(st.zone == .max ? Zone.editable + [.max] : Zone.editable) { Text($0.name).tag($0) }
                        }
                        Button("Remove this set", role: .destructive) { steps.removeAll { $0.id == st.id } }
                    }
                }
                Section {
                    Button("Add a set") {
                        let i = steps.firstIndex { $0.kind == .cd } ?? steps.count
                        steps.insert(SetStep(.main, 4, max(100, pool), .steady, rest: 20), at: i)
                    }
                    if session.edited {
                        Button("Go back to the planned swim", role: .destructive) { store.resetEdit(session.key); dismiss() }
                    }
                }
                if let error { Text(error).foregroundStyle(Palette.buoy) }
            }
            .navigationTitle("Edit swim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear { steps = session.steps }
        }
    }

    private func binding(_ id: UUID) -> Binding<SetStep> {
        Binding(
            get: { steps.first { $0.id == id } ?? SetStep(.main, 1, 100, .easy) },
            set: { v in if let i = steps.firstIndex(where: { $0.id == id }) { steps[i] = v } }
        )
    }

    private func save() {
        guard steps.contains(where: { $0.kind == .main }) else { error = "Keep at least one main set."; return }
        guard steps.allSatisfy({ $0.dist % store.plan.pool == 0 }) else {
            error = "Each distance must be a multiple of \(store.plan.pool) m, your pool length."
            return
        }
        store.saveEdit(session.key, steps: steps.map { st in
            var s = st
            if s.label == "non-stop" && s.reps > 1 { s.label = "" }
            return s
        })
        dismiss()
    }
}

/// Pick any swim from Apple Health to count for this session.
struct LinkSwimSheet: View {
    @Environment(TrainerStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var pending: SwimRecord?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pick the swim to count for \(session.title) on \(Days.withWeekday(session.at)). Its time and distance replace what is recorded now.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    if health.status == .notConnected {
                        Button("Connect Apple Health") { Task { await health.connect(); await health.sync(into: store) } }
                    }
                }
                let swims = store.linkCandidates(for: session.key)
                if swims.isEmpty {
                    Section {
                        Text("No swims found in Apple Health for the last few weeks. Pull down to check again.").foregroundStyle(Palette.muted)
                    }
                }
                Section("Swims in Apple Health") {
                    ForEach(swims) { sw in
                        let linked = store.linkedSession(for: sw.id)
                        Button {
                            if let other = linked, other.key != session.key { pending = sw } else { link(sw) }
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(Days.withWeekday(sw.day)) · \(Fmt.num(sw.metres)) m \(sw.openWater ? "open water" : "pool")")
                                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                                    Text([Fmt.time(sw.duration), sw.start.formatted(date: .omitted, time: .shortened),
                                          sw.longestNonStop.map { "longest non-stop \(Fmt.num($0)) m" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                                    Text(status(sw, linked)).font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(linked?.key == session.key ? Palette.water : Palette.muted)
                                }
                                Spacer()
                                if linked?.key == session.key { Image(systemName: "checkmark").foregroundStyle(Palette.water) }
                            }
                        }
                    }
                }
            }
            .refreshable { await health.sync(into: store) }
            .navigationTitle("Link a swim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Move this swim?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let sw = pending { Button("Count it for \(session.title) instead") { link(sw) } }
            } message: {
                if let sw = pending, let other = store.linkedSession(for: sw.id) {
                    Text("It counts for \(other.title) on \(Days.withWeekday(other.at)) now. That swim goes back to not done.")
                }
            }
        }
    }

    private func status(_ sw: SwimRecord, _ linked: Session?) -> String {
        if let linked { return linked.key == session.key ? "Linked to this swim" : "Counts for \(linked.title), \(Days.withWeekday(linked.at))" }
        return store.state.ignored.contains(sw.id) ? "Not counted" : "Not linked"
    }

    private func link(_ sw: SwimRecord) {
        store.link(sw.id, to: session.key)
        dismiss()
    }
}
