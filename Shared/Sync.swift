import Foundation

/// Identifiers shared by the Mac app, the iPhone app and its Screen Time extension.
enum Shared {
    static let appGroup = "group.com.eugenevinitsky.internetdeathclock"
    /// Keys in iCloud key-value storage (and mirrored into the app group on the phone).
    static let macDayPrefix = "mac."
    static let profileKey = "profile"

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

/// Age/sex/BMI, synced so the phone uses the same numbers as the Mac.
struct Profile: Codable, Equatable {
    var age: Int = 25
    var sex: Sex = .male
    var bmi: Double = 26

    var remainingYears: Double {
        LifeExpectancy.remainingYears(age: Double(age) + 0.5, sex: sex, bmi: bmi)
    }
}

extension Sex: Codable {}

/// How long you stayed on one thing before switching, bucketed.
enum RunBuckets {
    static let all: [(label: String, upTo: TimeInterval)] = [
        ("< 1m", 60), ("1–5m", 300), ("5–15m", 900), ("15–30m", 1800), ("30–60m", 3600), ("1h+", .infinity),
    ]
    static func index(for run: TimeInterval) -> Int {
        all.firstIndex { run < $0.upTo } ?? all.count - 1
    }
}

/// One day of Mac activity, synced to the phone through iCloud key-value storage.
struct MacDaySummary: Codable {
    var day: String                 // yyyy-MM-dd
    /// Seconds per activity, keyed "web:<host>" or "app:<name>".
    var totals: [String: Double]
    var focusBreaks: Int
    var longestRun: Double
    var longestRunName: String?
    var runBucketSeconds: [Double]
    var runBucketCounts: [Int]
    var updated: Date

    static func key(_ name: String, isWebsite: Bool) -> String { (isWebsite ? "web:" : "app:") + name }

    static func parse(_ key: String) -> (name: String, isWebsite: Bool) {
        if key.hasPrefix("web:") { return (String(key.dropFirst(4)), true) }
        if key.hasPrefix("app:") { return (String(key.dropFirst(4)), false) }
        return (key, false)
    }
}
