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

    static let tables: [LWProseKey: [NativeGameLanguage: String]] = [
        .peaceTitle: [
            .english: "Peace: {goal}",
            .portuguese: "Paz: {goal}",
            .spanish: "Paz: {goal}",
        ],
        .peaceSummary: [
            .english: "{winner} dictates terms; {loser} concedes.",
            .portuguese: "{winner} dita as condições; {loser} cede.",
            .spanish: "{winner} dicta las condiciones; {loser} cede.",
        ],
        .warGoalConcessions: [
            .english: "Concessions from {country}",
            .portuguese: "Concessões de {country}",
            .spanish: "Concesiones de {country}",
        ],
        .warDeclarationTitle: [
            .english: "{country} declares war on {target}",
            .portuguese: "{country} declara guerra a {target}",
            .spanish: "{country} declara la guerra a {target}",
        ],
        .warDeclarationSummary: [
            .english: "Armies mobilize along the border; embassies are withdrawn.",
            .portuguese: "Exércitos mobilizam-se na fronteira; embaixadas são retiradas.",
            .spanish: "Los ejércitos se movilizan en la frontera; las embajadas se retiran.",
        ],
        .allianceTitle: [
            .english: "Alliance signed",
            .portuguese: "Aliança assinada",
            .spanish: "Alianza firmada",
        ],
        .allianceSummary: [
            .english: "{country} and {target} enter a defensive alliance.",
            .portuguese: "{country} e {target} firmam uma aliança defensiva.",
            .spanish: "{country} y {target} forman una alianza defensiva.",
        ],
        .dispatchTitle: [
            .english: "Dispatch from {country}",
            .portuguese: "Despacho de {country}",
            .spanish: "Despacho de {country}",
        ],
        .flavorHarvest: [
            .english: "A bumper harvest steadies grain prices in {country}.",
            .portuguese: "Uma colheita farta estabiliza os preços do trigo em {country}.",
            .spanish: "Una cosecha abundante estabiliza los precios del grano en {country}.",
        ],
        .flavorStrikers: [
            .english: "Strikers blockade the docks of {country}.",
            .portuguese: "Grevistas bloqueiam os portos de {country}.",
            .spanish: "Los huelguistas bloquean los puertos de {country}.",
        ],
        .flavorTariff: [
            .english: "{country}'s parliament debates tariff reform.",
            .portuguese: "O parlamento de {country} debate a reforma tarifária.",
            .spanish: "El parlamento de {country} debate la reforma arancelaria.",
        ],
        .flavorBanking: [
            .english: "A banking scandal rattles confidence in {country}.",
            .portuguese: "Um escândalo bancário abala a confiança em {country}.",
            .spanish: "Un escándalo bancario sacude la confianza en {country}.",
        ],
        .flavorRailway: [
            .english: "Railway expansion reaches the interior of {country}.",
            .portuguese: "A expansão ferroviária alcança o interior de {country}.",
            .spanish: "La expansión ferroviária llega al interior de {country}.",
        ],
        .crisisTitle: [
            .english: "Crisis in {country}",
            .portuguese: "Crise em {country}",
            .spanish: "Crisis en {country}",
        ],
        .crisisSummary: [
            .english: "Riots erupt over the price of bread; the government scrambles to respond.",
            .portuguese: "Manifestações explodem pelo preço do pão; o governo corre para responder.",
            .spanish: "Estallan disturbios por el precio del pan; el gobierno se apresura a responder.",
        ],
        .worldHoldsBreath: [
            .english: "The world holds its breath.",
            .portuguese: "O mundo prende a respiração.",
            .spanish: "El mundo contiene la respiración.",
        ],
        .situationWarSingular: [
            .english: "{wars} war rages among {powers} great powers — {date}.",
            .portuguese: "{wars} guerra assola {powers} grandes potências — {date}.",
            .spanish: "{wars} guerra azota {powers} grandes potencias — {date}.",
        ],
        .situationWarPlural: [
            .english: "{wars} wars rage among {powers} great powers — {date}.",
            .portuguese: "{wars} guerras assolam {powers} grandes potências — {date}.",
            .spanish: "{wars} guerras azotan {powers} grandes potencias — {date}.",
        ],
        .situationPeace: [
            .english: "An uneasy peace holds among {powers} great powers — {date}.",
            .portuguese: "Uma paz instável persiste entre {powers} grandes potências — {date}.",
            .spanish: "Una paz inquieta se mantiene entre {powers} grandes potencias — {date}.",
        ],
        // MARK: Commentary fragments — every fragment names its country so the
        // assembled line always satisfies the "names its country" contract.
        .sitAtWar: [
            .english: "{country}'s armies hold active fronts.",
            .portuguese: "Os exércitos da {country} mantêm frentes ativas.",
            .spanish: "Los ejércitos de {country} sostienen frentes activos.",
        ],
        .sitDeficit: [
            .english: "{country} runs a deficit and the treasury urges moderation.",
            .portuguese: "A {country} registra déficit e o tesouro pede moderação.",
            .spanish: "{country} registra déficit y el tesouro pide moderación.",
        ],
        .sitMobilized: [
            .english: "{country} keeps its reserves mobilized while markets stay open.",
            .portuguese: "A {country} mantém suas reservas mobilizadas enquanto os mercados seguem abertos.",
            .spanish: "{country} mantiene sus reservas movilizadas mientras los mercados siguen abiertos.",
        ],
        .sitSteady: [
            .english: "{country} enjoys steady finances and quiet borders.",
            .portuguese: "A {country} desfruta de finanças estáveis e fronteiras tranquilas.",
            .spanish: "{country} disfruta de finanzas estables y fronteras tranquilas.",
        ],
        .causeInfamy: [
            .english: "Foreign chancelleries denounce {country}'s appetite for conquest.",
            .portuguese: "Chancelarias estrangeiras denunciam o apetite de conquista da {country}.",
            .spanish: "Las cancillerías extranjeras denuncian el apetito conquistador de {country}.",
        ],
        .causeRadicals: [
            .english: "Restive crowds keep {country}'s police busy.",
            .portuguese: "Multitudes inquietas mantêm a polícia da {country} ocupada.",
            .spanish: "Multitudes inquietas mantienen ocupada a la policía de {country}.",
        ],
        .causeThreat: [
            .english: "{country}'s staff officers watch the borders with concern.",
            .portuguese: "Os oficiais da {country} observam as fronteiras com preocupação.",
            .spanish: "Los oficiales de {country} observan las fronteras con preocupación.",
        ],
        .causePeace: [
            .english: "{country}'s chancellery drafts memoranda and waits.",
            .portuguese: "A chancelaria da {country} redige memorandos e aguarda.",
            .spanish: "La cancillería de {country} redacta memorandos y espera.",
        ],
        .outlookCaution: [
            .english: "The government counsels patience.",
            .portuguese: "O governo aconselha paciência.",
            .spanish: "El gobierno aconseja paciencia.",
        ],
        .outlookAmbition: [
            .english: "Ambition hums in every ministry.",
            .portuguese: "A ambição vibra em todos os ministérios.",
            .spanish: "La ambición vibra en todos los ministerios.",
        ],
        .outlookTrade: [
            .english: "The merchant classes champion quiet trade.",
            .portuguese: "As classes mercantis defendem o comércio tranquilo.",
            .spanish: "Las clases mercantiles defienden el comercio tranquilo.",
        ],
        .outlookOpportunity: [
            .english: "Every distant quarrel reads like an opening.",
            .portuguese: "Cada querela distante parece uma oportunidade.",
            .spanish: "Cada querella lejana parece una oportunidad.",
        ],
        .uiSituationWar: [
            .english: "{date} — {wars} war(s) rage across the world",
            .portuguese: "{date} — {wars} guerra(s) assolam o mundo",
            .spanish: "{date} — {wars} guerra(s) azotan el mundo",
        ],
        .uiSituationPeace: [
            .english: "{date} — an uneasy peace holds",
            .portuguese: "{date} — uma paz instável persiste",
            .spanish: "{date} — una paz inquieta se mantiene",
        ],
    ]
}
