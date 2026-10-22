import SwiftUI

/// Share of time spent in stretches of each length on one thing. Stretches under
/// 5 minutes are orange like the breaks chart, since leaving them counted as one.
struct FocusDistribution: View {
    let seconds: [TimeInterval]
    let counts: [Int]

    init(seconds: [TimeInterval], counts: [Int]) {
        self.seconds = seconds
        self.counts = counts
    }

    init(runs: [TimeInterval]) {
        var s = [TimeInterval](repeating: 0, count: RunBuckets.all.count)
        var c = [Int](repeating: 0, count: RunBuckets.all.count)
        for r in runs {
            let i = RunBuckets.index(for: r)
            s[i] += r
            c[i] += 1
        }
        self.init(seconds: s, counts: c)
    }

    var body: some View {
        let total = max(seconds.reduce(0, +), 1)
        let maxShare = (seconds.max() ?? 0) / total

        VStack(spacing: 4) {
            ForEach(RunBuckets.all.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(RunBuckets.all[i].label)
                        .frame(width: 52, alignment: .leading)
                        .foregroundStyle(.secondary)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(RunBuckets.all[i].upTo <= 300 ? palette[1] : palette[0])
                            .frame(width: maxShare > 0 ? max(seconds[i] > 0 ? 2 : 0, geo.size.width * (seconds[i] / total) / maxShare) : 0)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 10)
                    Text(percent(seconds[i], of: total))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                    Text("\(counts[i])×")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .font(.caption)
            }
            Text("% of today's time spent in stretches of that length; × is how many stretches.")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
