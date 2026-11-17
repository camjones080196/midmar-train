import SwiftUI

@main
struct MidmarTrainerApp: App {
    @State private var store = TrainerStore()
    @State private var health = HealthService()
    @State private var watch = WatchScheduler()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(health)
                .environment(watch)
        }
    }
}

enum AppTab: Hashable { case today, plan, progress, race, setup }

struct RootView: View {
    @Environment(TrainerStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(WatchScheduler.self) private var watch
    @Environment(\.scenePhase) private var phase
    @State private var tab = AppTab.today

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView(tab: $tab).withSessionLinks() }
                .tabItem { Label("Today", systemImage: "figure.pool.swim") }.tag(AppTab.today)
            NavigationStack { PlanView().withSessionLinks() }
                .tabItem { Label("Plan", systemImage: "calendar") }.tag(AppTab.plan)
            NavigationStack { ProgressTab().withSessionLinks() }
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }.tag(AppTab.progress)
            NavigationStack { RaceView() }
                .tabItem { Label("Race", systemImage: "flag") }.tag(AppTab.race)
            NavigationStack { SetupView() }
                .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }.tag(AppTab.setup)
        }
        .tint(Palette.water)
        .task {
            await watch.refresh()
            await health.sync(into: store)
        }
        .task(id: watch.autoSend ? store.watchToken : "off") {
            // Wait a moment so a run of quick changes sends once.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, watch.autoSend else { return }
            await watch.sync(store.watchQueue(), pool: store.plan.pool)
        }
        .onChange(of: phase) { _, newPhase in
            guard newPhase == .active else { return }
            store.freshStart()
            Task { await health.sync(into: store) }
        }
    }
}

extension View {
    /// Lets any screen in a tab push a workout by its session key.
    func withSessionLinks() -> some View {
        navigationDestination(for: String.self) { key in SessionDetailView(key: key) }
            .navigationDestination(for: WeekRoute.self) { route in WeekView(index: route.index) }
    }
}

struct WeekRoute: Hashable { let index: Int }
