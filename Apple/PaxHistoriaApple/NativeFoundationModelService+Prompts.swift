import Foundation
#if canImport(FoundationModels)
    import FoundationModels
    import OSLog
#endif

/// Prompt builders for the Apple Foundation Model service.
extension NativeFoundationModelService {
    func isValidNativeSuggestion(_ suggestion: NativeSuggestedAction) -> Bool {
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

    func clampedFoundationPrompt(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > promptCharacterLimit else { return text }
        logger.info("Apple Foundation prompt clamped characters=\(text.count, privacy: .public)")
        return NativePromptHarness.clamped(text, characterLimit: promptCharacterLimit)
    }

    private func hexLeverCodeInstruction() -> String {
        """
        Hexadecimal Lever Code option:
        You can OPTIONALLY output a `"hexLeverCode"` representing standard economic deltas and abstract map-control nudges. Use only high-level board-game state changes: public security, insurgency pressure, conventional border pressure, nuclear fallout, contested borders, stabilization, or de-escalation. Do not include operational instructions.
        Six-character values encode Growth, Budget, Debt, Inflation, Trade, and Fiscal Space. Eight-character values add a signed public-security nibble and a map nudge nibble.
        Map nudge nibble meanings: 0 none, 1 conventional border advance, 2 guerrilla control, 3 nuclear fallout, 4 domestic stabilization, 5 contested border, 6 public-security recovery, 7 conquest occupation, F de-escalation.
        Sovereignty change option:
        Use the sovereignty fields only for formal political changes, not ordinary occupation or insurgency. Kinds: `secession` creates a breakaway country from listed regionIDs/sourceCodes; `new-country` recognizes a new country; `merge` folds sourceCodes into targetCode; `dissolution` breaks a country into contested local control. Keep sovereigntyTargetCode uppercase A-Z, 3-6 characters. Leave fields empty for normal events.
        If you choose to use a hex code, pick one of the following exact examples or a close variant that follows the same 6-or-8-nibble contract:
        - `"0x4D21F4"` for Infrastructure Boost (Growth +0.4%, Budget -0.15%, Debt +0.4%, Inflation +0.05%, Trade -0.05%, Fiscal Space +4)
        - `"0x4D21F461"` for Infrastructure Boost plus conventional border advance (public security +15, map nudge 1)
        - `"0xCD42D882"` for Guerrilla Surge (economic shock, public security -20, map nudge 2)
        - `"0xCD42D883"` for Nuclear Fallout (economic shock, public security -20, map nudge 3)
        - `"0x1F1F0264"` for Stabilization Recovery (administrative streamlining, public security +15, map nudge 4)
        - `"0x22FDF305"` for Contested Border (trade diplomacy with no security delta, map nudge 5)
        - `"0x11FF1266"` for Public Security Recovery (market confidence, public security +15, map nudge 6)
        - `"0x3D21F447"` for Conquest Occupation (growth +0.3%, public security +10, map nudge 7)
        - `"0x11FF120F"` for De-escalation (market confidence, no security delta, map nudge F)
        - `"0x0D0004"` for Budget Reserve Buffer (Growth 0.0%, Budget -0.15%, Debt 0.0%, Inflation 0.0%, Trade 0.0%, Fiscal Space +4)
        - `"0x1F1F02"` for Administrative Streamlining (Growth +0.1%, Budget -0.05%, Debt +0.2%, Inflation -0.05%, Trade 0.0%, Fiscal Space +2)
        - `"0x22FDF3"` for Trade Diplomacy (Growth +0.2%, Budget +0.1%, Debt -0.2%, Inflation -0.1%, Trade +0.25%, Fiscal Space +3)
        - `"0x11FF12"` for Market confidence signaling (Growth +0.1%, Budget +0.05%, Debt -0.2%, Inflation -0.05%, Trade +0.05%, Fiscal Space +2)
        - `"0xCD42D8"` for External Shock/Recession (Growth -0.4%, Budget -0.15%, Debt +0.8%, Inflation +0.1%, Trade -0.15%, Fiscal Space -3)
        Otherwise, set `"hexLeverCode"` to null.
        """
    }

    private func promptPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func promptSignedPercent(_ value: Double) -> String {
        String(format: "%+.2f%%", value)
    }

    private func mechanicsContract(for state: NativeCampaignState) -> String {
        let ledger = state.economicLedger
        let conflictLines = state.regionConflicts.values
            .sorted { lhs, rhs in lhs.regionID < rhs.regionID }
            .prefix(5)
            .map { conflict in
                "- \(conflict.regionID): \(conflict.mode.displayName), controller \(conflict.controllerCode), intensity \(conflict.intensity)/5, \(sanitizeFoundationModelText(conflict.summary))"
            }
            .joined(separator: "\n")
        let diplomacyLines = state.diplomaticThreads
            .prefix(4)
            .map { thread in
                "- \(thread.participant.code): \(sanitizeFoundationModelText(thread.summary))"
            }
            .joined(separator: "\n")
        let pendingCount = state.plannedActions.filter { $0.status == .planned }.count
        let suggestedCount = state.suggestedActions.count

        return """
        Mechanics checklist:
        - Tie every event, suggestion, advisor answer, or diplomatic reply to at least one stored mechanic: planned actions/action memory, economic ledger, public security, insurgency pressure, map conflict, diplomacy/global friction, timeline/world effects, scenario canon, language, or AI readiness.
        - Economy mechanics include GDP, growth, inflation, budget balance, public debt, trade balance, unemployment, and fiscal space.
        - Security mechanics include public security, insurgency pressure, stabilization, contested borders, conventional occupation, guerrilla control, nuclear fallout, and de-escalation as abstract board-game states.
        - Map mechanics are stored in regionOccupations, nuclearFalloutRegions, and regionConflicts; prose should explain the strategic state, while events can use hexLeverCode for bounded map nudges.
        - Occupation, contested borders, guerrilla control, and stabilization are control changes, not new countries. Use sovereignty fields only when a polity formally secedes, is newly recognized, merges, or dissolves.
        - Suggestions must name the primary mechanic they intend to improve and a secondary mechanic that may trade off or benefit.
        - Advisor and diplomacy replies must read the same mechanics instead of inventing new hidden systems.

        Current selected ledger:
        GDP \(String(format: "$%.2fT", ledger.nominalGDPTrillions)); growth \(promptSignedPercent(ledger.realGrowthPercent)); inflation \(promptPercent(ledger.inflationPercent)); budget \(promptSignedPercent(ledger.budgetBalancePercentGDP)) of GDP; debt \(promptPercent(ledger.publicDebtPercentGDP)) of GDP; trade \(promptSignedPercent(ledger.tradeBalancePercentGDP)) of GDP; unemployment \(promptPercent(ledger.unemploymentPercent)); fiscal space \(ledger.fiscalSpaceIndex)/100; public security \(String(format: "%.1f", ledger.securityIndex))/100; insurgency pressure \(String(format: "%.1f%%", ledger.rebelControlPercent)).

        Current map conflict state:
        \(conflictLines.isEmpty ? "- No active region conflict records." : conflictLines)

        Current diplomacy state:
        \(diplomacyLines.isEmpty ? "- No active diplomatic threads." : diplomacyLines)

        Current action/suggestion state:
        pending planned actions \(pendingCount); visible suggestions \(suggestedCount).
        """
    }

    private func languageInstruction(for state: NativeCampaignState) -> String {
        state.language.promptInstruction
    }

    private func mechanicsReminder() -> String {
        "Mechanics checklist anchors: read the economic ledger, public security, insurgency pressure, map conflict, regionConflicts, diplomacy/global friction, and hexLeverCode rules where relevant; only event JSON may output hexLeverCode."
    }

    private func recentContext(for state: NativeCampaignState) -> String {
        // The local model should see a compact evidence packet rather than the
        // full save file. This keeps prompts inside the local context window and
        // makes generated events traceable to stored facts, action memory, and
        // ledger state.
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
        let objectives = NativeGameEngine.campaignObjectives(for: state)
            .map { objective in
                "- \(objective.title): \(objective.currentValue) / \(objective.targetValue), deadline \(objective.deadline), \(sanitizeFoundationModelText(objective.detail))"
            }
            .joined(separator: "\n")
        let canonContext = state.startDate == Native2010WorldModel.historicalStartDate
            ? Native2010WorldModel.promptContext(for: state)
            : "Scenario canon: respect the selected scenario start date \(state.startDate) as the authoritative opening state."

        return """
        Scenario: \(state.scenarioName)
        Scenario premise: \(state.scenarioDescription)
        Language: \(state.language.rawValue)
        \(languageInstruction(for: state))
        Selected country code: \(state.country.code)
        Date: \(state.gameDate)
        Stability: \(state.stability)/100
        Global friction index: \(state.worldTension)/100

        \(mechanicsContract(for: state))

        Campaign objectives:
        \(objectives.isEmpty ? "No explicit campaign objectives." : objectives)

        Historical/campaign canon:
        \(canonContext)

        Strategy database:
        \(NativeStrategyContextDatabase.promptPacket(for: state, months: 1))

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
        Create one external planning development for a SwiftHistoria game turn.
        \(languageInstruction(for: state))
        \(mechanicsReminder())
        It must be unrelated to the selected region except through broad economic, logistics, climate, energy, education, or market conditions.
        Include one measurable game effect.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairLine(repairInstruction))

        \(independentEventExamples(for: state.language))

        \(recentContext(for: state))
        """)
    }

    func makeGlobalAIActionsPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)

        let aiDetails = state.aiCountryStates.sorted(by: { $0.key < $1.key }).map { code, aiState in
            "- \(code): doctrine=\(aiState.doctrine.rawValue), agenda=\"\(aiState.multiTurnAgenda)\""
        }.joined(separator: "\n")

        return clampedFoundationPrompt("""
        Create one geopolitical or economic action event initiated by one of the autonomous non-player countries.
        \(languageInstruction(for: state))
        \(mechanicsReminder())
        Look at their doctrines and multi-turn agendas:
        \(aiDetails)

        Author an event representing an action taken by one of these countries to advance their agenda.
        The event must target the initiator country or one of its rivals, altering market confidence, global friction, or stability.

        Use the 'hexLeverCode' to nudge conflict borders or economic ledgers for the initiator or target.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairLine(repairInstruction))

        \(hexLeverCodeInstruction())

        Examples:
        [Example 1]
        {"title":"China Secures Highland Resource Access","description":"China completes a transit corridor integration with neighboring highland districts, securing primary resource inputs to advance its mercantile doctrine.","kind":"world","importance":"major","notable":true,"effectTarget":"CHN","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"Corridor integration secures resource supply, raising economic resilience.","hexLeverCode":"0x120004"}
        [Example 2]
        {"title":"US Reinforces Pacific Maritime Security","description":"The United States deploys logistics units to Pacific trade corridors to counter competitor maritime pressure, reinforcing its collaborative defense doctrine.","kind":"world","importance":"major","notable":true,"effectTarget":"USA","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Logistics patrols stabilize maritime trade routes, bolstering confidence.","hexLeverCode":"0x0D0004"}

        \(recentContext(for: state))
        """)
    }

    func makeEconomicEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return clampedFoundationPrompt("""
        Create one selected-region economic assessment event for a SwiftHistoria game turn.
        \(languageInstruction(for: state))
        \(mechanicsReminder())
        Focus on budget surplus or deficit, fiscal space, debt pressure, inflation, growth, trade balance, unemployment, and the cost of planned commitments.
        Include one measurable game effect using either market-confidence or economic-resilience.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairLine(repairInstruction))

        \(hexLeverCodeInstruction())

        Economic examples:
        [Example 1]
        {"title":"Quarterly Fiscal Outlook Narrows","description":"The treasury office updates its revenue forecast after weaker customs intake and higher service commitments, trimming available fiscal space for the next planning period.","kind":"economy","importance":"major","notable":true,"effectTarget":"\(state.country.code)","effectTrack":"market-confidence","effectMagnitude":-1,"effectSummary":"A narrower budget balance weighs on market confidence and slows discretionary spending.","hexLeverCode":"0x0D0004"}
        [Example 2]
        {"title":"Investment Pipeline Lifts Growth Estimate","description":"Regional finance agencies approve a sequenced capital pipeline that spreads costs over two budget cycles while improving logistics capacity for export sectors.","kind":"economy","importance":"minor","notable":false,"effectTarget":"\(state.country.code)","effectTrack":"economic-resilience","effectMagnitude":1,"effectSummary":"Phased investment preserves fiscal space while raising expected growth resilience.","hexLeverCode":"0x4D21F4"}

        Current strategy database for this turn:
        \(NativeStrategyContextDatabase.promptPacket(for: state, months: months))

        \(recentContext(for: state))
        """)
    }

    private func independentEventExamples(for language: NativeGameLanguage) -> String {
        switch language {
        case .portuguese:
            """
            [Example 1]
            {"title":"Expansão do Corredor Marítimo Norte","description":"Um consórcio de portos do norte coordena novas rotas de navegação para resolver gargalos no transporte agrícola, melhorando a capacidade de fluxo de trânsito.","kind":"world","importance":"minor","notable":true,"effectTarget":"International system","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Melhorias no trânsito elevam a confiança do mercado entre parceiros comerciais."}
            [Example 2]
            {"title":"Fórum Regional de Adaptação Climática","description":"Agências costeiras publicam novas diretrizes de resiliência para infraestrutura portuária, exigindo que parceiros comerciais atualizem instalações de armazenamento até o próximo período.","kind":"world","importance":"major","notable":true,"effectTarget":"International system","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Requisitos de adaptação aumentam custos de curto prazo para redes de trânsito regionais."}
            [Example 3]
            {"title":"Acordo de Intercâmbio Educacional Multilateral","description":"Seis agências regionais de educação assinam um acordo de mobilidade de instrutores, compartilhando capacidade de treinamento técnico em setores de energia e logística.","kind":"world","importance":"minor","notable":false,"effectTarget":"International system","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"A cooperação educacional fortalece a confiança institucional entre parceiros regionais."}
            """
        case .spanish:
            """
            [Example 1]
            {"title":"Expansión del Corredor Marítimo Norte","description":"Un consorcio de puertos del norte coordina nuevas rutas de navegación para resolver cuellos de botella en el transporte agrícola, mejorando la capacidad de flujo de tránsito.","kind":"world","importance":"minor","notable":true,"effectTarget":"International system","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Las mejoras de tránsito elevan la confianza del mercado entre socios comerciales."}
            [Example 2]
            {"title":"Foro Regional de Adaptación Climática","description":"Agencias costeras publican nuevas directrices de resiliencia para infraestructura portuaria, exigiendo que socios comerciales actualicen instalaciones de almacenamiento antes del próximo período.","kind":"world","importance":"major","notable":true,"effectTarget":"International system","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Los requisitos de adaptación aumentan costos a corto plazo para redes de tránsito regionales."}
            [Example 3]
            {"title":"Acuerdo Multilateral de Intercambio Educativo","description":"Seis agencias regionales de educación firman un acuerdo de movilidad de instructores, compartiendo capacidad de formación técnica en sectores de energía y logística.","kind":"world","importance":"minor","notable":false,"effectTarget":"International system","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"La cooperación educativa fortalece la confianza institucional entre socios regionales."}
            """
        case .english:
            """
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
        \(mechanicsReminder())
        The event must be directly related to the selected region and this action id: \(action.id).
        Planned proposal: \(safeTitle)
        Proposal brief: \(safeProposalBrief(for: action))
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairLine(repairInstruction))

        \(actionEventExamples(for: state.language, countryCode: state.country.code))

        \(hexLeverCodeInstruction())

        Action-specific facts and consequence ranges:
        \(NativeStrategyContextDatabase.promptPacket(for: state, months: months, action: action))

        \(recentContext(for: state))
        """)
    }

    private func actionEventExamples(for language: NativeGameLanguage, countryCode: String) -> String {
        switch language {
        case .portuguese:
            """
            [Example 1]
            {"title":"Integração de Corredores de Trânsito","description":"O projeto de capital para a rede regional de transporte completa seus testes iniciais, integrando corredores regionais com linhas de acesso a serviços.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"A resolução da logística de trânsito melhora as métricas de resiliência econômica."}
            [Example 2]
            {"title":"Auditoria do Orçamento de Serviços Distritais","description":"Conselhos distritais publicam a primeira auditoria fiscal trimestral, revelando superávits não alocados que agora financiam manutenção adiada em centros de serviço.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"A transparência orçamentária fortalece a estabilidade administrativa."}
            [Example 3]
            {"title":"Atraso na Modernização da Rede Energética","description":"Disputa contratual atrasa por dois meses a instalação de transformadores, forçando operadores regionais a estender cronogramas de manutenção de contingência.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Atrasos na rede energética reduzem a resiliência econômica de curto prazo."}
            """
        case .spanish:
            """
            [Example 1]
            {"title":"Integración de Corredores de Tránsito","description":"El proyecto de capital para la red regional de transporte completa sus pruebas iniciales, integrando corredores regionales con líneas de acceso a servicios.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"La resolución de logística de tránsito mejora las métricas de resiliencia económica."}
            [Example 2]
            {"title":"Auditoría Presupuestaria de Servicios Distritales","description":"Los consejos distritales publican la primera auditoría fiscal trimestral, revelando superávits no asignados que ahora financian mantenimiento diferido en centros de servicio.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"La transparencia presupuestaria fortalece la estabilidad administrativa."}
            [Example 3]
            {"title":"Retraso en Modernización de Red Energética","description":"Una disputa contractual retrasa la instalación de transformadores por dos meses, obligando a operadores regionales a extender cronogramas de mantenimiento de contingencia.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":-1,"effectSummary":"Los retrasos en la red energética reducen la resiliencia económica a corto plazo."}
            """
        case .english:
            """
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
        \(mechanicsReminder())
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairLine(repairInstruction))

        \(hexLeverCodeInstruction())

        \(domesticEventExamples(for: state.language, countryCode: state.country.code))

        \(recentContext(for: state))
        """)
    }

    private func domesticEventExamples(for language: NativeGameLanguage, countryCode: String) -> String {
        switch language {
        case .portuguese:
            """
            [Example 1]
            {"title":"Consolidação de Serviços Regionais","description":"Diante de limites de capacidade, conselhos administrativos regionais simplificam processos orçamentários para centros de serviço locais, evitando atrasos de trânsito.","kind":"action","importance":"minor","notable":true,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"A consolidação de serviços locais sustenta a estabilidade interna."}
            [Example 2]
            {"title":"Programa Piloto de Confiabilidade Energética","description":"Operadores regionais de rede lançam um programa de redundância de 90 dias para subestações prioritárias, reduzindo o risco de apagões de serviço durante a demanda de pico.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"A redundância de rede fortalece a resiliência econômica regional."}
            [Example 3]
            {"title":"Revisão do Mandato de Planejamento Distrital","description":"A autoridade de planejamento central atualiza os limites de zoneamento distrital, esclarecendo jurisdições sobrepostas que atrasavam licenças de construção.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"Jurisdições esclarecidas reduzem atritos administrativos."}
            """
        case .spanish:
            """
            [Example 1]
            {"title":"Consolidación de Servicios Regionales","description":"Ante límites de capacidad, consejos administrativos regionales simplifican procesos presupuestarios para centros de servicio locales, evitando retrasos de tránsito.","kind":"action","importance":"minor","notable":true,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"La consolidación de servicios locales sostiene la estabilidad interna."}
            [Example 2]
            {"title":"Programa Piloto de Confiabilidad Energética","description":"Operadores regionales de red lanzan un programa de redundancia de 90 días para subestaciones prioritarias, reduciendo el riesgo de cortes de servicio durante la demanda pico.","kind":"action","importance":"major","notable":true,"effectTarget":"\(countryCode)","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"La redundancia de red fortalece la resiliencia económica regional."}
            [Example 3]
            {"title":"Revisión del Mandato de Planificación Distrital","description":"La autoridad central de planificación actualiza los límites de zonificación distrital, aclarando jurisdicciones superpuestas que retrasaban permisos de construcción.","kind":"action","importance":"minor","notable":false,"effectTarget":"\(countryCode)","effectTrack":"internal-stability","effectMagnitude":1,"effectSummary":"Las jurisdicciones aclaradas reducen fricciones administrativas."}
            """
        case .english:
            """
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
        \(mechanicsReminder())
        Keep it concise and focused on fictional board-game planning.
        Connect the summary deltas to the same mechanics contract used by generated events.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        If you mention a date, use only the exact period dates above.
        Scenario: \(state.scenarioName)
        Selected region code: \(state.country.code)

        \(mechanicsContract(for: state))

        Current strategy database:
        \(NativeStrategyContextDatabase.promptPacket(for: state, months: months))

        \(summaryExamples(for: state.language))

        Generated events:
        \(eventLines)
        """)
    }

    private func summaryExamples(for language: NativeGameLanguage) -> String {
        switch language {
        case .portuguese:
            """
            [Example 1]
            {"summary":"A simplificação administrativa e integrações de transporte regional estabilizam linhas comerciais apesar de gargalos agrícolas externos menores.","stabilityDelta":2,"globalFrictionDelta":-1}
            [Example 2]
            {"summary":"Atrasos na rede energética e disputas contratuais em portos pressionam a capacidade logística, enquanto acordos educacionais fornecem uma margem diplomática modesta.","stabilityDelta":-1,"globalFrictionDelta":2}
            """
        case .spanish:
            """
            [Example 1]
            {"summary":"La simplificación administrativa e integraciones de transporte regional estabilizan líneas comerciales a pesar de cuellos de botella agrícolas externos menores.","stabilityDelta":2,"globalFrictionDelta":-1}
            [Example 2]
            {"summary":"Retrasos en la red energética y disputas contractuales portuarias presionan la capacidad logística, mientras acuerdos educativos proporcionan un margen diplomático modesto.","stabilityDelta":-1,"globalFrictionDelta":2}
            """
        case .english:
            """
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
        \(mechanicsReminder())
        Focus area \(index): \(focus).
        The proposal must be accept-ready: a player should be able to add it to the order queue without rewriting it.
        Respect current administrative capacity \(state.administrativeCapacity)/100; avoid plans that imply more capacity than remains.
        The detail must include instrument, target agency or sector, timing, and expected game effect.
        The detail must name a bounded policy instrument, not a vague national goal.
        The rationale must explicitly name the primary affected mechanic, one connected secondary mechanic, and why this fits the current campaign objectives.
        Prefer neutral terms like volatility, pressure, capacity gap, or opportunity when interpreting numeric effects.

        \(suggestionExamples(for: state.language))

        \(recentContext(for: state))
        """)
    }

    func makeSuggestionBatchPrompt(for state: NativeCampaignState, focusAreas: [String]) -> String {
        let focusList = focusAreas.enumerated()
            .map { index, focus in "\(index + 1). \(focus)" }
            .joined(separator: "\n")

        return clampedFoundationPrompt("""
        Create exactly four concrete civic proposals for the next SwiftHistoria turn.
        \(languageInstruction(for: state))
        \(mechanicsReminder())
        Use these focus areas, one proposal per focus:
        \(focusList)
        Each proposal must be accept-ready: a player should be able to add it to the order queue without rewriting it.
        Respect current administrative capacity \(state.administrativeCapacity)/100; avoid plans that imply more capacity than remains.
        Each detail must include instrument, target agency or sector, timing, expected game effect, primary affected mechanic, and secondary mechanic.
        Each detail must name a bounded policy instrument, not a vague national goal.
        Each rationale must explain why the proposal fits the current campaign objectives and ledger/map/diplomacy context.
        Prefer neutral terms like volatility, pressure, capacity gap, or opportunity when interpreting numeric effects.

        \(suggestionExamples(for: state.language))

        \(recentContext(for: state))
        """)
    }

    private func suggestionExamples(for language: NativeGameLanguage) -> String {
        switch language {
        case .portuguese:
            """
            [Example 1]
            {"title":"Estabelecer Reservas Logísticas","detail":"Expandir buffers de armazenamento em pontos de trânsito regionais durante o próximo período; mecânica primária: trade balance; mecânica secundária: market confidence.","rationale":"O fortalecimento das margens de trânsito responde ao saldo comercial atual e reduz volatilidade na confiança do mercado.","urgency":"soon"}
            [Example 2]
            {"title":"Lançar Auditoria de Eficiência Energética","detail":"Contratar uma agência independente para auditar subestações regionais e publicar recomendações até o final do próximo período; mecânica primária: economic resilience; mecânica secundária: fiscal space.","rationale":"A transparência da rede melhora resiliência econômica sem ocultar o custo fiscal de adaptação.","urgency":"immediate"}
            """
        case .spanish:
            """
            [Example 1]
            {"title":"Establecer Reservas Logísticas","detail":"Expandir buffers de almacenamiento en puntos de tránsito regionales durante el próximo período; mecánica primaria: trade balance; mecánica secundaria: market confidence.","rationale":"El fortalecimiento de los márgenes de tránsito responde al saldo comercial actual y reduce volatilidad en la confianza del mercado.","urgency":"soon"}
            [Example 2]
            {"title":"Lanzar Auditoría de Eficiencia Energética","detail":"Contratar una agencia independiente para auditar subestaciones regionales y publicar recomendaciones antes del final del próximo período; mecánica primaria: economic resilience; mecánica secundaria: fiscal space.","rationale":"La transparencia de la red mejora la resiliencia económica sin ocultar el costo fiscal de adaptación.","urgency":"immediate"}
            """
        case .english:
            """
            [Example 1]
            {"title":"Establish Logistics Reserves","detail":"Expand storage buffers at regional transit points over the next period; primary mechanic: trade balance; secondary mechanic: market confidence.","rationale":"Strengthening transit margins fits the current trade balance and reduces market-confidence volatility.","urgency":"soon"}
            [Example 2]
            {"title":"Launch Energy Efficiency Audit","detail":"Commission an independent agency to audit regional substations and publish recommendations by end of next period; primary mechanic: economic resilience; secondary mechanic: fiscal space.","rationale":"Grid transparency improves economic resilience while making the fiscal-space tradeoff visible.","urgency":"immediate"}
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
        You are the native SwiftHistoria strategic advisor for an alternate-history turn-based strategy game anchored to the campaign state.
        \(languageInstruction(for: state))
        \(mechanicsReminder())
        Lead with the bottom line, then one or two concrete observations.
        Be direct, not sycophantic. If the game state lacks data, say so plainly.
        Use only board-game civic strategy: diplomacy, budgets, logistics, services, energy, trade, education, infrastructure, public security, insurgency pressure, map conflict, and resilience.
        Do not provide real-world operational instructions or unsafe tactical guidance.
        Treat the encoded campaign state as canon; never present post-start-date facts as if they already happened.

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

        let counterpartCode = thread.participant.code
        let relationshipScore = state.aiCountryStates[counterpartCode]?.relationshipScores[state.country.code] ?? 0
        let counterpartDoctrine = state.aiCountryStates[counterpartCode]?.doctrine.rawValue ?? "isolationist"
        let counterpartAgenda = state.aiCountryStates[counterpartCode]?.multiTurnAgenda ?? "maintain status quo"

        return clampedFoundationPrompt("""
        Simulate a diplomacy chat inside SwiftHistoria, an alternate-history turn-based strategy game anchored to the campaign state.
        \(languageInstruction(for: state))
        \(mechanicsReminder())
        Speak as \(thread.participant.name), replying to \(state.country.name).
        Stay in character, concise, and practical. Respond to the exact latest message.
        Make proposals feel consequential, but use only abstract civic, economic, diplomatic, logistics, service, market, public-security, map-conflict, and resilience terms.
        Do not provide real-world operational, unsafe tactical, monitoring, pressure, or evasion instructions.
        Never mention that you are an AI, a model, or a safety system.
        Treat the encoded campaign state as canon; never present post-start-date facts as if they already happened.

        Current game state:
        Selected polity: \(state.country.name) (\(state.country.code))
        Counterparty: \(thread.participant.name) (\(thread.participant.code))
        Counterparty Doctrine: \(counterpartDoctrine)
        Counterparty Active Agenda: \(counterpartAgenda)
        Current Relationship Score with \(state.country.name): \(relationshipScore) (-100 to 100 range; negative is hostile, positive is collaborative/allied)
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
        let sector = if text.contains("health") || text.contains("clinic") || text.contains("medical") {
            "community services"
        } else if text.contains("school") || text.contains("education") || text.contains("teacher") {
            "education services"
        } else if text.contains("port") || text.contains("rail") || text.contains("road") || text.contains("transport") || text.contains("logistics") {
            "transport logistics"
        } else if text.contains("energy") || text.contains("grid") {
            "energy systems"
        } else if text.contains("climate") || text.contains("resilience") {
            "climate adaptation"
        } else if text.contains("trade") || text.contains("industry") {
            "trade capacity"
        } else if text.contains("budget") || text.contains("fund") || text.contains("fiscal") {
            "fiscal capacity"
        } else {
            "administrative capacity"
        }

        let instrument = if text.contains("fund") || text.contains("budget") {
            "budget program"
        } else if text.contains("hub") || text.contains("network") {
            "coordination hub"
        } else if text.contains("build") || text.contains("construction") || text.contains("upgrade") {
            "capital project"
        } else if text.contains("hire") || text.contains("training") {
            "staffing program"
        } else {
            "planning initiative"
        }

        return "title=\"\(safeTitle)\"; id=\(action.id); sector=\(sector); instrument=\(instrument); timing=next game period"
    }
}
