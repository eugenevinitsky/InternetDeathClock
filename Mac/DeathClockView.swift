import SwiftUI

/// Projects how much of the rest of your life each website will eat, if today's habits hold.
struct DeathClockView: View {
    @ObservedObject var tracker: Tracker
    @AppStorage("age") private var age: Int = 25
    @AppStorage("sex") private var sex: Sex = .male
    @AppStorage("bmi") private var bmi: Double = 26

    var body: some View {
        let (days, perDay) = tracker.dailyWebsiteAverages()
        VStack(alignment: .leading, spacing: 14) {
            demographics
            DeathClockSummary(
                profile: Profile(age: age, sex: sex, bmi: bmi),
                days: days,
                perDay: perDay.map { (name: $0.key.name, seconds: $0.seconds) },
                sourceNote: days == 1 ? " (today, which isn't over yet)" : ""
            )
        }
    }

    private var demographics: some View {
        HStack(spacing: 10) {
            Stepper("Age \(age)", value: $age, in: 1...110)
            Picker("", selection: $sex) {
                ForEach(Sex.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 80)
            HStack(spacing: 4) {
                Text("BMI")
                TextField("BMI", value: $bmi, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 40)
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(.callout)
        .controlSize(.small)
    }
}
