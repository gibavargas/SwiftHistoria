import SwiftUI

/// Typography tiers: DATA for small badges/values (caps mono OK), TITLE for
/// section titles and buttons (title case, readable size), and EDITORIAL /
/// CARTOGRAPHIC helpers for Living Atlas war-room framing.
enum NativeTypography {
    /// Small data labels, badges, numeric readouts. Monospaced + caps.
    static func dataLabel(_ size: CGFloat = 11) -> Font {
        .system(size: max(size, 11), weight: .bold, design: .monospaced)
    }

    /// Section titles, buttons, primary labels. Editorial serif hierarchy.
    static func sectionTitle(_ style: Font.TextStyle = .headline) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }

    /// Body copy.
    static func body(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif)
    }

    /// Monumental brass masthead title for campaign headers and archive covers.
    static func mastheadTitle(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .serif).weight(.bold)
    }

    /// Dossier headline for nation briefings, scenario covers, and field manual cards.
    static func dossierHeadline(_ style: Font.TextStyle = .title3) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }

    /// Crisp uppercase cartographic coordinate / telemetry caption.
    static func cartographicLabel(_ style: Font.TextStyle = .caption2, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }

    /// Tabular numeric readout for GDP, stability, and timeline counters.
    static func telemetryValue(_ style: Font.TextStyle = .caption, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .monospaced).weight(weight).monospacedDigit()
    }
}
