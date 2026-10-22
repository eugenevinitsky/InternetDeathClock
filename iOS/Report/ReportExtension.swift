import DeviceActivity
import ManagedSettings
import SwiftUI

@main
struct InternetDeathClockReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayScene { TodayReportView(model: $0) }
        DeathClockScene { DeathClockReportView(model: $0) }
    }
}

// MARK: Reading data

/// Phone usage, keyed like the Mac's ("web:<host>" / "app:<name>").
struct PhoneUsage {
    var totals: [String: Double] = [:]
    var pickups = 0
    var activeDays: Set<String> = []
}

private let safariBundleID = "com.apple.mobilesafari"

func collectPhoneUsage(_ data: DeviceActivityResults<DeviceActivityData>) async -> PhoneUsage {
    var usage = PhoneUsage()
    var safariWeb: Double = 0
    var safariKey: String?

    for await device in data {
        for await segment in device.activitySegments {
            if segment.totalActivityDuration > 0 {
                usage.activeDays.insert(Shared.dayString(segment.dateInterval.start))
            }
            usage.pickups += segment.totalPickupsWithoutApplicationActivity
            for await category in segment.categories {
                for await app in category.applications {
                    usage.pickups += app.numberOfPickups
                    let bundleID = app.application.bundleIdentifier
                    let key: String
                    if let domain = AppDomains.domain(forBundleID: bundleID) {
                        key = MacDaySummary.key(domain, isWebsite: true)
                    } else {
                        key = MacDaySummary.key(app.application.localizedDisplayName ?? bundleID ?? "Unknown app", isWebsite: false)
                    }
                    if bundleID == safariBundleID { safariKey = key }
                    usage.totals[key, default: 0] += app.totalActivityDuration
                }
                for await web in category.webDomains {
                    guard let host = web.webDomain.domain else { continue }
                    usage.totals[MacDaySummary.key(AppDomains.normalize(host), isWebsite: true), default: 0] += web.totalActivityDuration
                    safariWeb += web.totalActivityDuration
                }
            }
        }
    }
    // Safari's app time already includes the websites listed above; don't count it twice.
    if let safariKey, let t = usage.totals[safariKey] {
        let rest = t - safariWeb
        usage.totals[safariKey] = rest >= 60 ? rest : nil
    }
    return usage
}

/// Mac summaries the main app copied out of iCloud into the shared app group.
func loadMacSummaries(days: Int) -> [MacDaySummary] {
    guard let group = UserDefaults(suiteName: Shared.appGroup) else { return [] }
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    return (0..<days).compactMap { offset in
        guard let d = cal.date(byAdding: .day, value: -offset, to: today),
              let data = group.data(forKey: Shared.macDayPrefix + Shared.dayString(d)) else { return nil }
        return try? JSONDecoder().decode(MacDaySummary.self, from: data)
    }
}

func loadProfile() -> Profile {
    guard let data = UserDefaults(suiteName: Shared.appGroup)?.data(forKey: Shared.profileKey),
          let p = try? JSONDecoder().decode(Profile.self, from: data) else { return Profile() }
    return p
}

// MARK: Today

struct TodayModel {
    struct Row { var name: String; var isWebsite: Bool; var mac: Double; var phone: Double; var total: Double { mac + phone } }
    var rows: [Row] = []
    var mac: MacDaySummary?
    var phonePickups = 0
}

struct TodayScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .today
    let content: (TodayModel) -> TodayReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayModel {
        let phone = await collectPhoneUsage(data)
        let mac = loadMacSummaries(days: 1).first
        var merged: [String: TodayModel.Row] = [:]
        for (key, secs) in mac?.totals ?? [:] {
            let (name, web) = MacDaySummary.parse(key)
            merged[key, default: .init(name: name, isWebsite: web, mac: 0, phone: 0)].mac += secs
        }
        for (key, secs) in phone.totals {
            let (name, web) = MacDaySummary.parse(key)
            merged[key, default: .init(name: name, isWebsite: web, mac: 0, phone: 0)].phone += secs
        }
        return TodayModel(
            rows: merged.values.filter { $0.total >= 1 }.sorted { $0.total > $1.total },
            mac: mac,
            phonePickups: phone.pickups)
    }
}

// MARK: Death Clock

struct DeathClockModel {
    var profile = Profile()
    var days = 0
    var perDay: [(name: String, seconds: TimeInterval)] = []
    var macDays = 0
    var phoneDays = 0
}

struct DeathClockScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .deathClock
    let content: (DeathClockModel) -> DeathClockReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> DeathClockModel {
        let phone = await collectPhoneUsage(data)
        let macDays = loadMacSummaries(days: 30)

        // Average each device over the days it was actually used, then add them up.
        var perDay: [String: Double] = [:]
        if !macDays.isEmpty {
            for day in macDays {
                for (key, secs) in day.totals where key.hasPrefix("web:") {
                    perDay[key, default: 0] += secs / Double(macDays.count)
                }
            }
        }
        if !phone.activeDays.isEmpty {
            for (key, secs) in phone.totals where key.hasPrefix("web:") {
                perDay[key, default: 0] += secs / Double(phone.activeDays.count)
            }
        }
        return DeathClockModel(
            profile: loadProfile(),
            days: max(macDays.count, phone.activeDays.count),
            perDay: perDay.map { (name: MacDaySummary.parse($0.key).name, seconds: $0.value) }
                .sorted { $0.seconds > $1.seconds },
            macDays: macDays.count,
            phoneDays: phone.activeDays.count)
    }
}
