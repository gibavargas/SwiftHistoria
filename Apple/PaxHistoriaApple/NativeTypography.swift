import SwiftUI

/// Typography tiers: DATA for small badges/values (caps mono OK), TITLE for
/// section titles and buttons (title case, readable size).
enum NativeTypography {
    /// Small data labels, badges, numeric readouts. Monospaced + caps.
    static func dataLabel(_ size: CGFloat = 11) -> Font {
        .system(size: max(size, 11), weight: .bold, design: .monospaced)
    }

    /// Section titles, buttons, primary labels. Title case, rounded design.
    static func sectionTitle(_ style: Font.TextStyle = .headline) -> Font {
        .system(style, design: .rounded).weight(.semibold)
    }

    /// Body copy.
    static func body(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .default)
    }
}
