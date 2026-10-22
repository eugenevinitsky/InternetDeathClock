import SwiftUI
import FamilyControls
import DeviceActivity

@main
struct PhoneApp: App {
    @StateObject private var sync = MacSync()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sync)
        }
    }
}

/// Copies the Mac's daily summaries from iCloud into the app group, where the
/// Screen Time report extension (which can't touch iCloud itself) reads them.
@MainActor
final class MacSync: ObservableObject {
    @Published private(set) var lastMacUpdate: Date?
    @Published private(set) var profile = Profile()
    @Published private(set) var summaries: [MacDaySummary] = []
    /// Bumped whenever new Mac data arrives so reports re-render.
    @Published private(set) var revision = 0

    private let cloud = NSUbiquitousKeyValueStore.default
    private let group = UserDefaults(suiteName: Shared.appGroup)

    init() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.pull() } }
        cloud.synchronize()
        pull()
    }

    func pull() {
        cloud.synchronize()
        var latest: Date?
        var days: [MacDaySummary] = []
        for (key, value) in cloud.dictionaryRepresentation {
            guard key.hasPrefix(Shared.macDayPrefix) || key == Shared.profileKey,
                  let data = value as? Data else { continue }
            group?.set(data, forKey: key)
            if key.hasPrefix(Shared.macDayPrefix),
               let s = try? JSONDecoder().decode(MacDaySummary.self, from: data) {
                latest = max(latest ?? s.updated, s.updated)
                days.append(s)
            }
            if key == Shared.profileKey, let p = try? JSONDecoder().decode(Profile.self, from: data) {
                profile = p
            }
        }
        lastMacUpdate = latest
        summaries = days
        revision += 1
    }
}

struct RootView: View {
    @EnvironmentObject private var sync: MacSync
    @Environment(\.scenePhase) private var scenePhase
    /// iOS updates this asynchronously after the request returns, so observe it directly.
    @ObservedObject private var authCenter = AuthorizationCenter.shared
    @State private var authError: String?
    @State private var requesting = false
    @State private var now = Date()

    var body: some View {
        if authCenter.authorizationStatus == .approved {
            TabView {
                report(.today, days: 1)
                    .tabItem { Label("Today", systemImage: "chart.pie.fill") }
                NavigationStack {
                    ScrollView {
                        HistoryView(summaries: sync.summaries).padding()
                        Text("Focus history comes from your Mac. iOS doesn't expose app switching, so the phone can't measure focus breaks.")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    .navigationTitle("Focus history")
                }
                .tabItem { Label("History", systemImage: "chart.bar.xaxis") }
                report(.deathClock, days: 30)
                    .tabItem { Label("Death Clock", systemImage: "hourglass") }
                SettingsView()
                    .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { sync.pull(); now = Date() }
            }
        } else {
            onboarding
        }
    }

    /// The report is drawn by the extension; changing the filter's end date forces a refresh.
    private func report(_ context: DeviceActivityReport.Context, days: Int) -> some View {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: now))!
        let filter = DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: now)),
            users: .all,
            devices: .init([.iPhone])
        )
        return DeviceActivityReport(context, filter: filter)
            .id("\(context.rawValue)-\(sync.revision)-\(now.timeIntervalSince1970)")
            .ignoresSafeArea(edges: .bottom)
    }

    private var onboarding: some View {
        VStack(spacing: 18) {
            Image(systemName: "hourglass").font(.system(size: 56))
            Text("Internet Death Clock").font(.title.bold())
            Text("To count your phone time alongside your Mac, this needs Screen Time access. Your usage never leaves the phone. Apple doesn't allow it to.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                requesting = true
                authError = nil
                Task {
                    do {
                        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                        print("[DeathClock] authorization returned, status:", AuthorizationCenter.shared.authorizationStatus)
                    } catch {
                        print("[DeathClock] authorization failed:", error)
                        authError = "\(error.localizedDescription)\n\(String(describing: error))"
                    }
                    requesting = false
                }
            } label: {
                if requesting { ProgressView() } else { Text("Allow Screen Time access") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(requesting)
            Text("Status: \(String(describing: authCenter.authorizationStatus))")
                .font(.caption2).foregroundStyle(.secondary)
            if let authError {
                Text(authError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(32)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var sync: MacSync

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    LabeledContent("Last update", value: sync.lastMacUpdate.map {
                        $0.formatted(.relative(presentation: .named))
                    } ?? "never")
                    Button("Check now") { sync.pull() }
                }
                Section {
                    LabeledContent("Age", value: "\(sync.profile.age)")
                    LabeledContent("Sex", value: sync.profile.sex.rawValue)
                    LabeledContent("BMI", value: sync.profile.bmi.formatted(.number.precision(.fractionLength(0...1))))
                    LabeledContent("Expected to live to", value: "\(Int((Double(sync.profile.age) + 0.5 + sync.profile.remainingYears).rounded()))")
                } header: {
                    Text("You")
                } footer: {
                    Text("Synced from the Mac app's Death Clock tab. Change it there.")
                }
            }
            .navigationTitle("Sync")
        }
    }
}
