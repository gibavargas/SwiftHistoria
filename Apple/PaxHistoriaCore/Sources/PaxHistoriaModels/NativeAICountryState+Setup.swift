import Foundation

public extension NativeAICountryState {
    static func initialAICountryStates(for scenarioID: String, strategicCountryCodes: [String]) -> [String: NativeAICountryState] {
        var states: [String: NativeAICountryState] = [:]

        let strategicCodes = strategicCountryCodes.filter { $0 != "GLOBAL" }

        for code in strategicCodes {
            var doctrine = NativeAIDoctrine.isolationist
            var budgetPriority = NativeAIBudgetPriority.stability
            var multiTurnAgenda = "Focus on domestic administrative and service consolidation."
            var relationships: [String: Int] = [:]

            // Default baseline relationships (most are neutral)
            for otherCode in strategicCodes where otherCode != code {
                relationships[otherCode] = 0
            }

            if scenarioID == "default" || scenarioID == "" {
                // Historically-informed starting states for the 2010 Modern Day scenario
                switch code {
                case "USA":
                    doctrine = .collaborative
                    budgetPriority = .diplomacy
                    multiTurnAgenda = "Strengthen regional alliances and coordinate global trade corridors."
                    relationships["GBR"] = 70
                    relationships["DEU"] = 60
                    relationships["FRA"] = 60
                    relationships["JPN"] = 65
                    relationships["AUS"] = 60
                    relationships["BRA"] = 20
                    relationships["CHN"] = -25
                    relationships["RUS"] = -30
                case "CHN":
                    doctrine = .mercantile
                    budgetPriority = .growth
                    multiTurnAgenda = "Expand export corridors and secure industrial resources."
                    relationships["RUS"] = 40
                    relationships["USA"] = -25
                    relationships["JPN"] = -30
                case "RUS":
                    doctrine = .defensive
                    budgetPriority = .military
                    multiTurnAgenda = "Reinforce security boundaries and modernize logistics capabilities."
                    relationships["CHN"] = 40
                    relationships["USA"] = -30
                    relationships["GBR"] = -25
                    relationships["DEU"] = -15
                    relationships["FRA"] = -15
                case "DEU":
                    doctrine = .mercantile
                    budgetPriority = .growth
                    multiTurnAgenda = "Optimize industrial export grids and maintain fiscal stability."
                    relationships["USA"] = 60
                    relationships["FRA"] = 70
                    relationships["GBR"] = 50
                    relationships["RUS"] = -15
                case "FRA":
                    doctrine = .collaborative
                    budgetPriority = .diplomacy
                    multiTurnAgenda = "Lead European integration and support multilateral agreements."
                    relationships["USA"] = 60
                    relationships["DEU"] = 70
                    relationships["GBR"] = 55
                    relationships["RUS"] = -15
                case "GBR":
                    doctrine = .defensive
                    budgetPriority = .stability
                    multiTurnAgenda = "Recover trade corridors and manage post-recession administrative costs."
                    relationships["USA"] = 70
                    relationships["DEU"] = 50
                    relationships["FRA"] = 55
                    relationships["RUS"] = -25
                case "JPN":
                    doctrine = .defensive
                    budgetPriority = .stability
                    multiTurnAgenda = "Mitigate industrial deflation and reinforce Pacific maritime corridors."
                    relationships["USA"] = 65
                    relationships["CHN"] = -30
                    relationships["KOR"] = -10
                case "BRA":
                    doctrine = .collaborative
                    budgetPriority = .growth
                    multiTurnAgenda = "Develop commodity trade routes and South American infrastructure corridors."
                    relationships["USA"] = 20
                case "AUS":
                    doctrine = .collaborative
                    budgetPriority = .diplomacy
                    multiTurnAgenda = "Secure Asia-Pacific trade agreements and resource partnerships."
                    relationships["USA"] = 60
                    relationships["CHN"] = -15
                default:
                    break
                }
            } else if scenarioID == "soviet-triumph" {
                // Alternate History: Bipolar Cold War containment
                switch code {
                case "USA":
                    doctrine = .defensive
                    budgetPriority = .military
                    multiTurnAgenda = "Contain collectivized command networks and secure trade routes."
                    relationships["RUS"] = -80
                    relationships["CHN"] = -40
                case "RUS": // Stand-in for USSR
                    doctrine = .expansionist
                    budgetPriority = .military
                    multiTurnAgenda = "Integrate command industrial grids and support socialist alignment."
                    relationships["USA"] = -80
                    relationships["CHN"] = 50
                case "CHN":
                    doctrine = .expansionist
                    budgetPriority = .growth
                    multiTurnAgenda = "Expand command economy and strengthen alliance networks."
                    relationships["RUS"] = 50
                    relationships["USA"] = -40
                default:
                    break
                }
            } else if scenarioID == "fragmented-markets" {
                // Blocs, trade friction
                switch code {
                case "USA":
                    doctrine = .defensive
                    budgetPriority = .diplomacy
                    multiTurnAgenda = "Defend core sovereign trade networks from regional fragmentation."
                    relationships["CHN"] = -50
                case "CHN":
                    doctrine = .mercantile
                    budgetPriority = .growth
                    multiTurnAgenda = "Leverage trade access and secure local resource corridors."
                    relationships["USA"] = -50
                default:
                    relationships["USA"] = -10
                    relationships["CHN"] = -10
                }
            }

            states[code] = NativeAICountryState(
                countryCode: code,
                doctrine: doctrine,
                budgetPriority: budgetPriority,
                relationshipScores: relationships,
                multiTurnAgenda: multiTurnAgenda,
                agendaProgress: 0
            )
        }

        return states
    }
}
