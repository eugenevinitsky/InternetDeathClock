import AppKit
import Combine

enum ActivityKey: Codable, Hashable {
    case website(String)
    case app(String)

    var name: String {
        switch self {
        case .website(let n), .app(let n): return n
        }
    }
    var isWebsite: Bool { if case .website = self { return true } else { return false } }
}

struct Segment: Codable {
    var key: ActivityKey
    var start: Date
    var end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct FocusStats {
    var breaks: [Date] = []          // when each focus break happened
    var runs: [TimeInterval] = []    // length of every uninterrupted stretch on one thing
    var longestRun: TimeInterval = 0
    var longestRunKey: ActivityKey?
}

@MainActor
final class Tracker: ObservableObject {
    /// Spending less than this on something before switching counts as a focus break.
    static let focusThreshold: TimeInterval = 5 * 60
    /// No keyboard/mouse input for this long pauses tracking.
    static let idleThreshold: TimeInterval = 3 * 60
    static let pollInterval: TimeInterval = 2
    /// Gaps longer than this between samples (sleep, idle, lock) split activity.
    static let maxGap: TimeInterval = 10

    @Published private(set) var segments: [Segment] = []
    @Published private(set) var current: ActivityKey?
    @Published private(set) var deniedBrowsers: [String] = []
    @Published private(set) var needsAccessibility = false

    private var day: Date
    /// Totals from previous days (they don't change, so loaded once per day).
    private var history: (days: Int, totals: [ActivityKey: TimeInterval]) = (0, [:])
    /// Per-day focus summaries for previous days, for the History tab.
    private(set) var pastSummaries: [MacDaySummary] = []
    private var timer: Timer?
    private var lastSave = Date()
    private var screenAsleep = false
    private var observers: [NSObjectProtocol] = []

    init() {
        day = Calendar.current.startOfDay(for: Date())
        segments = Self.load(day: day)
        history = Self.loadHistory(before: day)
        pastSummaries = Self.loadPastSummaries(before: day)
        Self.backfillCloud(before: day)
        observeSystemEvents()
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    // MARK: Sampling

    private func tick() {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        if today != day {
            // Close yesterday at midnight, start a fresh day.
            if current != nil, let i = segments.indices.last { segments[i].end = min(segments[i].end, today) }
            save()
            day = today
            segments = []
            history = Self.loadHistory(before: day)
            pastSummaries = Self.loadPastSummaries(before: day)
        pastSummaries = Self.loadPastSummaries(before: day)
            current = nil
        }

        let idle = Self.secondsSinceLastInput()
        if screenAsleep || idle >= Self.idleThreshold {
            // Trim the idle stretch off the end of the last segment.
            if current != nil, let i = segments.indices.last {
                segments[i].end = max(segments[i].start, min(segments[i].end, now.addingTimeInterval(-idle)))
            }
            current = nil
        } else {
            record(ActivityProbe.currentKey(), at: now)
        }

        let denied = ActivityProbe.deniedBrowsers.sorted()
        if denied != deniedBrowsers { deniedBrowsers = denied }
        if ActivityProbe.accessibilityMissing != needsAccessibility { needsAccessibility = ActivityProbe.accessibilityMissing }
        if now.timeIntervalSince(lastSave) > 30 { save() }
    }

    private func record(_ key: ActivityKey?, at now: Date) {
        let contiguous = segments.last.map { now.timeIntervalSince($0.end) <= Self.maxGap } ?? false
        if current != nil, contiguous, let i = segments.indices.last {
            segments[i].end = now
        }
        guard let key else { current = nil; return }
        if key == current, contiguous { return }
        segments.append(Segment(key: key, start: now, end: now))
        current = key
    }

    private static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func observeSystemEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        let pause: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAsleep = true; self?.tick() }
        }
        let resume: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAsleep = false; self?.tick() }
        }
        observers += [
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: pause),
            ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: pause),
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: resume),
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: resume),
            dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: pause),
            dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: resume),
        ]
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.save() } })
    }

    // MARK: Stats

    func totals(filter: (ActivityKey) -> Bool = { _ in true }) -> [(key: ActivityKey, seconds: TimeInterval)] {
        var totals: [ActivityKey: TimeInterval] = [:]
        for s in segments where filter(s.key) { totals[s.key, default: 0] += s.duration }
        return totals.map { ($0.key, $0.value) }.filter { $0.1 >= 1 }.sorted { $0.1 > $1.1 }
    }

    var totalTracked: TimeInterval { segments.reduce(0) { $0 + $1.duration } }

    /// A focus break = switching away from something you'd been on for under 5 minutes.
    /// Consecutive samples of the same thing are merged; switches across an idle/sleep gap don't count.
    var focusStats: FocusStats { Self.focusStats(of: segments) }

    static func focusStats(of segments: [Segment]) -> FocusStats {
        var stats = FocusStats()
        var runKey: ActivityKey?
        var runStart = Date.distantPast
        var runEnd = Date.distantPast

        func closeRun() {
            let d = runEnd.timeIntervalSince(runStart)
            stats.runs.append(d)
            if d > stats.longestRun { stats.longestRun = d; stats.longestRunKey = runKey }
        }

        for s in segments {
            let contiguous = s.start.timeIntervalSince(runEnd) <= Self.maxGap
            if s.key == runKey, contiguous {
                runEnd = s.end
                continue
            }
            if runKey != nil {
                closeRun()
                if contiguous, runEnd.timeIntervalSince(runStart) < Self.focusThreshold {
                    stats.breaks.append(s.start)
                }
            }
            runKey = s.key
            runStart = s.start
            runEnd = s.end
        }
        if runKey != nil { closeRun() }
        return stats
    }

    /// How long the user has been on the current thing without switching.
    var currentRun: TimeInterval {
        guard current != nil, var start = segments.last?.start, let key = segments.last?.key else { return 0 }
        for s in segments.dropLast().reversed() {
            guard s.key == key, start.timeIntervalSince(s.end) <= Self.maxGap else { break }
            start = s.start
        }
        return Date().timeIntervalSince(start)
    }

    /// Average seconds per day spent on each website, over the last 30 days that have data
    /// (today counts as one day, even though it isn't over yet).
    func dailyWebsiteAverages() -> (days: Int, perDay: [(key: ActivityKey, seconds: TimeInterval)]) {
        var totals = history.totals
        for s in segments { totals[s.key, default: 0] += s.duration }
        let days = history.days + (segments.isEmpty ? 0 : 1)
        guard days > 0 else { return (0, []) }
        let perDay = totals.filter { $0.key.isWebsite && $0.value >= 1 }
            .map { (key: $0.key, seconds: $0.value / Double(days)) }
            .sorted { $0.seconds > $1.seconds }
        return (days, perDay)
    }

    private static func loadHistory(before today: Date, lookback: Int = 30) -> (days: Int, totals: [ActivityKey: TimeInterval]) {
        let cal = Calendar.current
        var days = 0
        var totals: [ActivityKey: TimeInterval] = [:]
        for offset in 1...lookback {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let segs = load(day: d)
            if segs.isEmpty { continue }
            days += 1
            for s in segs { totals[s.key, default: 0] += s.duration }
        }
        return (days, totals)
    }

    // MARK: Persistence

    private static var storageDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InternetDeathClock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(for day: Date) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return storageDir.appendingPathComponent("\(f.string(from: day)).json")
    }

    private static func load(day: Date) -> [Segment] {
        guard let data = try? Data(contentsOf: file(for: day)) else { return [] }
        return (try? JSONDecoder().decode([Segment].self, from: data)) ?? []
    }

    func save() {
        lastSave = Date()
        guard let data = try? JSONEncoder().encode(segments) else { return }
        try? data.write(to: Self.file(for: day), options: .atomic)
        Self.pushToCloud(day: day, segments: segments)
    }

    func revealData() {
        NSWorkspace.shared.open(Self.storageDir)
    }
}

// MARK: iCloud sync (read by the iPhone app)

extension Tracker {
    private static var cloud: NSUbiquitousKeyValueStore { .default }

    static func summary(day: Date, segments: [Segment]) -> MacDaySummary {
        var totals: [String: Double] = [:]
        for s in segments {
            totals[MacDaySummary.key(s.key.name, isWebsite: s.key.isWebsite), default: 0] += s.duration
        }
        let stats = focusStats(of: segments)
        var bucketSeconds = [Double](repeating: 0, count: RunBuckets.all.count)
        var bucketCounts = [Int](repeating: 0, count: RunBuckets.all.count)
        for r in stats.runs {
            let i = RunBuckets.index(for: r)
            bucketSeconds[i] += r
            bucketCounts[i] += 1
        }
        return MacDaySummary(
            day: Shared.dayString(day), totals: totals.filter { $0.value >= 1 },
            focusBreaks: stats.breaks.count, longestRun: stats.longestRun,
            longestRunName: stats.longestRunKey?.name,
            runBucketSeconds: bucketSeconds, runBucketCounts: bucketCounts, updated: Date())
    }

    static func pushToCloud(day: Date, segments: [Segment]) {
        guard let data = try? JSONEncoder().encode(summary(day: day, segments: segments)) else { return }
        cloud.set(data, forKey: Shared.macDayPrefix + Shared.dayString(day))

        let d = UserDefaults.standard
        let profile = Profile(
            age: d.object(forKey: "age") as? Int ?? 34,
            sex: Sex(rawValue: d.string(forKey: "sex") ?? "") ?? .male,
            bmi: d.object(forKey: "bmi") as? Double ?? 30)
        if let p = try? JSONEncoder().encode(profile) { cloud.set(p, forKey: Shared.profileKey) }

        // Keep ~35 days; the phone only looks back 30.
        let cutoff = Shared.dayString(Calendar.current.date(byAdding: .day, value: -35, to: day) ?? day)
        for key in cloud.dictionaryRepresentation.keys where key.hasPrefix(Shared.macDayPrefix) {
            if String(key.dropFirst(Shared.macDayPrefix.count)) < cutoff { cloud.removeObject(forKey: key) }
        }
        cloud.synchronize()
    }

    static func loadPastSummaries(before today: Date, lookback: Int = 60) -> [MacDaySummary] {
        (1...lookback).compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let segs = load(day: d)
            return segs.isEmpty ? nil : summary(day: d, segments: segs)
        }
    }

    /// Past days plus today so far.
    var allSummaries: [MacDaySummary] { pastSummaries + [Self.summary(day: day, segments: segments)] }

    /// Upload past days that aren't in iCloud yet (e.g. first launch with sync).
    static func backfillCloud(before today: Date, lookback: Int = 30) {
        for offset in 1...lookback {
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = Shared.macDayPrefix + Shared.dayString(d)
            if cloud.data(forKey: key) != nil { continue }
            let segs = load(day: d)
            if segs.isEmpty { continue }
            if let data = try? JSONEncoder().encode(summary(day: d, segments: segs)) { cloud.set(data, forKey: key) }
        }
        cloud.synchronize()
    }
}
