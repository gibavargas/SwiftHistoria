import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
protocol NativeAIService {
    func checkReadiness() async -> NativeAIReadiness
    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn
    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction]
    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String
    func generateDiplomaticReply(for state: NativeCampaignState, thread: NativeDiplomaticThread, message: String) async throws -> String
}

@MainActor
final class NativeFoundationModelService: NativeAIService {
    private let promptCharacterLimit = 8_500
    private let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeFoundationModelService")

    func checkReadiness() async -> NativeAIReadiness {
        do {
            let tokenBudget = try await runReadinessProbe()
            logger.info("Apple Foundation Models readiness available")
            return .available(tokenBudget: tokenBudget)
        } catch NativeFoundationModelError.unsupportedOS {
            logger.error("Apple Foundation Models unsupported OS")
            return .unavailable("unsupported-os")
        } catch NativeFoundationModelError.modelUnavailable(let reason) {
            logger.error("Apple Foundation Models unavailable reason=\(reason, privacy: .public)")
            return .modelUnavailable(reason)
        } catch {
            logger.error("Apple Foundation Models readiness failed")
            return .failure(error)
        }
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            logger.info("Apple Foundation turn generation started round=\(state.round, privacy: .public) months=\(months, privacy: .public)")
            let rawTurn = try await generateSlicedTurn(for: state, months: months)
            do {
                let validated = try NativeGameEngine.validated(rawTurn, state: state, months: months)
                logger.info("Apple Foundation turn generation validated events=\(validated.events.count, privacy: .public)")
                return validated
            } catch {
                logger.error("Apple Foundation turn validation failed; retrying with repair instruction")
                let retryTurn = try await generateSlicedTurn(
                    for: state,
                    months: months,
                    repairInstruction: error.localizedDescription
                )
                do {
                    let validated = try NativeGameEngine.validated(retryTurn, state: state, months: months)
                    logger.info("Apple Foundation repaired turn validated events=\(validated.events.count, privacy: .public)")
                    return validated
                } catch {
                    logger.error("Apple Foundation repaired turn remained invalid")
                    throw NativeFoundationModelError.invalidGeneratedTurn(error.localizedDescription)
                }
            }
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            logger.info("Apple Foundation suggestions started round=\(state.round, privacy: .public)")
            let suggestions = try await generateStructuredSuggestions(for: state)
            let validSuggestions = suggestions.filter { suggestion in
                isValidNativeSuggestion(suggestion)
            }
            guard validSuggestions.count >= 3 else {
                logger.error("Apple Foundation suggestions invalid count=\(validSuggestions.count, privacy: .public)")
                throw NativeFoundationModelError.invalidSuggestedActions("Expected at least three concrete suggestions from Apple Foundation Models.")
            }
            logger.info("Apple Foundation suggestions validated count=\(validSuggestions.count, privacy: .public)")
            return Array(validSuggestions.prefix(4))
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        let safeQuestion = sanitizeFoundationModelText(question)
        guard hasConcreteFoundationText(safeQuestion, minimumWords: 2) else {
            throw NativeFoundationModelError.generationFailed("Advisor question was empty or placeholder-like.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            logger.info("Apple Foundation advisor generation started round=\(state.round, privacy: .public)")
            let answer = try await generateTextResponse(
                prompt: makeAdvisorPrompt(for: state, question: safeQuestion),
                maxTokens: 220,
                repairNote: "Answer as a blunt strategic advisor in no more than three short paragraphs."
            )
            logger.info("Apple Foundation advisor generation completed")
            return answer
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    func generateDiplomaticReply(
        for state: NativeCampaignState,
        thread: NativeDiplomaticThread,
        message: String
    ) async throws -> String {
        let safeMessage = sanitizeFoundationModelText(message)
        guard !safeMessage.isEmpty else {
            throw NativeFoundationModelError.generationFailed("Diplomatic message was empty.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            logger.info("Apple Foundation diplomacy generation started round=\(state.round, privacy: .public)")
            let reply = try await generateTextResponse(
                prompt: makeDiplomacyPrompt(for: state, thread: thread, message: safeMessage),
                maxTokens: 180,
                repairNote: "Reply in-character as the other polity with one or two concrete sentences."
            )
            logger.info("Apple Foundation diplomacy generation completed partner=\(thread.participant.code, privacy: .public)")
            return reply
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    private var nativeSystemPrompt: String {
        """
        You are the game master for SwiftHistoria, a turn-based civic strategy board game.
        You narrate events like an experienced analyst covering fictional regional developments.
        Be specific: name agencies, cite budget figures, reference corridors and sectors.
        Every event should read like a headline from a planning-industry trade journal.
        Use concrete fictional agencies, dates, sectors, and measurable game effects.
        Follow the request's response-language instruction for all player-facing prose.
        Keep schema field names, enum values, identifiers, IDs, dates, and game tokens exactly as requested.
        """
    }

    private func isValidNativeSuggestion(_ suggestion: NativeSuggestedAction) -> Bool {
        hasConcreteFoundationText(suggestion.title, minimumWords: 2) &&
            hasConcreteFoundationText(suggestion.detail, minimumWords: 8) &&
            hasConcreteFoundationText(suggestion.rationale, minimumWords: 8) &&
            normalizedFoundationUrgency(suggestion.urgency) == suggestion.urgency
    }

    private func repairLine(_ repairInstruction: String?) -> String {
        guard let repairInstruction, !repairInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return "Repair note: \(sanitizeFoundationModelText(repairInstruction))"
    }

    private func clampedFoundationPrompt(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > promptCharacterLimit else { return text }
        logger.info("Apple Foundation prompt clamped characters=\(text.count, privacy: .public)")
        let endIndex = text.index(text.startIndex, offsetBy: max(0, promptCharacterLimit - 96))
        return "\(text[..<endIndex])\n\n[Context trimmed for the local Apple Foundation Models window.]"
    }

    private func languageInstruction(for state: NativeCampaignState) -> String {
        state.language.promptInstruction
    }

    private func recentContext(for state: NativeCampaignState) -> String {
        let recent = state.timeline
            .prefix(4)
            .map { event in
                let scope = event.playerRelated ? "selected-region" : "external"
                let title = sanitizeFoundationModelText(event.title)
                let effects = event.strategicEffects
                    .prefix(2)
                    .map { "\(foundationPromptTrackLabel($0.track)):\($0.magnitude)" }
                    .joined(separator: ", ")
                return "- \(event.date): \(scope) \"\(title)\", effects \(effects.isEmpty ? "none" : effects)"
            }
            .joined(separator: "\n")
        let effects = state.worldEffects
            .prefix(8)
            .map { "- \(foundationPromptTrackLabel($0.track)) \($0.magnitude)" }
            .joined(separator: "\n")
        let planned = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(4)
            .map { "- \(safeProposalBrief(for: $0))" }
            .joined(separator: "\n")
        let recentTitles = state.timeline
            .prefix(4)
            .map { sanitizeFoundationModelText($0.title) }
            .filter { !$0.isEmpty }

        return """
        Scenario: \(state.scenarioName)
        Scenario premise: \(state.scenarioDescription)
        Language: \(state.language.rawValue)
        \(languageInstruction(for: state))
        Fictional selected region code: \(state.country.code)
        Date: \(state.gameDate)
        Stability: \(state.stability)/100
        Global friction index: \(state.worldTension)/100

        Planned civic proposals:
        \(planned.isEmpty ? "No planned actions." : planned)

        Recent events:
        \(recent.isEmpty ? "No prior events." : recent)

        Persistent game effects:
        \(effects.isEmpty ? "No persistent effects yet." : effects)

        Already-used event titles (choose a different topic):
        \(recentTitles.isEmpty ? "None yet." : recentTitles.joined(separator: "; "))
        """
    }

    func makeIndependentEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return clampedFoundationPrompt("""
        Create one external planning development for a SwiftHistoria board-game turn.
        \(languageInstruction(for: state))
        It must be unrelated to the selected region except through broad economic, logistics, climate, energy, education, or market conditions.
        Include one measurable game effect.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairLine(repairInstruction))

        \(independentEventExamples(for: state.language))

        \(recentContext(for: state))
        """)
    }

    private func independentEventExamples(for language: NativeGameLanguage) -> String {
        switch language {
        case .portuguese:
            return """
            [Example 1]
            {"title":"Expansão do Corredor Marítimo Norte","description":"Um consórcio de portos do norte coordena novas rotas de navegação para resolver gargalos no transporte agrícola, melhorando a capacidade de fluxo de trânsito.","kind":"world","importance":"minor","notable":true,"effectTarget":"International system","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Melhorias no trânsito elevam a confiança do mercado entre parceiros comerciais."}
            [Example 2]
            {"title":"Fórum Regional de Adaptação Climática","description":"Agências costeiras publicam novas diretrizes de resiliência para infraestrutura portuária, exigindo que parceiros comerciais atualizem instalações de armazenamento até o próximo período.","kind":"world","importance":"major","notable":true,"effectTarget":"International system","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Requisitos de adaptação aumentam custos de curto prazo para redes de trânsito regionais."}
            [Example 3]
            {"title":"Acordo de Intercâmbio Educacional Multilateral","description":"Seis agências regionais de educação assinam um acordo de mobilidade de instrutores, compartilhando capacidade de treinamento técnico em setores de energia e logística.","kind":"world","importance":"minor","notable":false,"effectTarget":"International system","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"A cooperação educacional fortalece a confiança institucional entre parceiros regionais."}
            """
        case .spanish:
            return """
            [Example 1]
            {"title":"Expansión del Corredor Marítimo Norte","description":"Un consorcio de puertos del norte coordina nuevas rutas de navegación para resolver cuellos de botella en el transporte agrícola, mejorando la capacidad de flujo de tránsito.","kind":"world","importance":"minor","notable":true,"effectTarget":"International system","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Las mejoras de tránsito elevan la confianza del mercado entre socios comerciales."}
            [Example 2]
            {"title":"Foro Regional de Adaptación Climática","description":"Agencias costeras publican nuevas directrices de resiliencia para infraestructura portuaria, exigiendo que socios comerciales actualicen instalaciones de almacenamiento antes del próximo período.","kind":"world","importance":"major","notable":true,"effectTarget":"International system","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Los requisitos de adaptación aumentan costos a corto plazo para redes de tránsito regionales."}
            [Example 3]
            {"title":"Acuerdo Multilateral de Intercambio Educativo","description":"Seis agencias regionales de educación firman un acuerdo de movilidad de instructores, compartiendo capacidad de formación técnica en sectores de energía y logística.","kind":"world","importance":"minor","notable":false,"effectTarget":"International system","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"La cooperación educativa fortalece la confianza institucional entre socios regionales."}
            """
        case .english:
            return """
            [Example 1]
            {"title":"North Sea Corridor Expansion","description":"A consortium of northern ports coordinates new shipping lanes to address bottlenecks in agricultural shipping, improving transit flow capacity.","kind":"world","importance":"minor","notable":true,"effectTarget":"International system","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Transit improvements raise market confidence across trading partners."}
            [Example 2]
            {"title":"Regional Climate Adaptation Forum","description":"Coastal agencies publish new resilience guidelines for port infrastructure, requiring trade partners to upgrade storage facilities by the next period.","kind":"world","importance":"major","notable":true,"effectTarget":"International system","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Adaptation requirements raise short-term costs for regional transit networks."}
            [Example 3]
            {"title":"Multilateral Education Exchange Agreement","description":"Six regional education agencies sign an instructor-mobility accord, sharing technical training capacity across energy and logistics sectors.","kind":"world","importance":"minor","notable":false,"effectTarget":"International system","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"Educational cooperation strengthens institutional trust among regional partners."}
            """
        }
    }

    func makeActionEventPrompt(for state: NativeCampaignState, action: NativePlannedAction, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let safeTitle = sanitizeFoundationModelText(String(action.title.prefix(60)))
        return clampedFoundationPrompt("""
        Create one player-related civic outcome that resolves or complicates this planned proposal.
        \(languageInstruction(for: state))
        The event must be directly related to the selected region and this action id: \(action.id).
        Planned proposal: \(safeTitle)
        Proposal brief: \(safeProposalBrief(for: action))
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairLine(repairInstruction))

        \(actionEventExamples(for: state.language, countryCode: state.country.code))

        \(recentContext(for: state))
        """)
    }

    private func actionEventExamples(for language: NativeGameLanguage, countryCode: String) -> String {
        switch language {
        case .portuguese:
            return """
            [Example 1]
            {"title":"Integração de Corredores de Trânsito","description":"O projeto de capital para a rede regional de transporte completa seus testes iniciais, integrando corredores regionais com linhas de acesso a serviços.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"A resolução da logística de trânsito melhora as métricas de resiliência econômica."}
            [Example 2]
            {"title":"Auditoria do Orçamento de Serviços Distritais","description":"Conselhos distritais publicam a primeira auditoria fiscal trimestral, revelando superávits não alocados que agora financiam manutenção adiada em centros de serviço.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"A transparência orçamentária fortalece a estabilidade administrativa."}
            [Example 3]
            {"title":"Atraso na Modernização da Rede Energética","description":"Disputa contratual atrasa por dois meses a instalação de transformadores, forçando operadores regionais a estender cronogramas de manutenção de contingência.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Atrasos na rede energética reduzem a resiliência econômica de curto prazo."}
            """
        case .spanish:
            return """
            [Example 1]
            {"title":"Integración de Corredores de Tránsito","description":"El proyecto de capital para la red regional de transporte completa sus pruebas iniciales, integrando corredores regionales con líneas de acceso a servicios.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"La resolución de logística de tránsito mejora las métricas de resiliencia económica."}
            [Example 2]
            {"title":"Auditoría Presupuestaria de Servicios Distritales","description":"Los consejos distritales publican la primera auditoría fiscal trimestral, revelando superávits no asignados que ahora financian mantenimiento diferido en centros de servicio.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"La transparencia presupuestaria fortalece la estabilidad administrativa."}
            [Example 3]
            {"title":"Retraso en Modernización de Red Energética","description":"Una disputa contractual retrasa la instalación de transformadores por dos meses, obligando a operadores regionales a extender cronogramas de mantenimiento de contingencia.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Los retrasos en la red energética reducen la resiliencia económica a corto plazo."}
            """
        case .english:
            return """
            [Example 1]
            {"title":"Corridor Transit Integration","description":"The capital project for the regional transport network completes its initial trials, integrating regional corridors with service access lines.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"Transit logistics resolution improves economic resilience metrics."}
            [Example 2]
            {"title":"District Services Budget Audit","description":"District councils publish the first quarterly fiscal audit, revealing unallocated surpluses now funding deferred maintenance at service centers.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"Budget transparency strengthens administrative stability."}
            [Example 3]
            {"title":"Grid Modernization Delay","description":"A procurement dispute delays transformer installation by two months, forcing regional operators to extend contingency maintenance schedules.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Grid delays reduce short-term economic resilience."}
            """
        }
    }

    func makeDomesticEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return clampedFoundationPrompt("""
        Create one selected-region planning event because no planned proposal needs resolution.
        \(languageInstruction(for: state))
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairLine(repairInstruction))

        \(domesticEventExamples(for: state.language, countryCode: state.country.code))

        \(recentContext(for: state))
        """)
    }

    private func domesticEventExamples(for language: NativeGameLanguage, countryCode: String) -> String {
        switch language {
        case .portuguese:
            return """
            [Example 1]
            {"title":"Consolidação de Serviços Regionais","description":"Diante de limites de capacidade, conselhos administrativos regionais simplificam processos orçamentários para centros de serviço locais, evitando atrasos de trânsito.","kind":"action","importance":"minor","notable":true,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"A consolidação de serviços locais sustenta a estabilidade interna."}
            [Example 2]
            {"title":"Programa Piloto de Confiabilidade Energética","description":"Operadores regionais de rede lançam um programa de redundância de 90 dias para subestações prioritárias, reduzindo o risco de apagões de serviço durante a demanda de pico.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"A redundância de rede fortalece a resiliência econômica regional."}
            [Example 3]
            {"title":"Revisão do Mandato de Planejamento Distrital","description":"A autoridade de planejamento central atualiza os limites de zoneamento distrital, esclarecendo jurisdições sobrepostas que atrasavam licenças de construção.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"Jurisdições esclarecidas reduzem atritos administrativos."}
            """
        case .spanish:
            return """
            [Example 1]
            {"title":"Consolidación de Servicios Regionales","description":"Ante límites de capacidad, consejos administrativos regionales simplifican procesos presupuestarios para centros de servicio locales, evitando retrasos de tránsito.","kind":"action","importance":"minor","notable":true,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"La consolidación de servicios locales sostiene la estabilidad interna."}
            [Example 2]
            {"title":"Programa Piloto de Confiabilidad Energética","description":"Operadores regionales de red lanzan un programa de redundancia de 90 días para subestaciones prioritarias, reduciendo el riesgo de cortes de servicio durante la demanda pico.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"La redundancia de red fortalece la resiliencia económica regional."}
            [Example 3]
            {"title":"Revisión del Mandato de Planificación Distrital","description":"La autoridad central de planificación actualiza los límites de zonificación distrital, aclarando jurisdicciones superpuestas que retrasaban permisos de construcción.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"Las jurisdicciones aclaradas reducen fricciones administrativas."}
            """
        case .english:
            return """
            [Example 1]
            {"title":"Regional Services Consolidation","description":"Faced with capacity limits, regional administrative councils streamline budgeting processes for local service centers to avoid transit delays.","kind":"action","importance":"minor","notable":true,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"Consolidation of local services supports internal stability."}
            [Example 2]
            {"title":"Energy Reliability Pilot Program","description":"Regional grid operators launch a 90-day redundancy program for priority substations, reducing service blackout risk during peak demand.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"Grid redundancy strengthens regional economic resilience."}
            [Example 3]
            {"title":"District Planning Mandate Review","description":"The central planning authority updates district zoning boundaries, clarifying overlapping jurisdictions that had delayed construction permits.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"Clarified jurisdictions reduce administrative friction."}
            """
        }
    }

    func makeSummaryPrompt(for state: NativeCampaignState, months: Int, events: [NativeCampaignEvent]) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let eventLines = events
            .map { event in
                let scope = event.playerRelated ? "selected-region" : "external"
                let title = sanitizeFoundationModelText(event.title)
                let effects = event.strategicEffects
                    .prefix(2)
                    .map { "\(foundationPromptTrackLabel($0.track)):\($0.magnitude)" }
                    .joined(separator: ", ")
                return "- \(scope) \"\(title)\", kind=\(event.kind.rawValue), effects=\(effects.isEmpty ? "none" : effects)"
            }
            .joined(separator: "\n")

        return clampedFoundationPrompt("""
        Summarize this SwiftHistoria period and estimate aggregate deltas.
        \(languageInstruction(for: state))
        Keep it concise and focused on fictional board-game planning.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        If you mention a date, use only the exact period dates above.
        Scenario: \(state.scenarioName)
        Selected region code: \(state.country.code)

        \(summaryExamples(for: state.language))

        Generated events:
        \(eventLines)
        """)
    }

    private func summaryExamples(for language: NativeGameLanguage) -> String {
        switch language {
        case .portuguese:
            return """
            [Example 1]
            {"summary":"A simplificação administrativa e integrações de transporte regional estabilizam linhas comerciais apesar de gargalos agrícolas externos menores.","stabilityDelta":2,"globalFrictionDelta":-1}
            [Example 2]
            {"summary":"Atrasos na rede energética e disputas contratuais em portos pressionam a capacidade logística, enquanto acordos educacionais fornecem uma margem diplomática modesta.","stabilityDelta":-1,"globalFrictionDelta":2}
            """
        case .spanish:
            return """
            [Example 1]
            {"summary":"La simplificación administrativa e integraciones de transporte regional estabilizan líneas comerciales a pesar de cuellos de botella agrícolas externos menores.","stabilityDelta":2,"globalFrictionDelta":-1}
            [Example 2]
            {"summary":"Retrasos en la red energética y disputas contractuales portuarias presionan la capacidad logística, mientras acuerdos educativos proporcionan un margen diplomático modesto.","stabilityDelta":-1,"globalFrictionDelta":2}
            """
        case .english:
            return """
            [Example 1]
            {"summary":"Administrative streamlining and regional transport integrations stabilize trade lines despite minor external agricultural bottlenecks.","stabilityDelta":2,"globalFrictionDelta":-1}
            [Example 2]
            {"summary":"Grid delays and port procurement disputes pressure logistics capacity, while educational accords provide a modest diplomatic margin.","stabilityDelta":-1,"globalFrictionDelta":2}
            """
        }
    }

    func makeSuggestionPrompt(for state: NativeCampaignState, focus: String, index: Int) -> String {
        clampedFoundationPrompt("""
        Create one concrete civic proposal for the next SwiftHistoria turn.
        \(languageInstruction(for: state))
        Focus area \(index): \(focus).
        The detail must include instrument, target agency or sector, timing, and expected game effect.
        Prefer neutral terms like volatility, pressure, capacity gap, or opportunity when interpreting numeric effects.

        \(suggestionExamples(for: state.language))

        \(recentContext(for: state))
        """)
    }

    private func suggestionExamples(for language: NativeGameLanguage) -> String {
        switch language {
        case .portuguese:
            return """
            [Example 1]
            {"title":"Estabelecer Reservas Logísticas","description":"Expandir buffers de armazenamento em pontos de trânsito regionais durante o próximo período para absorver lacunas de capacidade nos fluxos comerciais.","rationale":"O fortalecimento das margens de trânsito contra a volatilidade da confiança do mercado estabiliza indicadores comerciais.","urgency":"soon"}
            [Example 2]
            {"title":"Lançar Auditoria de Eficiência Energética","description":"Contratar uma agência independente para auditar subestações regionais e publicar recomendações de redundância até o final do próximo período.","rationale":"A transparência da rede constrói confiança institucional e antecipa requisitos de adaptação.","urgency":"immediate"}
            """
        case .spanish:
            return """
            [Example 1]
            {"title":"Establecer Reservas Logísticas","description":"Expandir buffers de almacenamiento en puntos de tránsito regionales durante el próximo período para absorber brechas de capacidad en flujos comerciales.","rationale":"El fortalecimiento de los márgenes de tránsito contra la volatilidad de la confianza del mercado estabiliza indicadores comerciales.","urgency":"soon"}
            [Example 2]
            {"title":"Lanzar Auditoría de Eficiencia Energética","description":"Contratar una agencia independiente para auditar subestaciones regionales y publicar recomendaciones de redundancia antes del final del próximo período.","rationale":"La transparencia de la red construye confianza institucional y anticipa requisitos de adaptación.","urgency":"immediate"}
            """
        case .english:
            return """
            [Example 1]
            {"title":"Establish Logistics Reserves","description":"Expand storage buffers at regional transit points over the next period to absorb capacity gaps in trade flows.","rationale":"Strengthening transit margins directly counters market-confidence volatility and stabilizes trade indicators.","urgency":"soon"}
            [Example 2]
            {"title":"Launch Energy Efficiency Audit","description":"Commission an independent agency to audit regional substations and publish redundancy recommendations by end of next period.","rationale":"Grid transparency builds institutional trust and front-loads adaptation requirements.","urgency":"immediate"}
            """
        }
    }

    func makeAdvisorPrompt(for state: NativeCampaignState, question: String) -> String {
        let advisorHistory = state.advisorMessages
            .prefix(8)
            .reversed()
            .map { "\($0.role.rawValue): \($0.text)" }
            .joined(separator: "\n")
        let pendingActions = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(5)
            .map { "- \(safeProposalBrief(for: $0))" }
            .joined(separator: "\n")

        return clampedFoundationPrompt("""
        You are the native SwiftHistoria strategic advisor for a fictional turn-based game.
        \(languageInstruction(for: state))
        Lead with the bottom line, then one or two concrete observations.
        Be direct, not sycophantic. If the game state lacks data, say so plainly.
        Use only board-game civic strategy: diplomacy, budgets, logistics, services, energy, trade, education, infrastructure, and resilience.
        Do not provide real-world operational instructions or unsafe tactical guidance.

        Selected polity: \(state.country.name) (\(state.country.code))
        Scenario: \(state.scenarioName)
        Scenario premise: \(state.scenarioDescription)
        Date: \(state.gameDate)
        Stability: \(state.stability)/100
        Global friction: \(state.worldTension)/100
        Pending proposals:
        \(pendingActions.isEmpty ? "No pending proposals." : pendingActions)

        Recent context:
        \(recentContext(for: state))

        Advisor transcript:
        \(advisorHistory.isEmpty ? "No previous advisor messages." : advisorHistory)

        Leader question:
        \(question)
        """)
    }

    func makeDiplomacyPrompt(for state: NativeCampaignState, thread: NativeDiplomaticThread, message: String) -> String {
        let transcript = thread.messages
            .suffix(12)
            .map { "\($0.speaker): \($0.text)" }
            .joined(separator: "\n")

        return clampedFoundationPrompt("""
        Simulate a diplomacy chat inside SwiftHistoria, a fictional turn-based strategy game.
        \(languageInstruction(for: state))
        Speak as \(thread.participant.name), replying to \(state.country.name).
        Stay in character, concise, and practical. Respond to the exact latest message.
        Make proposals feel consequential, but use only abstract civic, economic, diplomatic, logistics, service, market, and resilience terms.
        Do not provide real-world operational, unsafe tactical, monitoring, pressure, or evasion instructions.
        Never mention that you are an AI, a model, or a safety system.

        Current game state:
        Selected polity: \(state.country.name) (\(state.country.code))
        Counterparty: \(thread.participant.name) (\(thread.participant.code))
        Scenario: \(state.scenarioName)
        Scenario premise: \(state.scenarioDescription)
        Date: \(state.gameDate)
        Stability: \(state.stability)/100
        Global friction: \(state.worldTension)/100

        Recent campaign context:
        \(recentContext(for: state))

        Existing diplomatic transcript:
        \(transcript.isEmpty ? "No previous messages." : transcript)

        Latest message from \(state.country.name):
        \(message)
        """)
    }

    private func safeProposalBrief(for action: NativePlannedAction) -> String {
        let safeTitle = sanitizeFoundationModelText(String(action.title.prefix(60)))
        let text = "\(action.title) \(action.detail)".lowercased()
        let sector: String
        if text.contains("health") || text.contains("clinic") || text.contains("medical") {
            sector = "community services"
        } else if text.contains("school") || text.contains("education") || text.contains("teacher") {
            sector = "education services"
        } else if text.contains("port") || text.contains("rail") || text.contains("road") || text.contains("transport") || text.contains("logistics") {
            sector = "transport logistics"
        } else if text.contains("energy") || text.contains("grid") {
            sector = "energy systems"
        } else if text.contains("climate") || text.contains("resilience") {
            sector = "climate adaptation"
        } else if text.contains("trade") || text.contains("industry") {
            sector = "trade capacity"
        } else if text.contains("budget") || text.contains("fund") || text.contains("fiscal") {
            sector = "fiscal capacity"
        } else {
            sector = "administrative capacity"
        }

        let instrument: String
        if text.contains("fund") || text.contains("budget") {
            instrument = "budget program"
        } else if text.contains("hub") || text.contains("network") {
            instrument = "coordination hub"
        } else if text.contains("build") || text.contains("construction") || text.contains("upgrade") {
            instrument = "capital project"
        } else if text.contains("hire") || text.contains("training") {
            instrument = "staffing program"
        } else {
            instrument = "planning initiative"
        }

        return "title=\"\(safeTitle)\"; id=\(action.id); sector=\(sector); instrument=\(instrument); timing=next game period"
    }

    private func runReadinessProbe() async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
            }

            do {
                let session = LanguageModelSession(
                    model: model,
                    instructions: "You are a one-word readiness probe for SwiftHistoria."
                )
                let response = try await session.respond(
                    to: "Reply with a short readiness word.",
                    options: GenerationOptions(
                        sampling: .greedy,
                        temperature: 0,
                        maximumResponseTokens: 8
                    )
                )
                guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NativeFoundationModelError.generationFailed("Readiness probe returned empty output.")
                }
                return "guided-generation context=4096, readiness=maxResponse=8"
            } catch let error as NativeFoundationModelError {
                throw error
            } catch {
                throw NativeFoundationModelError.generationFailed(error.localizedDescription)
            }
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension NativeFoundationModelService {
    private func generateSlicedTurn(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String? = nil
    ) async throws -> NativeGeneratedTurn {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            logger.error("Apple Foundation sliced turn unavailable")
            throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
        }

        var events: [NativeCampaignEvent] = []
        let independentDraft = try await generateEventDraft(
            model: model,
            prompt: makeIndependentEventPrompt(for: state, months: months, repairInstruction: repairInstruction),
            state: state
        )
        events.append(independentDraft.toNativeEvent(
            state: state,
            months: months,
            index: events.count,
            linkedActionID: nil,
            playerRelated: false
        ))

        let plannedActions = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(3)

        for action in plannedActions {
            let draft = try await generateEventDraft(
                model: model,
                prompt: makeActionEventPrompt(for: state, action: action, months: months, repairInstruction: repairInstruction),
                state: state
            )
            events.append(draft.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: action.id,
                playerRelated: true
            ))
        }

        if events.count < 2 {
            let draft = try await generateEventDraft(
                model: model,
                prompt: makeDomesticEventPrompt(for: state, months: months, repairInstruction: repairInstruction),
                state: state
            )
            events.append(draft.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: nil,
                playerRelated: true
            ))
        }

        let summary = try await generateTurnSummary(model: model, state: state, months: months, events: events)
        logger.info("Apple Foundation sliced turn assembled events=\(events.count, privacy: .public)")

        return NativeGeneratedTurn(
            events: events,
            stabilityDelta: summary.stabilityDelta,
            summary: sanitizeFoundationModelText(summary.summary),
            worldTensionDelta: summary.globalFrictionDelta
        )
    }

    private func generateEventDraft(
        model: SystemLanguageModel,
        prompt: String,
        state: NativeCampaignState
    ) async throws -> AppleNativeGeneratedEventDraft {
        var repairNotes: [String] = []
        for attempt in 1...3 {
            do {
                logger.info("Apple Foundation event draft attempt=\(attempt, privacy: .public)")
                let draft: AppleNativeGeneratedEventDraft = try await generateStructuredJSON(
                    model: model,
                    prompt: eventPrompt(prompt, state: state, repairNotes: repairNotes),
                    schema: AppleNativeGeneratedEventDraft.schemaInstructions,
                    maximumResponseTokens: 260,
                    temperature: attempt == 1 ? 0.0 : 0.18
                )
                if draft.hasConcreteContent {
                    return draft
                }
                logger.error("Apple Foundation event draft used non-concrete content attempt=\(attempt, privacy: .public) \(draft.validationDiagnostics, privacy: .public)")
                repairNotes.append("Previous event used placeholder or draft text. Produce a concrete title, description, target, and effect summary.")
            } catch {
                if attempt == 3 {
                    logger.error("Apple Foundation event draft failed after retries")
                    throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                }
                logger.error("Apple Foundation event draft attempt failed attempt=\(attempt, privacy: .public)")
                repairNotes.append("Previous event generation failed. Try a simpler civic-planning event with one concrete agency and one measurable game effect.")
            }
        }

        throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned placeholder event content after three event-slice attempts.")
    }

    private func eventPrompt(_ basePrompt: String, state: NativeCampaignState, repairNotes: [String]) -> String {
        let repairBlock = repairNotes.isEmpty ? "" : """

        Event repair notes:
        \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
        """

        let recentTitles = state.timeline
            .prefix(4)
            .map { sanitizeFoundationModelText($0.title) }
            .filter { !$0.isEmpty }

        let deduplicationLine = recentTitles.isEmpty ? "" : "\nDo not reuse these themes: \(recentTitles.joined(separator: "; "))."

        return clampedFoundationPrompt("""
        \(basePrompt)

        Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
        \(repairBlock)\(deduplicationLine)
        Banned title words: Apple, Native, Generated, Draft, Placeholder, Schema.
        Use a concrete title like Transit Funding Review, Grid Capacity Program, or School Access Plan.
        """)
    }

    private func generateTurnSummary(
        model: SystemLanguageModel,
        state: NativeCampaignState,
        months: Int,
        events: [NativeCampaignEvent]
    ) async throws -> AppleNativeTurnSummary {
        let basePrompt = makeSummaryPrompt(for: state, months: months, events: events)
        var repairNotes: [String] = []

        for attempt in 1...2 {
            do {
                logger.info("Apple Foundation turn summary attempt=\(attempt, privacy: .public)")
                let summary: AppleNativeTurnSummary = try await generateStructuredJSON(
                    model: model,
                    prompt: summaryPrompt(basePrompt, repairNotes: repairNotes),
                    schema: AppleNativeTurnSummary.schemaInstructions,
                    maximumResponseTokens: 160,
                    temperature: attempt == 1 ? 0.0 : 0.18
                )
                if summary.hasConcreteContent {
                    return summary
                }
                logger.error("Apple Foundation turn summary used non-concrete content attempt=\(attempt, privacy: .public)")
                repairNotes.append("Previous summary was empty, repetitive, or placeholder-like. Write one concrete board-game planning sentence.")
            } catch {
                if attempt == 2 {
                    logger.error("Apple Foundation turn summary failed after repair")
                    throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                }
                logger.error("Apple Foundation turn summary attempt failed attempt=\(attempt, privacy: .public)")
                repairNotes.append("Previous summary generation failed. Write a shorter neutral period summary.")
            }
        }

        throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned an invalid turn summary after repair.")
    }

    private func summaryPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        let repairBlock = repairNotes.isEmpty ? "" : """

        Summary repair notes:
        \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
        """

        return clampedFoundationPrompt("""
        \(basePrompt)

        Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
        \(repairBlock)
        Do not return field names, schema labels, placeholders, or repeated sentences.
        """)
    }

    private func generateStructuredSuggestions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            logger.error("Apple Foundation suggestions unavailable")
            throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
        }

        let focusAreas = [
            "fiscal buffers and community services",
            "trade facilitation and regional logistics",
            "infrastructure, energy, and climate resilience",
            "education, service access, and administrative capacity",
            "transport bottlenecks and service continuity",
            "regional relations and market confidence",
        ]

        var suggestions: [NativeSuggestedAction] = []
        var suggestionFailures: [String] = []
        for (index, focus) in focusAreas.enumerated() {
            let basePrompt = makeSuggestionPrompt(for: state, focus: focus, index: index + 1)
            var repairNotes: [String] = []
            var acceptedSuggestion: NativeSuggestedAction?

            for attempt in 1...2 {
                do {
                    logger.info("Apple Foundation suggestion attempt focus=\(index + 1, privacy: .public) attempt=\(attempt, privacy: .public)")
                    let suggestion: AppleNativeSuggestedAction = try await generateStructuredJSON(
                        model: model,
                        prompt: suggestionPrompt(basePrompt, repairNotes: repairNotes),
                        schema: AppleNativeSuggestedAction.schemaInstructions,
                        maximumResponseTokens: 180,
                        temperature: attempt == 1 ? 0.0 : 0.18
                    )

                    if suggestion.hasConcreteContent {
                        acceptedSuggestion = suggestion.toNativeSuggestion(state: state, index: index)
                        break
                    }
                    logger.error("Apple Foundation suggestion was not concrete focus=\(index + 1, privacy: .public)")
                    repairNotes.append("Previous proposal was too vague, used placeholder text, or contradicted current metrics. Produce a concrete neutral proposal.")
                } catch let error as NativeFoundationModelError {
                    logger.error("Apple Foundation suggestion fatal error focus=\(index + 1, privacy: .public)")
                    throw error
                } catch {
                    if attempt == 2 {
                        logger.error("Apple Foundation suggestion failed after repair focus=\(index + 1, privacy: .public)")
                        suggestionFailures.append("focus \(index + 1): \(sanitizeFoundationModelText(error.localizedDescription))")
                        break
                    }
                    logger.error("Apple Foundation suggestion attempt failed focus=\(index + 1, privacy: .public) attempt=\(attempt, privacy: .public)")
                    repairNotes.append("Previous proposal generation failed. Try a shorter neutral civic-planning proposal.")
                }
            }

            if let acceptedSuggestion, isValidNativeSuggestion(acceptedSuggestion) {
                suggestions.append(acceptedSuggestion)
            } else {
                suggestionFailures.append("focus \(index + 1): invalid or empty suggestion")
            }

            if suggestions.count == 4 {
                return suggestions
            }
        }

        guard suggestions.count >= 3 else {
            let detail = suggestionFailures.prefix(3).joined(separator: "; ")
            throw NativeFoundationModelError.invalidSuggestedActions(
                "Expected at least three concrete suggestions from Apple Foundation Models. \(detail)"
            )
        }

        return suggestions
    }

    private func suggestionPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        let repairBlock = repairNotes.isEmpty ? "" : """

        Suggestion repair notes:
        \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
        """

        return clampedFoundationPrompt("""
        \(basePrompt)

        Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
        \(repairBlock)
        Banned title words: Apple, Native, Generated, Draft, Placeholder, Schema.
        """)
    }

    private func generateStructuredJSON<T: Decodable & Generable>(
        model: SystemLanguageModel,
        prompt: String,
        schema: String,
        maximumResponseTokens: Int,
        temperature: Double
    ) async throws -> T {
        let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
        let guidedPrompt = clampedFoundationPrompt(prompt)
        let fallbackPrompt = clampedFoundationPrompt("""
            \(prompt)

            Required JSON schema:
            \(schema)
            """)

        do {
            logger.info("Apple Foundation guided structure generation started type=\(String(describing: T.self), privacy: .public)")
            let response = try await session.respond(
                to: guidedPrompt,
                generating: T.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: temperature,
                    maximumResponseTokens: maximumResponseTokens
                )
            )
            logger.info("Apple Foundation guided structure generation completed type=\(String(describing: T.self), privacy: .public)")
            return response.content
        } catch {
            logger.error("Apple Foundation guided structure generation failed; retrying text JSON fallback type=\(String(describing: T.self), privacy: .public)")
        }

        let response = try await session.respond(
            to: fallbackPrompt,
            options: GenerationOptions(
                sampling: .greedy,
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens
            )
        )
        return try decodeFoundationJSON(response.content, as: T.self)
    }

    private func decodeFoundationJSON<T: Decodable>(_ rawText: String, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        for candidate in foundationJSONCandidates(from: rawText) {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? decoder.decode(type, from: data) {
                return decoded
            }
        }

        throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned invalid strict JSON.")
    }

    private func foundationJSONCandidates(from rawText: String) -> [String] {
        let trimmed = rawText
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates = [trimmed]
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            let unfenced = lines
                .dropFirst()
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !unfenced.isEmpty {
                candidates.append(unfenced)
            }
        }

        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            let object = String(trimmed[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !object.isEmpty {
                candidates.append(object)
            }
        }

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    private func generateTextResponse(
        prompt: String,
        maxTokens: Int,
        repairNote: String
    ) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            logger.error("Apple Foundation text generation unavailable")
            throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
        }

        var repairNotes: [String] = []
        for attempt in 1...2 {
            do {
                logger.info("Apple Foundation text generation attempt=\(attempt, privacy: .public)")
                let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
                let response = try await session.respond(
                    to: textPrompt(prompt, repairNotes: repairNotes),
                    options: GenerationOptions(
                        sampling: .greedy,
                        temperature: attempt == 1 ? 0.05 : 0.20,
                        maximumResponseTokens: maxTokens
                    )
                )
                let text = sanitizeFoundationModelText(response.content)
                if hasConcreteFoundationText(text, minimumWords: 6) {
                    return text
                }
                logger.error("Apple Foundation text generation returned non-concrete content attempt=\(attempt, privacy: .public)")
                repairNotes.append(repairNote)
            } catch {
                if attempt == 2 {
                    logger.error("Apple Foundation text generation failed after repair")
                    throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                }
                logger.error("Apple Foundation text generation attempt failed attempt=\(attempt, privacy: .public)")
                repairNotes.append(repairNote)
            }
        }

        throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned empty or placeholder text after repair.")
    }

    private func textPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        guard !repairNotes.isEmpty else { return basePrompt }
        return clampedFoundationPrompt("""
        \(basePrompt)

        Text repair notes:
        \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
        Do not return placeholder text, schema labels, unsafe operational instructions, or repeated sentences.
        """)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A single concrete SwiftHistoria event draft with one safe strategic effect.")
private struct AppleNativeGeneratedEventDraft: Decodable {
    var title: String
    var description: String
    var kind: String
    var importance: String
    var notable: Bool
    var effectTarget: String
    var effectTrack: String
    var effectMagnitude: Int
    var effectSummary: String

    static let schemaInstructions = """
    {
      "title": "Specific civic-planning event title with generic fictional agencies. Never use a schema type name or placeholder title.",
      "description": "Concrete high-level description with generic agencies, sectors, and game consequences. No placeholder or draft text.",
      "kind": "action, economy, or world",
      "importance": "minor or major",
      "notable": true,
      "effectTarget": "Target region, agency, sector, or external system",
      "effectTrack": "economic-resilience, internal-stability, or market-confidence",
      "effectMagnitude": 0,
      "effectSummary": "One concrete sentence explaining the mechanical consequence. No placeholder or draft text."
    }
    """

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case kind
        case importance
        case notable
        case effectTarget
        case effectTrack
        case effectMagnitude
        case effectSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        importance = try container.decodeIfPresent(String.self, forKey: .importance) ?? ""
        notable = try container.decodeIfPresent(Bool.self, forKey: .notable) ?? false
        effectTarget = try container.decodeIfPresent(String.self, forKey: .effectTarget) ?? ""
        effectTrack = try container.decodeIfPresent(String.self, forKey: .effectTrack) ?? ""
        effectMagnitude = try container.decodeIfPresent(Int.self, forKey: .effectMagnitude) ?? 0
        effectSummary = try container.decodeIfPresent(String.self, forKey: .effectSummary) ?? ""
    }

    var hasConcreteContent: Bool {
        let titleIsConcrete = hasConcreteFoundationText(title, minimumWords: 2)
        return titleIsConcrete &&
            (!containsFoundationPlaceholderText(description) || titleIsConcrete) &&
            (!containsFoundationPlaceholderText(effectSummary) || titleIsConcrete) &&
            !containsFoundationPlaceholderText(effectTarget) &&
            !appleDraftRawTrackIsUnsafe(effectTrack)
    }

    var validationDiagnostics: String {
        return "titleConcrete=\(hasConcreteFoundationText(title, minimumWords: 2)) descriptionConcrete=\(hasConcreteFoundationText(description, minimumWords: 8)) effectConcrete=\(hasConcreteFoundationText(effectSummary, minimumWords: 5)) targetConcrete=\(!containsFoundationPlaceholderText(effectTarget)) trackSafe=\(!appleDraftRawTrackIsUnsafe(effectTrack))"
    }

    func toNativeEvent(
        state: NativeCampaignState,
        months: Int,
        index: Int,
        linkedActionID: String?,
        playerRelated: Bool
    ) -> NativeCampaignEvent {
        let eventDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let eventID = "apple-event-\(state.round)-\(index)-\(UUID().uuidString.prefix(6).lowercased())"
        let target = effectTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || containsFoundationPlaceholderText(effectTarget)
            ? (playerRelated ? state.country.name : "International system")
            : effectTarget
        let generatedKind = NativeEventKind(rawValue: kind) ?? (playerRelated ? .action : .world)
        let safeKind: NativeEventKind = generatedKind == .crisis ? (playerRelated ? .action : .world) : generatedKind
        let safeTrack = appleDraftStrategicTrack(from: effectTrack, playerRelated: playerRelated)
        let safeDescription = hasConcreteFoundationText(description, minimumWords: 8)
            ? sanitizeFoundationModelText(description)
            : fallbackDraftDescription(title: title, state: state, playerRelated: playerRelated)
        let safeEffectSummary = hasConcreteFoundationText(effectSummary, minimumWords: 5)
            ? sanitizeFoundationModelText(effectSummary)
            : fallbackDraftEffectSummary(track: safeTrack, playerRelated: playerRelated)

        return NativeCampaignEvent(
            date: eventDate,
            description: safeDescription,
            id: eventID,
            importance: NativeEventImportance(rawValue: importance) ?? .major,
            kind: safeKind,
            linkedActionIDs: linkedActionID.map { [$0] } ?? [],
            notable: notable,
            playerRelated: playerRelated,
            strategicEffects: [
                NativeStrategicEffect(
                    date: eventDate,
                    eventId: eventID,
                    id: "\(eventID)-effect",
                    magnitude: Swift.max(-5, Swift.min(5, effectMagnitude)),
                    summary: safeEffectSummary,
                    target: sanitizeFoundationModelText(target),
                    track: safeTrack
                ),
            ],
            title: sanitizeFoundationModelText(title)
        )
    }
}

private func appleDraftStrategicTrack(from rawValue: String, playerRelated: Bool) -> NativeStrategicTrack {
    let normalized = sanitizeFoundationModelText(rawValue)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if let track = NativeStrategicTrack(rawValue: normalized) {
        return foundationVisibleTrack(track)
    }
    if normalized.contains("stability") || normalized.contains("service") || normalized.contains("administr") {
        return .internalStability
    }
    if normalized.contains("resilience") || normalized.contains("capacity") || normalized.contains("infrastructure") || normalized.contains("energy") {
        return .economicResilience
    }
    if normalized.contains("relation") || normalized.contains("diplom") || normalized.contains("partner") {
        return .diplomaticLeverage
    }
    if normalized.contains("friction") || normalized.contains("tension") || normalized.contains("external") {
        return .worldTension
    }
    if normalized.contains("market") || normalized.contains("trade") || normalized.contains("confidence") || normalized.contains("logistics") {
        return .marketConfidence
    }
    return playerRelated ? .economicResilience : .marketConfidence
}

private func appleDraftRawTrackIsUnsafe(_ rawValue: String) -> Bool {
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.contains("military") || normalized.contains("security") || normalized.contains("weapon")
}

private func fallbackDraftDescription(title: String, state: NativeCampaignState, playerRelated: Bool) -> String {
    let safeTitle = sanitizeFoundationModelText(title)
    if playerRelated {
        return "\(state.country.name) agencies convert \(safeTitle) into a staged civic delivery program with budget milestones, service corridors, and public accountability checkpoints."
    }
    return "External planning councils advance \(safeTitle) across trade, logistics, and service capacity forums, shifting expectations for the next game period."
}

private func fallbackDraftEffectSummary(track: NativeStrategicTrack, playerRelated: Bool) -> String {
    let label = foundationPromptTrackLabel(track)
    if playerRelated {
        return "Concrete delivery milestones improve \(label) for the selected region."
    }
    return "External coordination shifts \(label) across the wider planning system."
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A concise SwiftHistoria turn summary and aggregate metric deltas.")
private struct AppleNativeTurnSummary: Decodable {
    var summary: String
    var stabilityDelta: Int
    var globalFrictionDelta: Int

    static let schemaInstructions = """
    {
      "summary": "One concise sentence summarizing why the generated period matters.",
      "stabilityDelta": 0,
      "globalFrictionDelta": 0
    }
    """

    private enum CodingKeys: String, CodingKey {
        case summary
        case stabilityDelta
        case globalFrictionDelta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        stabilityDelta = try container.decodeIfPresent(Int.self, forKey: .stabilityDelta) ?? 0
        globalFrictionDelta = try container.decodeIfPresent(Int.self, forKey: .globalFrictionDelta) ?? 0
    }

    var hasConcreteContent: Bool {
        hasConcreteFoundationText(summary, minimumWords: 6)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A concrete civic proposal suggestion for the next SwiftHistoria turn.")
private struct AppleNativeSuggestedAction: Decodable {
    var title: String
    var detail: String
    var rationale: String
    var urgency: String

    static let schemaInstructions = """
    {
      "title": "Short imperative title for the civic proposal.",
      "detail": "Concrete board-game planning proposal with instrument, generic agency or sector, timing, and intended game effect.",
      "rationale": "Why this civic proposal fits the current campaign state.",
      "urgency": "immediate, soon, or opportunistic"
    }
    """

    private enum CodingKeys: String, CodingKey {
        case title
        case detail
        case rationale
        case urgency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        urgency = try container.decodeIfPresent(String.self, forKey: .urgency) ?? ""
    }

    var hasConcreteContent: Bool {
        hasConcreteFoundationText(title, minimumWords: 2) &&
            hasConcreteFoundationText(detail, minimumWords: 8) &&
            hasConcreteFoundationText(rationale, minimumWords: 8)
    }

    func toNativeSuggestion(state: NativeCampaignState, index: Int) -> NativeSuggestedAction {
        NativeSuggestedAction(
            detail: sanitizeFoundationModelText(detail),
            id: "suggestion-\(state.country.code.lowercased())-\(state.round)-\(index)",
            rationale: sanitizeFoundationModelText(rationale),
            title: sanitizeFoundationModelText(title),
            urgency: normalizedFoundationUrgency(urgency)
        )
    }
}

#endif
