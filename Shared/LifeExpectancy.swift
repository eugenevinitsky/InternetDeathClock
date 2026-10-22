import Foundation

enum Sex: String, CaseIterable, Identifiable {
    case female = "Female", male = "Male", unspecified = "Other"
    var id: String { rawValue }
}

/// Remaining life expectancy (years) by exact age, from the US Social Security
/// Administration period life table (approximate, pre-pandemic values).
enum LifeExpectancy {
    private static let table: [(age: Double, male: Double, female: Double)] = [
        (0, 76.2, 81.3), (10, 66.8, 71.8), (20, 57.1, 62.0), (30, 47.9, 52.3),
        (40, 38.9, 42.8), (50, 30.3, 33.7), (60, 22.2, 25.0), (70, 14.8, 16.9),
        (80, 8.5, 9.8), (90, 4.1, 4.8), (100, 2.0, 2.3), (120, 0.5, 0.5),
    ]

    static func remainingYears(age: Double, sex: Sex) -> Double {
        let a = min(max(age, 0), 120)
        let i = max(table.lastIndex { $0.age <= a } ?? 0, 0)
        let lo = table[i], hi = table[min(i + 1, table.count - 1)]
        let t = hi.age == lo.age ? 0 : (a - lo.age) / (hi.age - lo.age)
        func pick(_ row: (age: Double, male: Double, female: Double)) -> Double {
            switch sex {
            case .male: return row.male
            case .female: return row.female
            case .unspecified: return (row.male + row.female) / 2
            }
        }
        return pick(lo) + (pick(hi) - pick(lo)) * t
    }
}

extension LifeExpectancy {
    /// Approximate years of life lost vs. a BMI of 22.5–25, interpolated from the
    /// Prospective Studies Collaboration (Lancet 2009): ~2–4 years at BMI 30–35,
    /// ~8–10 years at BMI 40–45, with excess mortality below 22.5 as well.
    private static let bmiYearsLost: [(bmi: Double, years: Double)] = [
        (15, 5), (18.5, 1), (22.5, 0), (25, 0), (27.5, 0.75),
        (32.5, 3), (37.5, 6), (42.5, 9), (50, 13),
    ]

    static func yearsLost(bmi: Double) -> Double {
        let b = min(max(bmi, bmiYearsLost.first!.bmi), bmiYearsLost.last!.bmi)
        let i = bmiYearsLost.lastIndex { $0.bmi <= b } ?? 0
        let lo = bmiYearsLost[i], hi = bmiYearsLost[min(i + 1, bmiYearsLost.count - 1)]
        let t = hi.bmi == lo.bmi ? 0 : (b - lo.bmi) / (hi.bmi - lo.bmi)
        return lo.years + (hi.years - lo.years) * t
    }

    /// Remaining years, adjusted for BMI (never cutting more than a third of what's left).
    static func remainingYears(age: Double, sex: Sex, bmi: Double) -> Double {
        let base = remainingYears(age: age, sex: sex)
        return base - min(yearsLost(bmi: bmi), base / 3)
    }
}
