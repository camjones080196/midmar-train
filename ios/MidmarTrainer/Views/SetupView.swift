import SwiftUI
import WorkoutKit

struct SetupView: View {
    @Environment(TrainerStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(WatchScheduler.self) private var watch

    @State private var draft = PlanConfig()
    @State private var start = Date()
    @State private var race = Date()
    @State private var level = 200
    @State private var trialDist = 100
    @State private var trialTime = ""
    @State private var error: String?
    @State private var saved = false
    @State private var confirmErase = false

    var body: some View {
        Form {
            Section {
                Text("\(store.plan.weekCount) weeks and \(store.sessions.count) swims, \(Days.withWeekday(store.plan.begin)) to \(Days.withWeekday(store.plan.race)). \(store.plan.config.perWeek) \(store.plan.config.perWeek == 1 ? "swim" : "swims") a week in a \(store.plan.pool) m pool, building to a \(Fmt.dist(store.plan.peak)) long swim.")
                    .foregroundStyle(Palette.muted)
            } header: { Text("Your plan now") }

            Section {
                Stepper("\(Fmt.num(level)) m", value: $level, in: 0...2400, step: 25)
                Picker("Recent timed swim", selection: $trialDist) {
                    ForEach([100, 200, 400, 800, 1500], id: \.self) { Text("\(Fmt.num($0)) m").tag($0) }
                }
                TextField("Time, e.g. 2:10 (optional)", text: $trialTime).keyboardType(.numbersAndPunctuation)
            } header: {
                Text("Longest swim you can do now without stopping")
            } footer: {
                Text(store.state.latestTrial.map { "Your paces now come from \($0.dist) m in \(Fmt.time(Double($0.secs))). Enter a newer time to update them." }
                     ?? "A timed swim sets a target for every set. You can skip it and do the time trial in week 1.")
            }

            Section {
                DatePicker("Plan starts", selection: $start, displayedComponents: .date)
                Button("Start the plan today") { start = Date() }
                DatePicker("Race day", selection: $race, displayedComponents: .date)
            } header: { Text("Dates") } footer: { Text("Plans can be 6 to 40 weeks long. To re-plan mid-way, start today and enter your current longest swim.") }

            Section {
                Picker("Swims per week", selection: $draft.perWeek) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.perWeek) { _, n in draft.days = PlanConfig.presets[n] ?? [6] }
                HStack(spacing: 6) {
                    ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { d in
                        let on = draft.days.contains(d)
                        Button(Days.dow[d]) {
                            if on { draft.days.removeAll { $0 == d } } else { draft.days.append(d) }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(on ? Palette.water : Palette.ink)
                        .background(on ? Palette.waterSoft : Palette.bg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Palette.water : Palette.line))
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Picker("Pool length", selection: $draft.pool) {
                    Text("25 m").tag(25)
                    Text("50 m").tag(50)
                }
                Picker("Longest swim before the race", selection: $draft.peak) {
                    ForEach(PlanConfig.peaks, id: \.self) { Text(Fmt.dist($0)).tag($0) }
                }
            } header: {
                Text("Your week")
            } footer: {
                Text(draft.perWeek == 1
                     ? "Pick 1 day. One swim a week keeps the long swim, with a drill each week and a time trial every fourth week. It drops the technique, interval and speed sessions, so fitness builds more slowly."
                     : "Pick \(draft.perWeek) days. The long swim goes on your last swim day of the week. The race is 1.6 km, so a longer longest swim gives you a margin.")
            }

            Section {
                if let p = preview { Text(p).font(.system(size: 14)).foregroundStyle(Palette.muted) }
                if let error { Text(error).foregroundStyle(Palette.buoy) }
                Button(store.state.config.setup ? "Update plan" : "Build my plan", action: apply)
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if saved { Text("Plan updated. Ticked swims stay ticked by date.").font(.system(size: 14)).foregroundStyle(Palette.water) }
            }

            Section {
                switch health.status {
                case .unavailable: Text("Apple Health is not available on this device.")
                case .notConnected: Button("Connect Apple Health") { Task { await health.connect(); await health.sync(into: store) } }
                case .connected:
                    Label("Connected. Swims sync when you open the app.", systemImage: "checkmark.circle").foregroundStyle(Palette.water)
                    Button("Check for swims now") { Task { await health.sync(into: store) } }
                case .failed(let m): Text("Health could not be read: \(m)").foregroundStyle(Palette.buoy)
                }
                if watch.isSupported {
                    Toggle("Send swims to Apple Watch automatically", isOn: Binding(
                        get: { watch.autoSend },
                        set: { on in
                            watch.autoSend = on
                            Task {
                                if on { await watch.sync(store.watchQueue(), pool: store.plan.pool) } else { await watch.clear() }
                            }
                        }))
                    switch watch.authorization {
                    case .authorized:
                        Label(watch.autoSend ? "\(watch.scheduledCount) \(watch.scheduledCount == 1 ? "swim" : "swims") waiting in the Workout app on your watch." : "Workouts can be scheduled on your watch.",
                              systemImage: "applewatch").foregroundStyle(Palette.water)
                    case .denied, .restricted: Text("Workout scheduling is off. Turn it on in the Settings app under Privacy & Security, then Health.").foregroundStyle(Palette.muted)
                    default: Button("Allow sending workouts to Apple Watch") { Task { await watch.requestAccess(); await watch.sync(store.watchQueue(), pool: store.plan.pool) } }
                    }
                    if let m = watch.message { Text(m).font(.system(size: 13)).foregroundStyle(Palette.muted) }
                }
            } header: { Text("Apple Health and Watch") } footer: {
                Text("The app reads your swim workouts and does not write to Health, so your watch's swims are never doubled up. With automatic sending on, the next two weeks of swims wait in the Workout app on your watch, each on its day, and update when you change, move, skip or finish one.")
            }

            Section {
                Button("Erase all data", role: .destructive) { confirmErase = true }
            }
        }
        .navigationTitle("Setup")
        .onAppear(perform: load)
        .confirmationDialog("Erase your plan, ticks and times?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive) { store.eraseAll(); load() }
        } message: {
            Text("This cannot be undone. Swims in Apple Health are not touched.")
        }
    }

    private var config: PlanConfig {
        var c = draft
        c.start = Days.key(start)
        c.race = Days.key(race)
        c.level = level
        return c
    }

    private var preview: String? { config.hasValidSpan ? config.preview : nil }

    private func load() {
        draft = store.state.config
        start = draft.startDate ?? Date()
        race = draft.raceDate ?? Date()
        level = draft.level
        trialTime = ""
        error = nil
        saved = false
    }

    private func apply() {
        let c = config
        guard c.hasValidSpan else { error = "Pick a race date between 6 and 40 weeks after the plan start."; return }
        guard c.days.count == c.perWeek else { error = c.perWeek == 1 ? "Pick 1 swim day." : "Pick \(c.perWeek) swim days."; return }
        var trial: (dist: Int, secs: Int)?
        if !trialTime.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let secs = Fmt.parseTime(trialTime), (40...600).contains(Double(secs) / Double(trialDist) * 100) else {
                error = "Enter the timed swim as minutes and seconds, like 2:10."
                return
            }
            trial = (trialDist, secs)
        }
        store.applyConfig(c, trial: trial)
        load()
        saved = true
    }
}
