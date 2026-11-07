import Foundation

// MARK: - Living World: localized prose pipeline

//
// Every procedurally generated string in Living World resolves through
// LWProse. Design contract:
// - Tables are in-code and keyed by `NativeGameLanguage`, NOT
//   `String(localized:)`: xcstrings resolves from the *device* locale, which
//   would make the same save render differently per device. The save carries
//   its language; prose follows the save.
// - Interpolation is plain `{placeholder}` substitution. Values come from
//   world state only — never from Date(), Locale, or UUID — so the same seed
//   + same decisions ⇒ identical history in every language.
// - Prose resolves at generation time and is persisted inside the event
//   record, so historical records keep the language they were generated in.
// - Country names come from the world catalog (unlocalized); templates adapt
//   grammar around them.

enum LWProseKey: String, CaseIterable {
    // War & peace events (NativeLivingWorldTick.swift)
    case peaceTitle
    case peaceSummary
    case warGoalConcessions
    case warDeclarationTitle
    case warDeclarationSummary
    case allianceTitle
    case allianceSummary
    // Ambient events
    case dispatchTitle
    case flavorHarvest
    case flavorStrikers
    case flavorTariff
    case flavorBanking
    case flavorRailway
    case crisisTitle
    case crisisSummary
    // Session status lines (NativeLivingWorldSession.swift)
    case worldHoldsBreath
    case situationWarSingular
    case situationWarPlural
    case situationPeace
    // Commentary fragments (state-grounded, seeded assembly)
    case sitAtWar
    case sitDeficit
    case sitMobilized
    case sitSteady
    case causeInfamy
    case causeRadicals
    case causeThreat
    case causePeace
    case outlookCaution
    case outlookAmbition
    case outlookTrade
    case outlookOpportunity
    // HUD situation line (NativeLivingWorldUI.swift, date-first variant)
    case uiSituationWar
    case uiSituationPeace
    // Decision interruption & modal prose (NativeLivingWorldTick.swift & NativeLivingWorldUI.swift)
    case decisionPendingPrefix
    case decisionPendingPrompt
    case decisionAIResponseLabel
    case decisionPlayerDirectiveLabel
    case decisionDefaultOptionLabel
    case decisionDefaultOptionDetail
    case uiDecisionRequiredBadge
    case uiExecutiveDecisionHeader
    case uiPolicyDirectivesHeader
    case uiChainTag
}

enum LWProse {
    /// Resolves `key` in `language`, falling back to English, with
    /// `{placeholder}` interpolation. Never returns an empty string.
    static func string(_ key: LWProseKey, language: NativeGameLanguage, _ interp: [String: String] = [:]) -> String {
        let template = tables[key]?[language] ?? tables[key]?[.english] ?? key.rawValue
        return interp.reduce(template) { partial, pair in
            partial.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    /// Seeded pick from the localized daily-dispatch flavor stream.
    static func dispatchFlavor(language: NativeGameLanguage, country: String, rng: LWRNG, stream: String) -> String {
        let flavors: [LWProseKey] = [.flavorHarvest, .flavorStrikers, .flavorTariff, .flavorBanking, .flavorRailway]
        let key = flavors[rng.int(stream, in: 0 ..< flavors.count)]
        return string(key, language: language, ["country": country])
    }

    /// Localizes a `LWDecisionEvent` and its options into the active world language.
    /// English returns the canonical event untouched; Portuguese and Spanish resolve
    /// through deterministic in-code translation tables.
    static func localizeDecision(_ event: LWDecisionEvent, language: NativeGameLanguage) -> LWDecisionEvent {
        guard language != .english else { return event }

        let lookupID: String = if event.id.hasPrefix("lw-general-strike-") {
            "lw-general-strike"
        } else if event.id.hasPrefix("lw-debt-spiral-") {
            "lw-debt-spiral"
        } else {
            event.id
        }

        let localizedTitle: String
        let localizedSummary: String
        if let entry = decisionEventTranslations[lookupID]?[language] {
            localizedTitle = entry.title
            localizedSummary = entry.summary
        } else {
            localizedTitle = localizeCatalogPhrase(event.title, language: language)
            localizedSummary = localizeCatalogPhrase(event.summary, language: language)
        }

        let localizedOptions = event.options.map { opt -> LWDecisionOption in
            let label: String
            let detail: String
            if let optEntry = decisionOptionTranslations[opt.id]?[language] {
                label = optEntry.label
                detail = optEntry.detail
            } else {
                label = localizeCatalogPhrase(opt.label, language: language)
                detail = localizeCatalogPhrase(opt.detail, language: language)
            }
            return LWDecisionOption(
                id: opt.id,
                label: label,
                detail: detail,
                treasuryDelta: opt.treasuryDelta,
                radicalsDelta: opt.radicalsDelta,
                stabilityDelta: opt.stabilityDelta,
                worldTensionDelta: opt.worldTensionDelta,
                nextChainedEventID: opt.nextChainedEventID,
                flagSet: opt.flagSet,
                mechanicCode: opt.mechanicCode
            )
        }

        return LWDecisionEvent(
            id: event.id,
            day: event.day,
            title: localizedTitle,
            summary: localizedSummary,
            countryCode: event.countryCode,
            rarity: event.rarity,
            severity: event.severity,
            imageAssetName: event.imageAssetName,
            chainID: event.chainID,
            options: localizedOptions
        )
    }

    private static func localizeCatalogPhrase(_ text: String, language: NativeGameLanguage) -> String {
        guard language != .english else { return text }
        let replacements: [(String, String, String)] = [
            ("Direct Sovereign Credit to", "Direcionar Crédito Soberano a", "Dirigir Crédito Soberano a"),
            ("Enact National Charter for", "Promulgar Carta Nacional para", "Promulgar Carta Nacional para"),
            ("Mobilize State Capacity for", "Mobilizar Capacidade Estatal para", "Movilizar Capacidad Estatal para"),
            ("Authorize Executive Mandate on", "Autorizar Mandato Executivo sobre", "Autorizar Mandato Ejecutivo sobre"),
            ("Capitalize Public Authority for", "Capitalizar Autoridade Pública para", "Capitalizar Autoridad Pública para"),
            ("Charter Commercial Syndicate for", "Licenciar Sindicato Comercial para", "Licenciar Sindicato Comercial para"),
            ("Open Multilateral Clearing on", "Abrir Compensação Multilateral em", "Abrir Compensación Multilateral en"),
            ("License Regional Consortium for", "Habilitar Consórcio Regional para", "Habilitar Consorcio Regional para"),
            ("Co-Finance Private Tenders on", "Cofinanciar Licitações Privadas em", "Cofinanciar Licitaciones Privadas en"),
            ("Broker Stakeholder Compact on", "Mediar Pacto Setorial sobre", "Mediar Pacto Sectorial sobre"),
            ("Executive council directs emergency policy formulation to secure long-term sovereign autonomy.", "O conselho executivo determina medidas de emergência para assegurar a autonomia soberana.", "El consejo ejecutivo ordena medidas de emergencia para asegurar la autonomía soberana."),
            ("Direct ", "Direcionar ", "Dirigir "),
            ("Commit ", "Comprometer ", "Comprometer "),
            ("Authorize ", "Autorizar ", "Autorizar "),
            ("Mobilize ", "Mobilizar ", "Movilizar "),
            ("Coordinate ", "Coordenar ", "Coordinar "),
            ("Balance ", "Equilibrar ", "Equilibrar "),
            ("Empower ", "Capacitar ", "Empoderar "),
            ("Enact ", "Promulgar ", "Promulgar "),
            ("Establish ", "Estabelecer ", "Establecer "),
            ("Deploy ", "Mobilizar ", "Desplegar "),
            ("Convene ", "Convocar ", "Convocar "),
            ("Ratify ", "Ratificar ", "Ratificar "),
            ("Enforce ", "Aplicar ", "Aplicar ")
        ]
        var result = text
        for (en, pt, es) in replacements {
            let target = language == .portuguese ? pt : es
            result = result.replacingOccurrences(of: en, with: target)
        }
        return result
    }

    static let tables: [LWProseKey: [NativeGameLanguage: String]] = [
        .peaceTitle: [
            .english: "Peace: {goal}",
            .portuguese: "Paz: {goal}",
            .spanish: "Paz: {goal}"
        ],
        .peaceSummary: [
            .english: "{winner} dictates terms; {loser} concedes.",
            .portuguese: "{winner} dita as condições; {loser} cede.",
            .spanish: "{winner} dicta las condiciones; {loser} cede."
        ],
        .warGoalConcessions: [
            .english: "Concessions from {country}",
            .portuguese: "Concessões de {country}",
            .spanish: "Concesiones de {country}"
        ],
        .warDeclarationTitle: [
            .english: "{country} declares war on {target}",
            .portuguese: "{country} declara guerra a {target}",
            .spanish: "{country} declara la guerra a {target}"
        ],
        .warDeclarationSummary: [
            .english: "Armies mobilize along the border; embassies are withdrawn.",
            .portuguese: "Exércitos mobilizam-se na fronteira; embaixadas são retiradas.",
            .spanish: "Los ejércitos se movilizan en la frontera; las embajadas se retiran."
        ],
        .allianceTitle: [
            .english: "Alliance signed",
            .portuguese: "Aliança assinada",
            .spanish: "Alianza firmada"
        ],
        .allianceSummary: [
            .english: "{country} and {target} enter a defensive alliance.",
            .portuguese: "{country} e {target} firmam uma aliança defensiva.",
            .spanish: "{country} y {target} forman una alianza defensiva."
        ],
        .dispatchTitle: [
            .english: "Dispatch from {country}",
            .portuguese: "Despacho de {country}",
            .spanish: "Despacho de {country}"
        ],
        .flavorHarvest: [
            .english: "A bumper harvest steadies grain prices in {country}.",
            .portuguese: "Uma colheita farta estabiliza os preços do trigo em {country}.",
            .spanish: "Una cosecha abundante estabiliza los precios del grano en {country}."
        ],
        .flavorStrikers: [
            .english: "Strikers blockade the docks of {country}.",
            .portuguese: "Grevistas bloqueiam os portos de {country}.",
            .spanish: "Los huelguistas bloquean los puertos de {country}."
        ],
        .flavorTariff: [
            .english: "{country}'s parliament debates tariff reform.",
            .portuguese: "O parlamento de {country} debate a reforma tarifária.",
            .spanish: "El parlamento de {country} debate la reforma arancelaria."
        ],
        .flavorBanking: [
            .english: "A banking scandal rattles confidence in {country}.",
            .portuguese: "Um escândalo bancário abala a confiança em {country}.",
            .spanish: "Un escándalo bancario sacude la confianza en {country}."
        ],
        .flavorRailway: [
            .english: "Railway expansion reaches the interior of {country}.",
            .portuguese: "A expansão ferroviária alcança o interior de {country}.",
            .spanish: "La expansión ferroviária llega al interior de {country}."
        ],
        .crisisTitle: [
            .english: "Crisis in {country}",
            .portuguese: "Crise em {country}",
            .spanish: "Crisis en {country}"
        ],
        .crisisSummary: [
            .english: "Riots erupt over the price of bread; the government scrambles to respond.",
            .portuguese: "Manifestações explodem pelo preço do pão; o governo corre para responder.",
            .spanish: "Estallan disturbios por el precio del pan; el gobierno se apresura a responder."
        ],
        .worldHoldsBreath: [
            .english: "The world holds its breath.",
            .portuguese: "O mundo prende a respiração.",
            .spanish: "El mundo contiene la respiración."
        ],
        .situationWarSingular: [
            .english: "{wars} war rages among {powers} great powers — {date}.",
            .portuguese: "{wars} guerra assola {powers} grandes potências — {date}.",
            .spanish: "{wars} guerra azota {powers} grandes potencias — {date}."
        ],
        .situationWarPlural: [
            .english: "{wars} wars rage among {powers} great powers — {date}.",
            .portuguese: "{wars} guerras assolam {powers} grandes potências — {date}.",
            .spanish: "{wars} guerras azotan {powers} grandes potencias — {date}."
        ],
        .situationPeace: [
            .english: "An uneasy peace holds among {powers} great powers — {date}.",
            .portuguese: "Uma paz instável persiste entre {powers} grandes potências — {date}.",
            .spanish: "Una paz inquieta se mantiene entre {powers} grandes potencias — {date}."
        ],

        // MARK: Commentary fragments — every fragment names its country so the

        // assembled line always satisfies the "names its country" contract.
        .sitAtWar: [
            .english: "{country}'s armies hold active fronts.",
            .portuguese: "Os exércitos da {country} mantêm frentes ativas.",
            .spanish: "Los ejércitos de {country} sostienen frentes activos."
        ],
        .sitDeficit: [
            .english: "{country} runs a deficit and the treasury urges moderation.",
            .portuguese: "A {country} registra déficit e o tesouro pede moderação.",
            .spanish: "{country} registra déficit y el tesouro pide moderación."
        ],
        .sitMobilized: [
            .english: "{country} keeps its reserves mobilized while markets stay open.",
            .portuguese: "A {country} mantém suas reservas mobilizadas enquanto os mercados seguem abertos.",
            .spanish: "{country} mantiene sus reservas movilizadas mientras los mercados siguen abiertos."
        ],
        .sitSteady: [
            .english: "{country} enjoys steady finances and quiet borders.",
            .portuguese: "A {country} desfruta de finanças estáveis e fronteiras tranquilas.",
            .spanish: "{country} disfruta de finanzas estables y fronteras tranquilas."
        ],
        .causeInfamy: [
            .english: "Foreign chancelleries denounce {country}'s appetite for conquest.",
            .portuguese: "Chancelarias estrangeiras denunciam o apetite de conquista da {country}.",
            .spanish: "Las cancillerías extranjeras denuncian el apetito conquistador de {country}."
        ],
        .causeRadicals: [
            .english: "Restive crowds keep {country}'s police busy.",
            .portuguese: "Multitudes inquietas mantêm a polícia da {country} ocupada.",
            .spanish: "Multitudes inquietas mantienen ocupada a la policía de {country}."
        ],
        .causeThreat: [
            .english: "{country}'s staff officers watch the borders with concern.",
            .portuguese: "Os oficiais da {country} observam as fronteiras com preocupação.",
            .spanish: "Los oficiales de {country} observan las fronteras con preocupación."
        ],
        .causePeace: [
            .english: "{country}'s chancellery drafts memoranda and waits.",
            .portuguese: "A chancelaria da {country} redige memorandos e aguarda.",
            .spanish: "La cancillería de {country} redacta memorandos y espera."
        ],
        .outlookCaution: [
            .english: "The government counsels patience.",
            .portuguese: "O governo aconselha paciência.",
            .spanish: "El gobierno aconseja paciencia."
        ],
        .outlookAmbition: [
            .english: "Ambition hums in every ministry.",
            .portuguese: "A ambição vibra em todos os ministérios.",
            .spanish: "La ambición vibra en todos los ministerios."
        ],
        .outlookTrade: [
            .english: "The merchant classes champion quiet trade.",
            .portuguese: "As classes mercantis defendem o comércio tranquilo.",
            .spanish: "Las clases mercantiles defienden el comercio tranquilo."
        ],
        .outlookOpportunity: [
            .english: "Every distant quarrel reads like an opening.",
            .portuguese: "Cada querela distante parece uma oportunidade.",
            .spanish: "Cada querella lejana parece una oportunidad."
        ],
        .uiSituationWar: [
            .english: "{date} — {wars} war(s) rage across the world",
            .portuguese: "{date} — {wars} guerra(s) assolam o mundo",
            .spanish: "{date} — {wars} guerra(s) azotan el mundo"
        ],
        .uiSituationPeace: [
            .english: "{date} — an uneasy peace holds",
            .portuguese: "{date} — uma paz instável persiste",
            .spanish: "{date} — una paz inquieta se mantiene"
        ],
        .decisionPendingPrefix: [
            .english: "CRITICAL DECISION:",
            .portuguese: "DECISÃO CRÍTICA:",
            .spanish: "DECISIÓN CRÍTICA:"
        ],
        .decisionPendingPrompt: [
            .english: "The executive must select a response to proceed.",
            .portuguese: "O executivo deve escolher uma diretriz para prosseguir.",
            .spanish: "El ejecutivo debe elegir una directriz para continuar."
        ],
        .decisionAIResponseLabel: [
            .english: "Government response:",
            .portuguese: "Resposta do governo:",
            .spanish: "Respuesta del gobierno:"
        ],
        .decisionPlayerDirectiveLabel: [
            .english: "Executive Directive Formed:",
            .portuguese: "Diretriz Executiva Formada:",
            .spanish: "Directriz Ejecutiva Formada:"
        ],
        .decisionDefaultOptionLabel: [
            .english: "Acknowledge",
            .portuguese: "Registrar",
            .spanish: "Reconocer"
        ],
        .decisionDefaultOptionDetail: [
            .english: "Government observes developments.",
            .portuguese: "O governo acompanha os desdobramentos.",
            .spanish: "El gobierno observa los acontecimientos."
        ],
        .uiDecisionRequiredBadge: [
            .english: "DECISION REQUIRED",
            .portuguese: "DECISÃO NECESSÁRIA",
            .spanish: "DECISIÓN REQUERIDA"
        ],
        .uiExecutiveDecisionHeader: [
            .english: "EXECUTIVE DECISION REQUIRED",
            .portuguese: "DECISÃO EXECUTIVA NECESSÁRIA",
            .spanish: "DECISIÓN EJECUTIVA REQUERIDA"
        ],
        .uiPolicyDirectivesHeader: [
            .english: "POLICY DIRECTIVES",
            .portuguese: "DIRETRIZES DE POLÍTICA",
            .spanish: "DIRECTRICES DE POLÍTICA"
        ],
        .uiChainTag: [
            .english: "⟦CHAIN⟧",
            .portuguese: "⟦CADEIA⟧",
            .spanish: "⟦CADENA⟧"
        ]
    ]

    private static let decisionEventTranslations: [String: [NativeGameLanguage: (title: String, summary: String)]] = [
        "soviet-miners-strike": [
            .portuguese: (
                "Greve Geral dos Mineiros de Donbas e Locautes Fabris",
                "Mais de 120.000 mineiros de carvão apagam altos-fornos na bacia industrial, cortando o carvão metalúrgico e o gás de calefação na chegada do inverno."
            ),
            .spanish: (
                "Huelga General de Mineros del Donbás y Cierres Patronales",
                "Más de 120.000 mineros del carbón apagan altos hornos en la cuenca industrial, cortando el carbón metalúrgico y el gas de calefacción al llegar el invierno."
            )
        ],
        "soviet-ogas-launch": [
            .portuguese: (
                "Diretriz 44: Lançamento da Rede Cibernética OGAS-2",
                "Matrizes de mainframes nos ministérios industriais são interconectadas por fibras ópticas, automatizando alocações em 24.000 empresas estatais."
            ),
            .spanish: (
                "Directiva 44: Lanzamiento de la Red Cibernética OGAS-2",
                "Matrices de mainframes en los ministerios industriales se interconectan por fibra óptica, automatizando asignaciones en 24.000 empresas estatales."
            )
        ],
        "soviet-techno-bloc": [
            .portuguese: (
                "União Aduaneira do Tecnobloco Vermelho do Comecon",
                "Um mercado comum tecnológico fechado é estabelecido com Berlim Oriental, Varsóvia e Minsk liquidando operações em Inforrublos digitais."
            ),
            .spanish: (
                "Unión Aduanera del Tecnobloque Rojo del Comecon",
                "Se establece un mercado común tecnológico cerrado con Berlín Oriental, Varsovia y Minsk liquidando operaciones en Inforrublos digitales."
            )
        ],
        "fashoda-channel-mobilization": [
            .portuguese: (
                "Mobilização da Frota do Canal e Impasse em Toulon",
                "Esquadras de batalha concentram-se em Portsmouth e Toulon à medida que aceleram os preparativos de guerra pela crise do Nilo."
            ),
            .spanish: (
                "Movilización de la Flota del Canal e Impasse en Tolón",
                "Escuadras de batalla se concentran en Portsmouth y Tolón mientras se aceleran los preparativos de guerra por la crisis del Nilo."
            )
        ],
        "fashoda-continental-league": [
            .portuguese: (
                "A Liga Continental de Berlim: O Gambito do Kaiser",
                "Diplomatas reúnem-se em Berlim para negociar uma aliança tripartite equilibrando a supremacia naval britânica no Atlântico e no Índico."
            ),
            .spanish: (
                "La Liga Continental de Berlín: El Gambito del Káiser",
                "Diplomáticos se reúnen en Berlín para negociar una alianza tripartita que equilibre la supremacía naval británica en el Atlántico y el Índico."
            )
        ],
        "fashoda-dreadnought-panic": [
            .portuguese: (
                "O Pânico dos Dreadnoughts: Corrida Naval no Mar do Norte",
                "Encouraçados a turbina tornam obsoletas as frotas existentes da noite para o dia, desencadeando debates de emergência no parlamento."
            ),
            .spanish: (
                "El Pánico de los Dreadnoughts: Carrera Naval en el Mar del Norte",
                "Los acorazados de turbina vuelven obsoletas las flotas existentes de la noche a la mañana, desatando debates de emergencia en el parlamento."
            )
        ],
        "cyber-microgrid-secession": [
            .portuguese: (
                "Cisão das Microrredes Inteligentes: Secessão Energética Biorregional",
                "Cooperativas agrárias e distritos municipais desconectam-se das redes de alta tensão para formar redes solares e de baterias autônomas."
            ),
            .spanish: (
                "Escisión de Microrredes Inteligentes: Secesión Energética Biorregional",
                "Cooperativas agrarias y distritos municipales se desconectan de las redes de alta tensión hacia redes solares y de baterías autónomas."
            )
        ],
        "resource-fertilizer-crisis": [
            .portuguese: (
                "Déficit Global de Fertilizantes Nitrogenados e Motins do Pão",
                "Gargalos no suprimento de gás natural fecham fábricas de fertilizantes sintéticos. Preços de ureia saltam 220%, gerando protestos."
            ),
            .spanish: (
                "Déficit Global de Fertilizantes Nitrogenados y Motines del Pan",
                "Cuellos de botella en el gas natural cierran plantas de fertilizantes sintéticos. Los precios de la urea suben un 220%, provocando protestas."
            )
        ],
        "lw-grain-surge": [
            .portuguese: (
                "Disparo no Preço do Trigo e Insegurança Alimentar",
                "Os mercados de grãos subiram mais de 50% acima da linha de base. Orçamentos familiares sofrem pressão e padarias racionam farinha."
            ),
            .spanish: (
                "Alza en el Precio del Grano e Inseguridad Alimentaria",
                "Los mercados de granos han subido más del 50% sobre la línea base. Los presupuestos obreros sufren presión y las panaderías racionan harina."
            )
        ],
        "lw-general-strike": [
            .portuguese: (
                "Greve Geral e Piquetes Fabris",
                "Sindicatos radicalizados e operários cruzam os braços, bloqueando pátios ferroviários e altos-fornos em protesto contra o custo de vida."
            ),
            .spanish: (
                "Huelga General y Piquetes Fabriles",
                "Sindicatos radicalizados y obreros industriales paran labores, bloqueando patios ferroviarios y altos hornos en protesta por las condiciones de vida."
            )
        ],
        "lw-debt-spiral": [
            .portuguese: (
                "Exaustão de Liquidez do Tesouro e Espiral da Dívida",
                "As reservas estatais estão próximas de zero enquanto a arrecadação mal cobre obrigações administrativas. Credores congelam emissões."
            ),
            .spanish: (
                "Agotamiento de Liquidez del Tesoro y Espiral de Deuda",
                "Las reservas estatales están cerca de cero mientras los ingresos fiscales apenas cubren obligaciones administrativas. Los acreedores congelan bonos."
            )
        ],
        "lw-barracks-rebellion": [
            .portuguese: (
                "A Defecção dos Quartéis e Ultimato da Junta Militar",
                "Comandantes de guarnição na capital recusam-se a reprimir manifestações civis, emitindo manifesto por reorganização constitucional."
            ),
            .spanish: (
                "La Defección de los Cuarteles y Ultimátum de la Junta Militar",
                "Comandantes de guarnición en la capital se niegan a disparar contra manifestaciones civiles, exigiendo reorganización constitucional."
            )
        ],
        "soviet-coup-sweep": [
            .portuguese: (
                "A Operação Arkhangelskoye: Comitê Estatal de Emergência",
                "Unidades Alfa detêm líderes reformistas fora de Moscou. O Comitê Estatal de Emergência assume o controle executivo com blindados nas ruas."
            ),
            .spanish: (
                "La Operación Arjánguelskoye: Comité Estatal de Emergencia",
                "Unidades Alfa detienen a líderes reformistas fuera de Moscú. El Comité Estatal de Emergencia asume el control ejecutivo con blindados en las calles."
            )
        ],
        "fashoda-confrontation": [
            .portuguese: (
                "As Canhoneiras de Fashoda: Ultimato no Vale do Nilo",
                "Expedições coloniais de impérios rivais confrontam-se em um forte no Alto Nilo. Canhoneiras trocam advertências enquanto a crise chega às capitais."
            ),
            .spanish: (
                "Las Cañoneras de Fachoda: Ultimátum en el Valle del Nilo",
                "Expediciones coloniales de imperios rivales se enfrentan en un fuerte del Alto Nilo. Cañoneras intercambian advertencias mientras la crisis llega a las capitales."
            )
        ],
        "resource-aquifer-crisis": [
            .portuguese: (
                "Exaustão do Aquífero Indo-Ganges e Moratória de Irrigação",
                "O esgotamento catastrófico de águas subterrâneas força a proibição emergencial de poços agrícolas, deflagrando disputas transfronteiriças."
            ),
            .spanish: (
                "Agotamiento del Acuífero Indo-Ganges y Moratoria de Riego",
                "El agotamiento catastrófico del agua subterránea fuerza una prohibición de emergencia de pozos agrícolas, desatando disputas transfronterizas."
            )
        ],
        "cyber-fiber-blackout": [
            .portuguese: (
                "A Fratura das Fibras Submarinas: Colapso Algorítmico",
                "Cortes simultâneos em cabos oceânicos cegam corredores internacionais de compensação. DAOs autônomas disparam US$ 4T em liquidações em cascata."
            ),
            .spanish: (
                "La Fractura de Fibra Submarina: Colapso Algorítmico",
                "Cortes simultáneos en troncales oceánicos ciegan los corredores internacionales de compensación. DAOs autónomas desatan US$ 4T en liquidaciones en cascada."
            )
        ]
    ]

    private static let decisionOptionTranslations: [String: [NativeGameLanguage: (label: String, detail: String)]] = [
        "soviet-miners-force": [
            .portuguese: ("Mobilizar Tropas Internas nas Minas", "Guarnecer poços de mineração com destacamentos armados para impor cotas de extração."),
            .spanish: ("Desplegar Tropas Internas en las Minas", "Guarnecer pozos mineros con destacamentos armados para imponer cuotas de extracción.")
        ],
        "soviet-miners-integrate": [
            .portuguese: ("Integrar Comitês de Greve aos Conselhos Digitais da Gosplan", "Oferecer assentos de planejamento digital e indexação salarial para encerrar a paralisação."),
            .spanish: ("Integrar Comités de Huelga en los Consejos Digitales del Gosplán", "Ofrecer puestos de planificación digital e indexación salarial para poner fin al paro.")
        ],
        "soviet-ogas-quotas": [
            .portuguese: ("Impor Cotas Automatizadas às Empresas Estatais", "Alocações automatizadas de insumo-produto contornam a burocracia regional."),
            .spanish: ("Imponer Cuotas Automatizadas a las Empresas Estatales", "Las asignaciones automatizadas de insumo-producto eluden la burocracia regional.")
        ],
        "soviet-ogas-dual": [
            .portuguese: ("Permitir Comércio Eletrônico de Dupla Via entre Empresas", "Autorizar empresas a negociar excedentes acima da cota em bolsas digitais monitoradas."),
            .spanish: ("Permitir Comercio Electrónico de Doble Vía entre Empresas", "Autorizar a las empresas a negociar excedentes sobre la cuota en bolsas digitales supervisadas.")
        ],
        "soviet-techno-fabs": [
            .portuguese: ("Subsidiar Fábricas de Litografia em Dresden e Minsk", "Financiar manufatura autóctone de microchips para blindar o bloco contra embargos ocidentais."),
            .spanish: ("Subsidiar Plantas de Litografía en Dresde y Minsk", "Financiar fabricación autóctona de microchips para blindar al bloque frente a embargos occidentales.")
        ],
        "soviet-techno-nordic": [
            .portuguese: ("Oferecer Pactos de Energia por Tecnologia aos Neutros Nórdicos", "Trocar gás natural siberiano por maquinário escandinavo de telecomunicações."),
            .spanish: ("Ofrecer Pactos de Energía por Tecnología a los Neutrales Nórdicos", "Intercambiar gas natural siberiano por maquinaria escandinava de telecomunicaciones.")
        ],
        "fashoda-channel-league": [
            .portuguese: ("Propor Liga Tripartite Secreta em Berlim", "Sondar o Kaiser alemão para formar um contrapeso continental."),
            .spanish: ("Proponer Liga Tripartita Secreta en Berlín", "Sondear al Káiser alemán para formar un contrapeso continental.")
        ],
        "fashoda-channel-arbitrate": [
            .portuguese: ("Aceitar Arbitragem Marítima Americana", "Conceder arbitragem diplomática para evitar um confronto naval catastrófico."),
            .spanish: ("Aceptar Arbitraje Marítimo Estadounidense", "Conceder arbitraje diplomático para evitar un choque naval catastrófico.")
        ],
        "fashoda-league-ratify": [
            .portuguese: ("Ratificar Cotas Tripartites de Construção Naval", "Coordenar programas de construção de navios capitais nos estaleiros continentais."),
            .spanish: ("Ratificar Cuotas Tripartitas de Construcción Naval", "Coordinar programas de construcción de buques capitales en los astilleros continentales.")
        ],
        "fashoda-league-treaty-ports": [
            .portuguese: ("Direcionar Pressão da Liga aos Portos de Tratado Asiáticos", "Reivindicar concessões conjuntas ao longo da bacia do rio Yangtzé."),
            .spanish: ("Dirigir la Presión de la Liga hacia los Puertos de Tratado Asiáticos", "Reclamar concesiones conjuntas a lo largo de la cuenca del río Yangtsé.")
        ],
        "dreadnought-build": [
            .portuguese: ("Autorizar Programa Emergencial de Cruzadores de Batalha", "Bater quilha de seis dreadnoughts a turbina para manter a supremacia marítima."),
            .spanish: ("Autorizar Programa de Emergencia de Cruceros de Batalla", "Poner en grada seis dreadnoughts de turbina para mantener la supremacía marítima.")
        ],
        "dreadnought-hague": [
            .portuguese: ("Patrocinar Convenção de Limitação Naval em Haia", "Propor tetos internacionais de tonelagem de frota para evitar a ruína fiscal."),
            .spanish: ("Patrocinar Convención de Limitación Naval en La Haya", "Proponer topes internacionales de tonelaje naval para evitar la ruina fiscal.")
        ],
        "microgrid-charter": [
            .portuguese: ("Homologar Comuns Regionais de Energia Cooperativa", "Reconhecer microrredes descentralizadas e emitir créditos energéticos biorregionais."),
            .spanish: ("Homologar Bienes Comunes Regionales de Energía Cooperativa", "Reconocer microrredes descentralizadas y emitir créditos energéticos biorregionales.")
        ],
        "microgrid-enforce": [
            .portuguese: ("Reafirmar Primazia da Rede Central com a Guarda Nacional", "Impor interconexão de alta tensão e servidões federais de transmissão."),
            .spanish: ("Reafirmar la Primacía de la Red Central con la Guardia Nacional", "Imponer la interconexión de alta tensión y derechos federales de transmisión.")
        ],
        "fertilizer-subsidies": [
            .portuguese: ("Emitir Subsídios Universais ao Pão pelo Tesouro", "Tabelar preços de grãos ao consumidor e absorver déficits de padarias com reservas estatais."),
            .spanish: ("Emitir Subsidios Universales al Pan desde el Tesoro", "Limitar precios de granos al consumidor y absorber déficits de panaderías con reservas estatales.")
        ],
        "fertilizer-guard": [
            .portuguese: ("Mobilizar Gendarmaria para Proteger Silos de Grãos", "Impor toque de recolher ao redor de armazéns regionais para impedir açambarcamento."),
            .spanish: ("Desplegar Gendarmería para Asegurar Silos de Granos", "Imponer toque de queda alrededor de silos regionales para impedir el acaparamiento.")
        ],
        "grain-subsidize": [
            .portuguese: ("Financiar Subsídios Universais ao Pão pelo Tesouro", "Absorver aumentos de moagem para manter o pão básico acessível."),
            .spanish: ("Financiar Subsidios Universales al Pan desde el Tesoro", "Absorber los costos de molienda para mantener asequible el pan básico.")
        ],
        "grain-tariffs": [
            .portuguese: ("Suspender Tarifas de Importação sobre Trigo Estrangeiro", "Reduzir barreiras alfandegárias para atrair cargas agrícolas aos portos."),
            .spanish: ("Suspender Aranceles de Importación sobre Grano Extranjero", "Reducir barreras aduaneras para atraer cargamentos agrícolas a los puertos.")
        ],
        "grain-gendarmerie": [
            .portuguese: ("Mobilizar Gendarmaria para Vigiar Celeiros", "Aplicar decretos contra estocagem especulativa por sindicatos cerealistas."),
            .spanish: ("Desplegar Gendarmería para Custodiar Graneros", "Aplicar decretos contra el acaparamiento especulativo de sindicatos cerealistas.")
        ],
        "strike-reforms": [
            .portuguese: ("Promulgar Proteções Trabalhistas e Salário Mínimo", "Conceder reformas industriais e apoio habitacional para restaurar a ordem social."),
            .spanish: ("Promulgar Protecciones Laborales y Salario Mínimo", "Conceder reformas industriales y apoyo habitacional para restaurar el orden social.")
        ],
        "strike-martial-law": [
            .portuguese: ("Declarar Lei Marcial para Dispersar Piquetes", "Enviar unidades militares para desobstruir artérias de transporte."),
            .spanish: ("Declarar la Ley Marcial para Dispersar Piquetes", "Enviar unidades militares para despejar las arterias de transporte.")
        ],
        "strike-council": [
            .portuguese: ("Convidar Delegações Sindicais ao Diálogo Nacional", "Formar um conselho bipartite de emergência para negociar condições."),
            .spanish: ("Invitar a Delegaciones Sindicales al Diálogo Nacional", "Formar un consejo bipartito de emergencia para negociar condiciones.")
        ],
        "debt-moratorium": [
            .portuguese: ("Declarar Moratória da Dívida Soberana", "Repudiar dívidas externas especulativas para reter capital doméstico."),
            .spanish: ("Declarar Moratoria de la Deuda Soberana", "Repudiar deudas externas especulativas para retener capital doméstico.")
        ],
        "debt-austerity": [
            .portuguese: ("Promulgar Cortes Emergenciais nos Gastos Públicos", "Cortar salários públicos e pensões para equilibrar o orçamento."),
            .spanish: ("Promulgar Recortes de Emergencia en el Gasto Público", "Recortar salarios públicos y pensiones para equilibrar las cuentas.")
        ],
        "debt-bailout": [
            .portuguese: ("Garantir Crédito Internacional de Estabilização", "Aceitar linhas de empréstimo externo com cláusulas de ajuste fiscal."),
            .spanish: ("Asegurar Crédito Internacional de Estabilización", "Aceptar líneas de préstamo externo con cláusulas de reforma fiscal.")
        ],
        "rebellion-transition": [
            .portuguese: ("Acatar Junta de Transição Civil-Militar", "Ceder supervisão executiva a um conselho de transição para evitar conflito civil."),
            .spanish: ("Aceptar Junta de Transición Cívico-Militar", "Ceder supervisión ejecutiva a un consejo de transición para evitar el conflicto civil.")
        ],
        "rebellion-garrison": [
            .portuguese: ("Mobilizar Guarda Palaciana Leal para Defender o Executivo", "Ordenar que forças leais sustentem a sede do governo contra brigadas rebeldes."),
            .spanish: ("Movilizar a la Guardia Palaciega Leal para Defender al Ejecutivo", "Ordenar a las fuerzas leales defender la sede de gobierno frente a brigadas rebeldes.")
        ],
        "soviet-coup-emergency": [
            .portuguese: ("Declarar Estado de Emergência em Toda a União", "Mobilizar forças de segurança interna e instituir tribunais militares."),
            .spanish: ("Declarar el Estado de Emergencia en Toda la Unión", "Movilizar fuerzas de seguridad interna e instituir tribunales militares.")
        ],
        "soviet-coup-compromise": [
            .portuguese: ("Transmitir Manifesto Conciliatório da Federação", "Prometer subsídios econômicos imediatos e concessões de descentralização."),
            .spanish: ("Transmitir Manifiesto Conciliador de la Federación", "Prometer subsidios económicos inmediatos y concesiones de descentralización.")
        ],
        "soviet-coup-technocrat": [
            .portuguese: ("Formar Coalizão com Tecnocratas Reformistas", "Convidar economistas da Gosplan para liderar a reorganização administrativa."),
            .spanish: ("Formar Coalición con Tecnócratas Reformistas", "Invitar a economistas del Gosplán a liderar la reorganización administrativa.")
        ],
        "fashoda-refuse": [
            .portuguese: ("Recusar Evacuação e Reforçar Guarnição do Nilo", "Manter a fortaleza fluvial estratégica e desafiar a frota adversária."),
            .spanish: ("Rechazar la Evacuación y Reforzar la Guarnición del Nilo", "Mantener la fortaleza fluvial estratégica y desafiar a la flota adversaria.")
        ],
        "fashoda-mediate": [
            .portuguese: ("Aceitar Mediação Diplomática Americana", "Conceder demarcação fluvial em troca de garantias de segurança nas fronteiras."),
            .spanish: ("Aceptar Mediación Diplomática Estadounidense", "Conceder demarcación fluvial a cambio de garantías de seguridad fronteriza.")
        ],
        "fashoda-berlin": [
            .portuguese: ("Buscar Alinhamento Naval Secreto em Berlim", "Enviar emissários diplomáticos para negociar um pacto de assistência mútua."),
            .spanish: ("Buscar Alineamiento Naval Secreto en Berlín", "Enviar emisarios diplomáticos para negociar un pacto de asistencia mutua.")
        ],
        "aquifer-sluices": [
            .portuguese: ("Tomar Comportas Transfronteiriças por Força Militar", "Mobilizar guarnições mecanizadas para garantir o fluxo soberano de irrigação."),
            .spanish: ("Tomar Compuertas Transfronterizas por Fuerza Militar", "Desplegar guarniciones mecanizadas para asegurar el flujo soberano de riego.")
        ],
        "aquifer-desal": [
            .portuguese: ("Emitir Títulos de Emergência para Dessalinização Solar", "Iniciar construção acelerada de adutoras costeiras de osmose reversa."),
            .spanish: ("Emitir Bonos de Emergencia para Desalinización Solar", "Iniciar construcción acelerada de acueductos costeros de ósmosis inversa.")
        ],
        "aquifer-rationing": [
            .portuguese: ("Impor Racionamento Estrito de Água Urbana", "Cortar alocações hídricas municipais em 40% para preservar as colheitas de grãos."),
            .spanish: ("Imponer Racionamiento Estricto de Agua Urbana", "Recortar las asignaciones municipales de agua un 40% para sostener las cosechas.")
        ],
        "cyber-killswitch": [
            .portuguese: ("Ativar Chaves Criptográficas Soberanas de Isolamento", "Isolar redes financeiras nacionais do contágio automatizado internacional."),
            .spanish: ("Activar Interruptores Criptográficos Soberanos", "Aislar las redes financieras nacionales del contagio automatizado internacional.")
        ],
        "cyber-nationalize": [
            .portuguese: ("Nacionalizar Nós Quânticos de Telecom sob Comando Cibernético", "Colocar a infraestrutura estratégica de rede sob coordenação marcial."),
            .spanish: ("Nacionalizar Nodos Cuánticos de Telecom bajo Mando Cibernético", "Poner la infraestructura estratégica de red bajo coordinación marcial.")
        ],
        "cyber-liquidity": [
            .portuguese: ("Injetar Liquidez de Emergência nas Câmaras Algorítmicas", "Garantir câmaras de compensação de ativos digitais com reservas soberanas."),
            .spanish: ("Inyectar Liquidez de Emergencia en las Cámaras Algorítmicas", "Garantizar las cámaras de compensación de activos digitales con reservas soberanas.")
        ]
    ]
}
