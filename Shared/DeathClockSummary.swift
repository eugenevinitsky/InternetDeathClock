import SwiftUI

/// The Death Clock readout: given average daily time per website, projects it over
/// the rest of your expected life. Display-only, so the phone's Screen Time
/// extension can render it too.
struct DeathClockSummary: View {
    let profile: Profile
    /// Number of days the averages are based on.
    let days: Int
    /// Average seconds per day, per website, sorted descending.
    let perDay: [(name: String, seconds: TimeInterval)]
    var sourceNote: String = ""

    /// Hours per day you're awake, used for the "% of waking life" figure.
    static let wakingHours: Double = 16

    var body: some View {
        let remaining = profile.remainingYears
        let wakingSeconds = remaining * 365.25 * Self.wakingHours * 3600
        let projections = perDay.prefix(10).map { (name: $0.name, seconds: $0.seconds * remaining * 365.25) }
        let allWeb = perDay.reduce(0) { $0 + $1.seconds } * remaining * 365.25
        let maxProjection = projections.first?.seconds ?? 1

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Expected to live to about \(Int((Double(profile.age) + 0.5 + remaining).rounded()))")
                    .font(.headline)
                Text("\(String(format: "%.1f", remaining)) years left · \(Int(remaining * 365.25 * Self.wakingHours).formatted()) waking hours")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }

            if projections.isEmpty {
                Text("No websites tracked yet. Your time on the internet is, for now, finite.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("At this rate, you'll spend")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(formatLong(allWeb)).font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    Text("of the rest of your life on websites. That's \(percent(allWeb, of: wakingSeconds)) of your remaining waking hours.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    ForEach(projections, id: \.name) { p in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(p.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(formatLong(p.seconds)).monospacedDigit()
                                Text(percent(p.seconds, of: wakingSeconds))
                                    .monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .font(.callout)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(palette[0])
                                    .frame(width: max(2, geo.size.width * p.seconds / maxProjection))
                            }
                            .frame(height: 4)
                        }
                    }
                }

                Text("Based on your average over \(days) day\(days == 1 ? "" : "s") of tracking\(sourceNote). Life expectancy is from US Social Security life tables, adjusted for BMI. % is of remaining waking hours, assuming \(Int(Self.wakingHours)) hours awake a day.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
