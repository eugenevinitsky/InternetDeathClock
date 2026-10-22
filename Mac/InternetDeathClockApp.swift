import SwiftUI
import Charts
import ServiceManagement

@main
struct InternetDeathClockApp: App {
    @StateObject private var tracker = Tracker()
    @StateObject private var presenter = DeathClockPresenter()

    var body: some Scene {
        Window("Internet Death Clock", id: "main") {
            ContentView(tracker: tracker, presenter: presenter)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            ContentView(tracker: tracker, presenter: presenter)
        } label: {
            MenuBarLabel(tracker: tracker, presenter: presenter)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Pops the Death Clock up at launch, on wake from sleep, and on screen unlock.
@MainActor
final class DeathClockPresenter: ObservableObject {
    /// Set by the menu bar label, which is the one view guaranteed to exist.
    var openMainWindow: (() -> Void)?
    /// Bumped on every pop-up so already-open windows flip to the Death Clock tab.
    @Published private(set) var showRequests = 0
    private var lastShown = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    init() {
        let show: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: show),
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: show),
        ]
    }

    func show() {
        // Wake and unlock usually fire together; only pop up once.
        guard Date().timeIntervalSince(lastShown) > 30 else { return }
        lastShown = Date()
        UserDefaults.standard.set(Tab.deathClock.rawValue, forKey: "tab")
        showRequests += 1
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func enableLaunchAtLoginOnce() {
        let key = "didEnableLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }
}

struct MenuBarLabel: View {
    @ObservedObject var tracker: Tracker
    let presenter: DeathClockPresenter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack {
            Image(systemName: "chart.pie.fill")
            Text("\(tracker.focusStats.breaks.count)")
        }
        .onAppear {
            let open = openWindow
            presenter.openMainWindow = { open(id: "main") }
            presenter.enableLaunchAtLoginOnce()
            presenter.show()
        }
    }
}


enum Tab: String, CaseIterable, Identifiable {
    case today = "Today", history = "History", deathClock = "Death Clock"
    var id: String { rawValue }
}

enum Scope: String, CaseIterable, Identifiable {
    case all = "Everything", websites = "Websites", apps = "Apps"
    var id: String { rawValue }
    func includes(_ key: ActivityKey) -> Bool {
        switch self {
        case .all: return true
        case .websites: return key.isWebsite
        case .apps: return !key.isWebsite
        }
    }
}

struct Slice: Identifiable {
    let id: String
    let label: String
    let seconds: TimeInterval
    let color: Color
    let isWebsite: Bool
}

struct ContentView: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var presenter: DeathClockPresenter
    @AppStorage("scope") private var scope: Scope = .all
    @AppStorage("tab") private var tab: Tab = .today
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hovered: String?

    private var slices: [Slice] {
        let totals = tracker.totals(filter: scope.includes)
        let top = totals.prefix(palette.count)
        var result = top.enumerated().map { i, t in
            Slice(id: "\(t.key)", label: t.key.name, seconds: t.seconds, color: palette[i], isWebsite: t.key.isWebsite)
        }
        let rest = totals.dropFirst(palette.count).reduce(0) { $0 + $1.seconds }
        if rest > 0 {
            result.append(Slice(id: "other", label: "Other (\(totals.count - top.count))", seconds: rest, color: otherColor, isWebsite: false))
        }
        return result
    }

    var body: some View {
        let slices = slices
        let total = slices.reduce(0) { $0 + $1.seconds }
        let stats = tracker.focusStats

        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == .deathClock {
                DeathClockView(tracker: tracker)
            } else if tab == .history {
                HistoryView(summaries: tracker.allSummaries)
            } else {
                todayTab(slices: slices, total: total, stats: stats)
            }

            if !tracker.deniedBrowsers.isEmpty {
                Label("Can't read tabs in \(tracker.deniedBrowsers.joined(separator: ", ")). Allow Internet Death Clock in System Settings → Privacy & Security → Automation.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if tracker.needsAccessibility {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                } label: {
                    Label("Grant Accessibility access so Firefox tabs count as websites →", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.link)
            }

            Divider()
            HStack {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Spacer()
                Button("Data") { tracker.revealData() }
                Button("Quit") { tracker.save(); NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 340)
        .onChange(of: presenter.showRequests) { tab = .deathClock }
    }

    private func todayTab(slices: [Slice], total: TimeInterval, stats: FocusStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.headline)
                Spacer()
                Text("\(format(tracker.totalTracked)) tracked").foregroundStyle(.secondary).monospacedDigit()
            }

            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if slices.isEmpty {
                Text("Nothing tracked yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                pie(slices, total: total)
                legend(slices, total: total)
            }

            Divider()
            focusSection(stats)
        }
    }

    private func pie(_ slices: [Slice], total: TimeInterval) -> some View {
        Chart(slices) { s in
            SectorMark(
                angle: .value("Time", s.seconds),
                innerRadius: .ratio(0.58),
                outerRadius: .ratio(hovered == s.id ? 1.0 : 0.94),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(s.color)
            .opacity(hovered == nil || hovered == s.id ? 1 : 0.45)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 2) {
                if let h = hovered, let s = slices.first(where: { $0.id == h }) {
                    Text(s.label).font(.caption).lineLimit(1).frame(maxWidth: 110)
                    Text(format(s.seconds)).font(.title3.bold()).monospacedDigit()
                    Text(percent(s.seconds, of: total)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(format(total)).font(.title3.bold()).monospacedDigit()
                    Text(scope == .all ? "active" : scope.rawValue.lowercased()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 190)
    }

    private func legend(_ slices: [Slice], total: TimeInterval) -> some View {
        VStack(spacing: 5) {
            ForEach(slices) { s in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 10, height: 10)
                    if s.isWebsite && scope == .all {
                        Image(systemName: "globe").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(s.label).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(format(s.seconds)).monospacedDigit().foregroundStyle(.secondary)
                    Text(percent(s.seconds, of: total)).monospacedDigit().frame(width: 38, alignment: .trailing)
                }
                .font(.callout)
                .padding(.vertical, 1)
                .contentShape(Rectangle())
                .background(hovered == s.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .onHover { hovered = $0 ? s.id : (hovered == s.id ? nil : hovered) }
            }
        }
    }

    private func focusSection(_ stats: FocusStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(stats.breaks.count)").font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    Text("focus breaks").font(.headline)
                    Text("switched away after < 5 min").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(stats.longestRun > 0 ? format(stats.longestRun) : "—")
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    Text("longest focus").font(.headline)
                    Text(stats.longestRunKey?.name ?? " ").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            breakHistogram(stats.breaks)

            Text("How long you stay on one thing").font(.subheadline.weight(.medium))
            FocusDistribution(runs: stats.runs)

            HStack {
                Text("Now").foregroundStyle(.secondary)
                Spacer()
                Text(tracker.current.map { "\($0.name) · \(format(tracker.currentRun))" } ?? "idle")
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.callout)
        }
    }

    /// Breaks per hour, so you can see when in the day focus fell apart.
    private func breakHistogram(_ breaks: [Date]) -> some View {
        let cal = Calendar.current
        var counts = [Int](repeating: 0, count: 24)
        for b in breaks { counts[cal.component(.hour, from: b)] += 1 }
        let first = min(counts.firstIndex { $0 > 0 } ?? 9, 9)
        let last = max(counts.lastIndex { $0 > 0 } ?? 17, 17, cal.component(.hour, from: Date()))
        let hours = Array(first...last)
        return Chart(hours, id: \.self) { h in
            BarMark(x: .value("Hour", h), y: .value("Breaks", counts[h]), width: .ratio(0.7))
                .cornerRadius(2)
                .foregroundStyle(palette[1])
        }
        .chartXScale(domain: (Double(first) - 0.5)...(Double(last) + 0.5))
        .chartXAxis {
            AxisMarks(values: hours.filter { $0 % 3 == 0 }) { v in
                AxisValueLabel { if let h = v.as(Int.self) { Text(hourLabel(h)) } }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 54)
    }
}

private func hourLabel(_ h: Int) -> String {
    h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h - 12)p"
}
