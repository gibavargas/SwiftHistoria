import Foundation

public struct NativeScenario: Codable, Hashable, Identifiable, Sendable {
    public var accentColor: String
    public var baseStability: Int
    public var baseWorldTension: Int
    public var gameDate: String
    public var heroSubtitle: String
    public var heroTitle: String
    public var id: String
    public var name: String
    public var openingSummary: String
    public var startDate: String
    public var subtitle: String

    public init(
        accentColor: String,
        baseStability: Int,
        baseWorldTension: Int,
        gameDate: String,
        heroSubtitle: String,
        heroTitle: String,
        id: String,
        name: String,
        openingSummary: String,
        startDate: String,
        subtitle: String
    ) {
        self.accentColor = accentColor
        self.baseStability = baseStability
        self.baseWorldTension = baseWorldTension
        self.gameDate = gameDate
        self.heroSubtitle = heroSubtitle
        self.heroTitle = heroTitle
        self.id = id
        self.name = name
        self.openingSummary = openingSummary
        self.startDate = startDate
        self.subtitle = subtitle
    }
}

public enum NativeScenarioCatalog {
    public static let defaultScenario = NativeScenario(
        accentColor: "#c49a35",
        baseStability: 62,
        baseWorldTension: 48,
        gameDate: "2010-01-15",
        heroSubtitle: "Post-recession recovery, rapid technological growth, and regional alignment of the early 2010s.",
        heroTitle: "Modern Day",
        id: "default",
        name: "Modern Day",
        openingSummary: "The campaign begins in 2010. Real-world challenges include post-crisis economic recovery, rising tech connectivity, and shifting geopolitical power balances.",
        startDate: "2010-01-01",
        subtitle: "Real-world facts starting 2010"
    )

    public static let fragmentedMarkets = NativeScenario(
        accentColor: "#4f9f8f",
        baseStability: 54,
        baseWorldTension: 66,
        gameDate: "2032-04-01",
        heroSubtitle: "Regional blocs, volatile trade corridors, and hard budget choices define the opening.",
        heroTitle: "Fragmented Markets",
        id: "fragmented-markets",
        name: "Fragmented Markets",
        openingSummary: "A fractured market order forces the player to convert scarce administrative capacity into trust, access, and leverage.",
        startDate: "2031-01-01",
        subtitle: "Trade friction and coalition management"
    )

    public static let resilienceDecade = NativeScenario(
        accentColor: "#5d8fd8",
        baseStability: 70,
        baseWorldTension: 38,
        gameDate: "2040-01-10",
        heroSubtitle: "Adaptation finance, energy reliability, and public-service legitimacy shape a slower strategic game.",
        heroTitle: "Resilience Decade",
        id: "resilience-decade",
        name: "Resilience Decade",
        openingSummary: "The resilience decade rewards patient institution-building, credible delivery, and alliances that can survive stress.",
        startDate: "2038-06-01",
        subtitle: "Long-horizon civic strategy"
    )

    public static let sovietTriumph = NativeScenario(
        accentColor: "#df2a2a",
        baseStability: 58,
        baseWorldTension: 75,
        gameDate: "1991-11-07",
        heroSubtitle: "Alternate History Cold War: The Soviet Union achieved hegemony. Collectivized command networks and military pacts dominate.",
        heroTitle: "Soviet Triumph",
        id: "soviet-triumph",
        name: "Soviet Triumph",
        openingSummary: "The Soviet Union stands victorious. Direct collectivized industrial grids or manage containment strategies in a tense bipolar world.",
        startDate: "1991-11-01",
        subtitle: "Bipolar containment and planned hegemony"
    )

    public static let paxCybernetica = NativeScenario(
        accentColor: "#a855f7",
        baseStability: 64,
        baseWorldTension: 50,
        gameDate: "2055-08-18",
        heroSubtitle: "Decentralized algorithmic protocols and corporate sovereign networks compete for digital supremacy.",
        heroTitle: "Pax Cybernetica",
        id: "pax-cybernetica",
        name: "Pax Cybernetica",
        openingSummary: "Algorithmic DAOs and automated supply webs govern global trade. Administrative capacity represents server scale.",
        startDate: "2055-01-01",
        subtitle: "Corporate sovereign networks"
    )

    public static let solarpunkDawn = NativeScenario(
        accentColor: "#10b981",
        baseStability: 68,
        baseWorldTension: 35,
        gameDate: "2060-03-21",
        heroSubtitle: "Ecological restoration and cooperative bioregions strive for global climatic balance.",
        heroTitle: "Solarpunk Dawn",
        id: "solarpunk-dawn",
        name: "Solarpunk Dawn",
        openingSummary: "Cooperative bioregions focus on climate restoration, local micro-grids, and shared tech resources under resource ceilings.",
        startDate: "2060-01-01",
        subtitle: "Climatic balance and cooperative networks"
    )

    public static let dividedSovereignty = NativeScenario(
        accentColor: "#d97706",
        baseStability: 60,
        baseWorldTension: 42,
        gameDate: "1895-06-20",
        heroSubtitle: "Multi-polar imperial balancing, mercantilist spheres, and classic balance-of-power diplomacy.",
        heroTitle: "Divided Sovereignty",
        id: "divided-sovereignty",
        name: "Divided Sovereignty",
        openingSummary: "Direct your empire through balance-of-power alignments, coal concessions, and mercantilist treaty ports.",
        startDate: "1895-01-01",
        subtitle: "Imperial balance and treaty ports"
    )

    public static let resourceCrucible = NativeScenario(
        accentColor: "#ea580c",
        baseStability: 48,
        baseWorldTension: 80,
        gameDate: "2035-10-31",
        heroSubtitle: "Critical resource bottlenecks, water security friction, and heavily militarized corridors.",
        heroTitle: "Resource Crucible",
        id: "resource-crucible",
        name: "Resource Crucible",
        openingSummary: "Critical mineral bottlenecks and massive climate migrations challenge state survival as aquifers dry up.",
        startDate: "2035-06-01",
        subtitle: "Resource security and migration corridors"
    )

    public static let all: [NativeScenario] = [
        defaultScenario,
        fragmentedMarkets,
        resilienceDecade,
        sovietTriumph,
        paxCybernetica,
        solarpunkDawn,
        dividedSovereignty,
        resourceCrucible
    ]

    public static func scenario(for id: String?) -> NativeScenario {
        let normalized = sanitizeFoundationModelText(id ?? "")
        return all.first { $0.id == normalized } ?? defaultScenario
    }
}
