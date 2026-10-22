import Charts
import SwiftUI

struct TodayReportView: View {
    let model: TodayModel

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let seconds: Double
        let color: Color
        let detail: String
    }

    private var slices: [Slice] {
        let top = model.rows.prefix(palette.count)
        var result = top.enumerated().map { i, r in
            Slice(id: r.name + "\(r.isWebsite)", label: r.name, seconds: r.total, color: palette[i],
                  detail: split(mac: r.mac, phone: r.phone))
        }
        let rest = model.rows.dropFirst(palette.count)
        let restTotal = rest.reduce(0) { $0 + $1.total }
        if restTotal > 0 {
            result.append(Slice(id: "other", label: "Other (\(rest.count))", seconds: restTotal, color: otherColor,
                                detail: split(mac: rest.reduce(0) { $0 + $1.mac }, phone: rest.reduce(0) { $0 + $1.phone })))
        }
        return result
    }

    private func split(mac: Double, phone: Double) -> String {
        switch (mac >= 1, phone >= 1) {
        case (true, true): return "Mac \(format(mac)) · iPhone \(format(phone))"
        case (true, false): return "Mac"
        default: return "iPhone"
        }
    }

    var body: some View {
        let slices = slices
        let total = slices.reduce(0) { $0 + $1.seconds }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today").font(.largeTitle.bold())
                    Spacer()
                    Text("\(format(total)) · Mac + iPhone").foregroundStyle(.secondary).monospacedDigit()
                }

                if slices.isEmpty {
                    Text("Nothing tracked yet.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Chart(slices) { s in
                        SectorMark(angle: .value("Time", s.seconds), innerRadius: .ratio(0.58), angularInset: 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(s.color)
                    }
                    .chartLegend(.hidden)
                    .chartBackground { _ in
                        VStack(spacing: 2) {
                            Text(format(total)).font(.title2.bold()).monospacedDigit()
                            Text("active").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 230)

                    VStack(spacing: 8) {
                        ForEach(slices) { s in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.label).lineLimit(1).truncationMode(.middle)
                                    Text(s.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(format(s.seconds)).monospacedDigit().foregroundStyle(.secondary)
                                Text(percent(s.seconds, of: total)).monospacedDigit().frame(width: 42, alignment: .trailing)
                            }
                        }
                    }
                }

                Divider()

                HStack(alignment: .top) {
                    stat(model.mac.map { "\($0.focusBreaks)" } ?? "—", "Mac focus breaks", "switched away after < 5 min")
                    Spacer()
                    stat("\(model.phonePickups)", "iPhone pickups", "times you picked it up", trailing: true)
                }
                if let mac = model.mac, mac.longestRun > 0 {
                    stat(format(mac.longestRun), "longest focus on Mac", mac.longestRunName ?? "")
                    Text("How long you stay on one thing (Mac)").font(.subheadline.weight(.medium))
                    FocusDistribution(seconds: mac.runBucketSeconds, counts: mac.runBucketCounts)
                }

                Text(model.mac.map { "Mac data from \($0.updated.formatted(.relative(presentation: .named)))." }
                     ?? "No Mac data yet. Open Internet Death Clock on your Mac, signed into the same iCloud account.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func stat(_ value: String, _ title: String, _ caption: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(value).font(.system(size: 32, weight: .semibold)).monospacedDigit()
            Text(title).font(.headline)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct DeathClockReportView: View {
    let model: DeathClockModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Death Clock").font(.largeTitle.bold())
                DeathClockSummary(
                    profile: model.profile,
                    days: model.days,
                    perDay: model.perDay,
                    sourceNote: " (Mac: \(model.macDays), iPhone: \(model.phoneDays)). Phone apps for a site, like Bluesky or Instagram, count toward that site"
                )
            }
            .padding()
        }
    }
}
