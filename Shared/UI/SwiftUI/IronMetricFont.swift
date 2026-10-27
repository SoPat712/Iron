import SwiftUI

extension Font {
    /// SF Pro metric numerals with fixed digit widths; use semibold in dense rows.
    /// Example: `Text("185").font(.ironMetric(.title2))` or
    /// `Text("8").font(.ironMetric(.body, weight: .semibold))`.
    /// Render units separately in a smaller, secondary semantic style.
    static func ironMetric(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .default).weight(weight).monospacedDigit()
    }
}
