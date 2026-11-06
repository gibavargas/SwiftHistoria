import MapKit
import SwiftUI

/// Presentation-only prioritization for campaign events.
///
/// The simulation and persisted timeline remain complete. This briefing only
/// decides which signals deserve full cards and which belong in the compact,
/// on-demand log so a busy world does not become a wall of equally loud text.
struct NativeEventBriefing {
    private struct RankedCandidate {
        let event: NativeCampaignEvent
        let offset: Int
        let score: Int
    }

    let highlights: [NativeCampaignEvent]
    let additionalEvents: [NativeCampaignEvent]
    let totalCount: Int
    let severeCount: Int
    let majorCount: Int
    let nationCount: Int
    let globalCount: Int

    static func make(
        events: [NativeCampaignEvent],
        highlightLimit: Int
    ) -> NativeEventBriefing {
        let limit = max(0, min(highlightLimit, events.count))
        let candidateLimit = min(events.count, limit + 4)
        var topCandidates: [RankedCandidate] = []
        var strongest: RankedCandidate?
        var strongestCrisis: RankedCandidate?
        var strongestNationSignal: RankedCandidate?
        var strongestGlobalSignal: RankedCandidate?
        var severeCount = 0
        var majorCount = 0
        var nationCount = 0

        func prefer(_ candidate: RankedCandidate, over current: RankedCandidate?) -> RankedCandidate {
            guard let current else { return candidate }
            return outranks(candidate, current) ? candidate : current
        }

        for (offset, event) in events.enumerated() {
            let candidate = RankedCandidate(event: event, offset: offset, score: salience(of: event))
            strongest = prefer(candidate, over: strongest)
            if event.importance == .severe || event.kind == .crisis {
                strongestCrisis = prefer(candidate, over: strongestCrisis)
            }
            if event.playerRelated || !event.linkedActionIDs.isEmpty {
                strongestNationSignal = prefer(candidate, over: strongestNationSignal)
            }
            if !event.playerRelated {
                strongestGlobalSignal = prefer(candidate, over: strongestGlobalSignal)
            }

            switch event.importance {
            case .severe: severeCount += 1
            case .major: majorCount += 1
            case .minor: break
            }
            if event.playerRelated { nationCount += 1 }

            guard candidateLimit > 0 else { continue }
            let insertionIndex = topCandidates.firstIndex { outranks(candidate, $0) } ?? topCandidates.endIndex
            topCandidates.insert(candidate, at: insertionIndex)
            if topCandidates.count > candidateLimit {
                topCandidates.removeLast()
            }
        }

        var selectedIndices: Set<Int> = []
        func ensure(_ candidate: RankedCandidate?) {
            guard selectedIndices.count < limit, let candidate else { return }
            selectedIndices.insert(candidate.offset)
        }

        // Reserve room for the perspectives a player needs, then fill from a
        // bounded top-k list. This keeps unbounded campaign archives O(n * k)
        // with k <= 12 instead of sorting the complete history every render.
        ensure(strongest)
        ensure(strongestCrisis)
        ensure(strongestNationSignal)
        ensure(strongestGlobalSignal)

        for candidate in topCandidates where selectedIndices.count < limit {
            selectedIndices.insert(candidate.offset)
        }

        let highlights = selectedIndices.map { offset in
            RankedCandidate(event: events[offset], offset: offset, score: salience(of: events[offset]))
        }
        .sorted(by: outranks)
        .map(\.event)
        let additionalEvents = events.enumerated().compactMap { index, event in
            selectedIndices.contains(index) ? nil : event
        }

        return NativeEventBriefing(
            highlights: highlights,
            additionalEvents: additionalEvents,
            totalCount: events.count,
            severeCount: severeCount,
            majorCount: majorCount,
            nationCount: nationCount,
            globalCount: events.count - nationCount
        )
    }

    private static func outranks(_ lhs: RankedCandidate, _ rhs: RankedCandidate) -> Bool {
        if lhs.score == rhs.score {
            // Timelines are newest-first, so equal signals retain recency.
            return lhs.offset < rhs.offset
        }
        return lhs.score > rhs.score
    }

    private static func salience(of event: NativeCampaignEvent) -> Int {
        let importanceScore = switch event.importance {
        case .severe: 500
        case .major: 220
        case .minor: 0
        }
        let kindScore = switch event.kind {
        case .crisis: 120
        case .action: 35
        case .diplomacy: 25
        case .economy: 15
        case .world: 0
        }
        let effectScore = min(
            90,
            event.strategicEffects.reduce(0) { result, effect in
                result + min(abs(effect.magnitude), 12) * 5
            }
        )

        return importanceScore + kindScore + effectScore
            + (event.sovereigntyChange == nil ? 0 : 240)
            + (event.linkedActionIDs.isEmpty ? 0 : 140)
            + (event.playerRelated ? 100 : 0)
            + (event.notable ? 70 : 0)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.glowingCyan)
                .frame(width: 40, height: 40)
                .background(Color.glowingCyan.opacity(0.12), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.glowingCyan.opacity(0.24), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassmorphicCard(borderColor: .white.opacity(0.08), cornerRadius: 12)
        .hoverScale(1.02)
    }
}

struct ActionRow: View {
    let action: NativePlannedAction
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: outcomeSymbol)
                .font(.title3)
                .foregroundStyle(outcomeColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)
                    if let outcome = action.outcome {
                        Text(outcomeBadge(outcome))
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(outcomeBadgeColor(outcome))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(outcomeBadgeColor(outcome).opacity(0.12), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(outcomeBadgeColor(outcome).opacity(0.24), lineWidth: 1)
                            }
                    }
                }
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.softRed.opacity(0.8))
                    .padding(8)
                    .background(Color.softRed.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete order \(action.title)")
            .accessibilityIdentifier("native-delete-order-\(action.id)")
        }
        .padding(12)
        .glassmorphicCard(borderColor: outcomeBorderColor, cornerRadius: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-order-row-\(action.id)")
    }

    // MARK: – Outcome presentation helpers

    private var outcomeSymbol: String {
        guard action.status == .resolved else { return "circle" }
        switch action.outcome {
        case .success: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case nil: return "checkmark.circle.fill"
        }
    }

    private var outcomeColor: Color {
        guard action.status == .resolved else { return Color.iceBlue.opacity(0.4) }
        switch action.outcome {
        case .success: return Color.neonTeal
        case .partial: return Color.alertGold
        case .failure: return Color.softRed
        case nil: return Color.neonTeal
        }
    }

    private var outcomeBorderColor: Color {
        guard action.status == .resolved else { return Color.white.opacity(0.08) }
        switch action.outcome {
        case .failure: return Color.softRed.opacity(0.18)
        case .partial: return Color.alertGold.opacity(0.18)
        case .success, nil: return Color.white.opacity(0.08)
        }
    }

    private func outcomeBadge(_ outcome: NativeActionOutcome) -> String {
        switch outcome {
        case .success: "✅ SUCCESS"
        case .partial: "⚠️ PARTIAL"
        case .failure: "❌ FAILED"
        }
    }

    private func outcomeBadgeColor(_ outcome: NativeActionOutcome) -> Color {
        switch outcome {
        case .success: Color.neonTeal
        case .partial: Color.alertGold
        case .failure: Color.softRed
        }
    }
}

struct EventCard: View {
    let event: NativeCampaignEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // High security dossier header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.caption)
                        .foregroundStyle(Color.alertGold)
                    Text("INTEL REPORT // CLASS-\(event.importance.rawValue.uppercased())")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.alertGold)
                }
                Spacer()
                Text(event.playerRelated ? "NATION" : "GLOBAL")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(event.playerRelated ? Color.glowingCyan : Color.neonTeal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        event.playerRelated ? Color.glowingCyan.opacity(0.12) : Color.neonTeal.opacity(0.12),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(event.playerRelated ? Color.glowingCyan.opacity(0.24) : Color.neonTeal.opacity(0.24), lineWidth: 1)
                    }
            }
            .padding(.bottom, 2)

            if let img = event.imageAssetName {
                EventImageView(imageName: img, fallbackIcon: "doc.text.image", height: 140)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Text("\(event.date) · \(event.kind.displayName.uppercased())")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(event.description)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if !event.strategicEffects.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                Text("TACTICAL DELTAS")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(event.strategicEffects) { effect in
                        HStack(alignment: .center, spacing: 10) {
                            let isPositive = effect.magnitude >= 0
                            Text(isPositive ? "+\(effect.magnitude)" : "\(effect.magnitude)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(isPositive ? Color.neonTeal : Color.softRed)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(minWidth: 36)
                                .background(
                                    isPositive ? Color.neonTeal.opacity(0.12) : Color.softRed.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isPositive ? Color.neonTeal.opacity(0.3) : Color.softRed.opacity(0.3), lineWidth: 1)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(effect.track.displayName.uppercased())
                                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.secondary)
                                let displayTarget = CountryNameResolver.name(forCode: effect.target)
                                Text(effect.target.uppercased() == "GLOBAL" || displayTarget == effect.target
                                    ? effect.summary
                                    : "\(displayTarget): \(effect.summary)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            if let options = event.decisionOptions, !options.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                Text("STRATEGIC DECISION BRANCHES")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.neonTeal)

                VStack(spacing: 8) {
                    ForEach(options) { opt in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.label)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                Text(opt.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(opt.effectTrack.mechanicCode)
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundStyle(Color.glowingCyan)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(14)
        .glassmorphicCard(borderColor: .white.opacity(0.08), cornerRadius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-event-card-\(event.id)")
    }
}

struct NativeClassicDecisionView: View {
    let decision: NativeCampaignEvent
    let onChoose: (NativeEventDecisionOption) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.alertGold)
                        Text("CRITICAL EXECUTIVE DECISION // ADVANCE PAUSED")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.alertGold)
                    }
                    Spacer()
                    Text(decision.date)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let img = decision.imageAssetName {
                    EventImageView(imageName: img, fallbackIcon: "shield.lefthalf.filled", height: 180)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(decision.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(decision.kind.displayName.uppercased())
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.glowingCyan)
                }

                Text(decision.description)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .background(Color.white.opacity(0.12))

                Text("POLICY DIRECTIVES (CHOOSE ONE TO FORM RESOLUTION)")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.neonTeal)

                if let options = decision.decisionOptions {
                    VStack(spacing: 10) {
                        ForEach(options) { opt in
                            Button {
                                onChoose(opt)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(opt.label)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(opt.effectTrack.mechanicCode)
                                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                                            .foregroundStyle(Color.glowingCyan)
                                    }
                                    Text(opt.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)

                                    HStack(spacing: 8) {
                                        let isPos = opt.effectMagnitude >= 0
                                        Text("\(isPos ? "+" : "")\(opt.effectMagnitude) \(opt.effectTrack.displayName)")
                                            .font(.system(size: 9, design: .monospaced).weight(.bold))
                                            .foregroundStyle(isPos ? Color.neonTeal : Color.softRed)

                                        if opt.nextChainedEventID != nil {
                                            Text("⟦CHAIN CASSETTE⟧")
                                                .font(.system(size: 8, design: .monospaced).weight(.bold))
                                                .foregroundStyle(Color.alertGold)
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.spaceBlack)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.neonTeal.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("classic-decision-\(opt.id)")
                        }
                    }
                }
            }
            .padding(20)
            .background(Color.deepSlate)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.alertGold.opacity(0.6), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.85), radius: 24, x: 0, y: 12)
            .frame(maxWidth: 620)
            .padding(20)
        }
    }
}

struct NativeEventDigestStrip: View {
    let briefing: NativeEventBriefing
    var accessibilityIdentifier = "native-event-digest"

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            digestMetric(
                value: briefing.totalCount,
                label: "Signals",
                systemImage: "waveform.path.ecg",
                color: Color.iceBlue
            )
            digestMetric(
                value: briefing.severeCount,
                label: "Critical",
                systemImage: "exclamationmark.triangle.fill",
                color: briefing.severeCount > 0 ? Color.softRed : Color.secondary
            )
            digestMetric(
                value: briefing.majorCount,
                label: "Major",
                systemImage: "star.fill",
                color: Color.alertGold
            )
            digestMetric(
                value: briefing.nationCount,
                label: "Nation-linked",
                systemImage: "building.columns.fill",
                color: Color.glowingCyan
            )
            digestMetric(
                value: briefing.globalCount,
                label: "Global",
                systemImage: "globe.americas.fill",
                color: Color.neonTeal
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func digestMetric(
        value: Int,
        label: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(.callout, design: .monospaced).weight(.black))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct NativeCompactEventRow: View {
    let event: NativeCampaignEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(importanceColor)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.title)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(event.importance.rawValue.uppercased())
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(importanceColor)
                }

                Text("\(event.date) · \(event.kind.displayName)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(event.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("native-compact-event-\(event.id)")
    }

    private var importanceColor: Color {
        switch event.importance {
        case .severe: Color.softRed
        case .major: Color.alertGold
        case .minor: Color.iceBlue.opacity(0.72)
        }
    }
}

struct NativeTurnReportView: View {
    let report: NativeGeneratedTurn
    let onDismiss: () -> Void
    @State private var showsAdditionalSignals = false

    private var briefing: NativeEventBriefing {
        NativeEventBriefing.make(events: report.events, highlightLimit: 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GEOPOLITICAL PERIOD REPORT")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)
                        .tracking(2.0)
                    Text("Turn Resolution")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close report")
                .accessibilityIdentifier("native-report-close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .background(Color.spaceBlack)

            Divider()
                .background(Color.white.opacity(0.12))

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Turn summary banner
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUMMARY ANALYSIS")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.alertGold)
                            .tracking(1.2)
                        Text(report.summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassmorphicCard(borderColor: Color.alertGold.opacity(0.25), cornerRadius: 12)

                    // Key metrics deltas
                    HStack(spacing: 16) {
                        // Stability card
                        HStack(spacing: 12) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.title2)
                                .foregroundStyle(Color.neonTeal)
                                .padding(8)
                                .background(Color.neonTeal.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                let sign = report.stabilityDelta >= 0 ? "+" : ""
                                Text("\(sign)\(report.stabilityDelta)%")
                                    .font(.title3.monospacedDigit().weight(.bold))
                                    .foregroundStyle(report.stabilityDelta >= 0 ? Color.neonTeal : Color.softRed)
                                Text("Stability")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .glassmorphicCard(borderColor: Color.white.opacity(0.08), cornerRadius: 12)

                        // World Tension card
                        HStack(spacing: 12) {
                            Image(systemName: "globe.americas.fill")
                                .font(.title2)
                                .foregroundStyle(Color.softRed)
                                .padding(8)
                                .background(Color.softRed.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                let sign = report.worldTensionDelta >= 0 ? "+" : ""
                                Text("\(sign)\(report.worldTensionDelta)")
                                    .font(.title3.monospacedDigit().weight(.bold))
                                    .foregroundStyle(report.worldTensionDelta >= 0 ? Color.softRed : Color.neonTeal)
                                Text("World Tension")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .glassmorphicCard(borderColor: Color.white.opacity(0.08), cornerRadius: 12)
                    }

                    // A concise briefing comes first; the complete log remains
                    // available without making every autonomous action compete
                    // for the player's attention.
                    VStack(alignment: .leading, spacing: 14) {
                        Text("PRIORITY SIGNALS")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.iceBlue)
                            .tracking(1.5)

                        if report.events.isEmpty {
                            Text("No specific signals logged this period.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            NativeEventDigestStrip(
                                briefing: briefing,
                                accessibilityIdentifier: "native-report-event-digest"
                            )

                            Text("The most consequential and decision-relevant signals are expanded. The complete period log is preserved below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(spacing: 14) {
                                ForEach(briefing.highlights) { event in
                                    EventCard(event: event)
                                }
                            }

                            if !briefing.additionalEvents.isEmpty {
                                DisclosureGroup(isExpanded: $showsAdditionalSignals) {
                                    LazyVStack(spacing: 8) {
                                        ForEach(briefing.additionalEvents) { event in
                                            NativeCompactEventRow(event: event)
                                        }
                                    }
                                    .padding(.top, 10)
                                } label: {
                                    Label(
                                        "Additional signals (\(briefing.additionalEvents.count))",
                                        systemImage: "tray.full"
                                    )
                                    .font(.system(.callout, design: .monospaced).weight(.bold))
                                    .foregroundStyle(Color.alertGold)
                                }
                                .padding(12)
                                .background(
                                    Color.alertGold.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .accessibilityIdentifier("native-report-additional-signals")
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Action Button bar
            VStack {
                Button(action: onDismiss) {
                    HStack {
                        Spacer()
                        Text("ACKNOWLEDGE & CLOSE DOSSIER")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .tracking(1.0)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .background(Color.glowingCyan, in: Capsule())
                    .foregroundStyle(.black)
                    .shadow(color: Color.glowingCyan.opacity(0.3), radius: 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-report-dismiss")
            }
            .padding(16)
            .background(Color.spaceBlack)
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color.spaceBlack.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("native-turn-report")
    }
}
