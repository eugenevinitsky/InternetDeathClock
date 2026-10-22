import Charts
import SwiftUI

/// Day-by-day focus metrics with a 7-day average, to see whether focus is improving.
struct HistoryView: View {
    /// One summary per tracked day, any order. Days without data are simply gaps.
    let summaries: [MacDaySummary]
    var dayCount = 30

    @AppStorage("historyMetric") private var metric: Metric = .breaksPerHour
    @State private var selectedDay: Date?

    enum Metric: String, CaseIterable, Identifiable {
        case breaksPerHour = "Breaks per hour"
        case deepShare = "Deep focus share"
        case longest = "Longest focus"
        case breaks = "Focus breaks"
        var id: String { rawValue }

        var lowerIsBetter: Bool { self == .breaksPerHour || self == .breaks }

        var explanation: String {
            switch self {
            case .breaksPerHour: return "Focus breaks per hour you were active. Lower is better."
            case .deepShare: return "Share of your time in stretches of 15+ minutes on one thing. Higher is better."
            case .longest: return "Your longest uninterrupted stretch each day, in minutes. Higher is better."
            case .breaks: return "Times you switched away after < 5 min. Lower is better, though it also rises with hours worked."
            }
        }

        /// nil when the day doesn't have enough activity for the number to mean anything.
        func value(_ s: MacDaySummary) -> Double? {
            let active = s.totals.values.reduce(0, +)
            guard active >= 15 * 60 else { return nil }
            switch self {
            case .breaksPerHour: return Double(s.focusBreaks) / (active / 3600)
            case .deepShare:
                let deep = s.runBucketSeconds.dropFirst(3).reduce(0, +)   // 15m+ buckets
                let all = s.runBucketSeconds.reduce(0, +)
                return all > 0 ? deep / all * 100 : nil
            case .longest: return s.longestRun / 60
            case .breaks: return Double(s.focusBreaks)
            }
        }

        func label(_ v: Double) -> String {
            switch self {
            case .breaksPerHour: return String(format: "%.1f/hr", v)
            case .deepShare: return "\(Int(v.rounded()))%"
            case .longest: return format(v * 60)
            case .breaks: return "\(Int(v.rounded()))"
            }
        }
    }

    private struct Point: Identifiable {
        let day: Date
        let value: Double?
        let average: Double?
        var id: Date { day }
    }

    private var points: [Point] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let byDay = Dictionary(summaries.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        // Look back an extra 6 days so the first average has a full window.
        let days = (0..<(dayCount + 6)).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let values = days.map { byDay[Shared.dayString($0)].flatMap(metric.value) }
        return days.indices.dropFirst(6).map { i in
            let window = values[(i - 6)...i].compactMap { $0 }
            return Point(day: days[i], value: values[i],
                         average: window.isEmpty ? nil : window.reduce(0, +) / Double(window.count))
        }
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: 12) {
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            headline(points)

            if points.allSatisfy({ $0.value == nil }) {
                Text("Not enough history yet. Each day with 15+ minutes of activity adds a bar.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                chart(points)
            }

            Text(metric.explanation + " Bars are days; the line is the 7-day average.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// This week vs. the week before, or the hovered day.
    @ViewBuilder
    private func headline(_ points: [Point]) -> some View {
        if let sel = selectedDay, let p = points.first(where: { Calendar.current.isDate($0.day, inSameDayAs: sel) }) {
            VStack(alignment: .leading, spacing: 0) {
                Text(p.value.map(metric.label) ?? "—").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Text(p.day.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            let thisWeek = mean(points.suffix(7).compactMap(\.value))
            let lastWeek = mean(points.dropLast(7).suffix(7).compactMap(\.value))
            VStack(alignment: .leading, spacing: 2) {
                Text(thisWeek.map(metric.label) ?? "—").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                if let t = thisWeek, let l = lastWeek, l > 0 {
                    let change = (t - l) / l * 100
                    let improved = metric.lowerIsBetter ? change < 0 : change > 0
                    let flat = abs(change) < 3
                    Label {
                        Text(flat ? "About the same as last week (\(metric.label(l)))"
                             : "\(Int(abs(change).rounded()))% \(change < 0 ? "lower" : "higher") than last week (\(metric.label(l))), \(improved ? "better" : "worse")")
                    } icon: {
                        Image(systemName: flat ? "equal.circle" : improved ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("average over the last 7 days").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chart(_ points: [Point]) -> some View {
        Chart {
            ForEach(points) { p in
                if let v = p.value {
                    BarMark(x: .value("Day", p.day, unit: .day), y: .value(metric.rawValue, v))
                        .cornerRadius(2)
                        .foregroundStyle(palette[0].opacity(
                            selectedDay == nil || Calendar.current.isDate(p.day, inSameDayAs: selectedDay!) ? 0.55 : 0.25))
                }
            }
            ForEach(points) { p in
                if let a = p.average {
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("7-day average", a))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel { if let d = v.as(Double.self) { Text(metric.label(d)) } }
            }
        }
        .frame(height: 170)
    }

    private func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }
}
