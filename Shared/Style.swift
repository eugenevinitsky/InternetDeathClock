import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// Categorical palette (light, dark), in fixed order; "Other" is neutral gray.
let palette: [Color] = [
    ("#2a78d6", "#3987e5"), ("#eb6834", "#d95926"), ("#1baf7a", "#199e70"),
    ("#eda100", "#c98500"), ("#e87ba4", "#d55181"), ("#008300", "#008300"),
    ("#4a3aa7", "#9085e9"),
].map { Color.dynamic(light: $0.0, dark: $0.1) }
let otherColor = Color.dynamic(light: "#a8a7a2", dark: "#5e5d59")

/// "45s", "12m", "2h 5m"
func format(_ t: TimeInterval) -> String {
    let m = Int(t) / 60
    if m < 1 { return "\(Int(t))s" }
    return m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
}

func percent(_ part: TimeInterval, of total: TimeInterval) -> String {
    guard total > 0 else { return "—" }
    let p = part / total * 100
    return p < 1 ? "<1%" : "\(Int(p.rounded()))%"
}

/// "2.3 years", "7 months", "12 days", "5 hours"
func formatLong(_ seconds: TimeInterval) -> String {
    let days = seconds / 86_400
    if days >= 365.25 { return String(format: "%.1f years", days / 365.25) }
    if days >= 30.44 { let m = Int((days / 30.44).rounded()); return "\(m) month\(m == 1 ? "" : "s")" }
    if days >= 1 { let d = Int(days.rounded()); return "\(d) day\(d == 1 ? "" : "s")" }
    let h = Int((seconds / 3600).rounded()); return "\(h) hour\(h == 1 ? "" : "s")"
}

private func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return (CGFloat((v >> 16) & 0xff) / 255, CGFloat((v >> 8) & 0xff) / 255, CGFloat(v & 0xff) / 255)
}

extension Color {
    static func dynamic(light: String, dark: String) -> Color {
        let (l, d) = (rgb(light), rgb(dark))
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }
}
