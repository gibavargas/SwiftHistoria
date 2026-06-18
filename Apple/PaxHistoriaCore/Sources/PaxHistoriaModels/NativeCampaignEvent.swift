import Foundation

public struct NativeCampaignEvent: Codable, Hashable, Identifiable, Sendable {
    public var date: String
    public var description: String
    public var id: String
    public var importance: NativeEventImportance
    public var kind: NativeEventKind
    public var linkedActionIDs: [String]
    public var notable: Bool
    public var playerRelated: Bool
    public var strategicEffects: [NativeStrategicEffect]
    public var title: String
    public var hexLeverCode: String?
    public var sovereigntyChange: NativeSovereigntyChange?

    public init(
        date: String,
        description: String,
        id: String,
        importance: NativeEventImportance,
        kind: NativeEventKind,
        linkedActionIDs: [String],
        notable: Bool,
        playerRelated: Bool,
        strategicEffects: [NativeStrategicEffect],
        title: String,
        hexLeverCode: String? = nil,
        sovereigntyChange: NativeSovereigntyChange? = nil
    ) {
        self.date = date
        self.description = description
        self.id = id
        self.importance = importance
        self.kind = kind
        self.linkedActionIDs = linkedActionIDs
        self.notable = notable
        self.playerRelated = playerRelated
        self.strategicEffects = strategicEffects
        self.title = title
        self.hexLeverCode = hexLeverCode
        self.sovereigntyChange = sovereigntyChange
    }
}

public struct NativeStrategicEffect: Codable, Hashable, Identifiable, Sendable {
    public var date: String
    public var eventId: String
    public var id: String
    public var magnitude: Int
    public var summary: String
    public var target: String
    public var track: NativeStrategicTrack

    public init(
        date: String,
        eventId: String,
        id: String,
        magnitude: Int,
        summary: String,
        target: String,
        track: NativeStrategicTrack
    ) {
        self.date = date
        self.eventId = eventId
        self.id = id
        self.magnitude = magnitude
        self.summary = summary
        self.target = target
        self.track = track
    }
}
