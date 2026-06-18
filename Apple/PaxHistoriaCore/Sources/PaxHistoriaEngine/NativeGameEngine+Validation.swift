import Foundation
import PaxHistoriaModels

extension NativeGameEngine {
    public static func validated(_ turn: NativeGeneratedTurn, state: NativeCampaignState, months: Int) throws -> NativeGeneratedTurn {
        guard months > 0 else {
            throw NativeGameEngineError.invalidTurn("Generated turns require a positive time jump.")
        }
        guard isValidDate(state.gameDate) else {
            throw NativeGameEngineError.invalidTurn("Campaign state has an invalid game date.")
        }

        let candidateEvents = Array(turn.events.prefix(6))
        guard !candidateEvents.isEmpty else {
            throw NativeGameEngineError.invalidTurn("Foundation Models returned no events.")
        }
        guard candidateEvents.contains(where: { !$0.playerRelated }) else {
            throw NativeGameEngineError.invalidTurn("At least one generated event must be independent of the player country.")
        }
        let summary = sanitizeFoundationModelText(turn.summary)
        guard hasConcreteFoundationText(summary, minimumWords: 6) else {
            throw NativeGameEngineError.invalidTurn("Foundation Models returned an empty or placeholder turn summary.")
        }

        let targetDate = advance(date: state.gameDate, months: months)
        guard isValidDate(targetDate) else {
            throw NativeGameEngineError.invalidTurn("Generated turn produced an invalid target date.")
        }

        let plannedActionIDs = Set(state.plannedActions.filter { $0.status == .planned }.map(\.id))
        var seenEventIDs = Set<String>()
        var seenEffectIDs = Set<String>()
        var events: [NativeCampaignEvent] = []

        for (index, rawEvent) in candidateEvents.enumerated() {
            let event = normalized(rawEvent, index: index, targetDate: targetDate, country: state.country)
            guard seenEventIDs.insert(event.id).inserted else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) reused a duplicate event ID.")
            }
            guard NativeGameEngine.isValidDate(event.date) else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) has an invalid date.")
            }
            guard !event.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) is missing a title.")
            }
            guard !containsFoundationPlaceholderText(event.title) else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) used a schema placeholder instead of a real title.")
            }
            guard !event.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) is missing a description.")
            }
            guard !containsFoundationPlaceholderText(event.description), event.description.split(separator: " ").count >= 8 else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) needs a concrete description.")
            }
            guard !event.strategicEffects.isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(event.title) has no strategic effects.")
            }
            let invalidLinks = event.linkedActionIDs.filter { !plannedActionIDs.contains($0) }
            guard invalidLinks.isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) linked to an unknown or already resolved action.")
            }

            var allEffectsValid = true
            for effect in event.strategicEffects {
                let summaryValid = hasConcreteFoundationText(effect.summary, minimumWords: 5)
                let targetValid = !effect.target.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty && !containsFoundationPlaceholderText(effect.target)
                let dateValid = NativeGameEngine.isValidDate(effect.date)
                let idMatch = effect.eventId == event.id
                if !(summaryValid && targetValid && dateValid && idMatch) {
                    allEffectsValid = false
                    break
                }
            }
            guard allEffectsValid else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) needs a concrete strategic effect summary.")
            }

            for effect in event.strategicEffects {
                guard seenEffectIDs.insert(effect.id).inserted else {
                    throw NativeGameEngineError.invalidTurn("Event \(index + 1) reused a duplicate strategic effect ID.")
                }
            }
            events.append(event)
        }

        return NativeGeneratedTurn(
            events: eventsWithSingleMapNudge(events),
            stabilityDelta: max(-12, min(12, turn.stabilityDelta)),
            summary: summary,
            worldTensionDelta: max(-12, min(12, turn.worldTensionDelta))
        )
    }

    private static func eventsWithSingleMapNudge(_ events: [NativeCampaignEvent]) -> [NativeCampaignEvent] {
        var keptMapNudge = false
        return events.map { event in
            guard let hex = event.hexLeverCode,
                  NativeHexLever.decodeHexLever(hex)?.conflictMode != nil
            else {
                return event
            }
            if !keptMapNudge {
                keptMapNudge = true
                return event
            }

            var next = event
            var clean = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if clean.lowercased().hasPrefix("0x") {
                clean = String(clean.dropFirst(2))
            }
            next.hexLeverCode = clean.count >= 6 ? "0x\(clean.prefix(6))" : nil
            return next
        }
    }
}
