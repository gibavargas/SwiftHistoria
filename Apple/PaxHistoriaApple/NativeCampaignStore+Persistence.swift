import Foundation
import OSLog
import SwiftUI

private final class NativePersistenceSnapshot: @unchecked Sendable {
    let state: NativeCampaignState
    let slot: Int
    let defaults: UserDefaults
    let persistenceDirectory: URL

    init(state: NativeCampaignState, slot: Int, defaults: UserDefaults, persistenceDirectory: URL) {
        self.state = state
        self.slot = slot
        self.defaults = defaults
        self.persistenceDirectory = persistenceDirectory
    }
}

private actor NativePersistenceWriter {
    static let shared = NativePersistenceWriter()

    func write(_ snapshot: NativePersistenceSnapshot) {
        NativeCampaignStore.writeStateToDisk(
            snapshot.state,
            slot: snapshot.slot,
            defaults: snapshot.defaults,
            persistenceDirectory: snapshot.persistenceDirectory
        )
    }
}

/// File I/O, persistence, and campaign-state loading.
extension NativeCampaignStore {
    static func removePersistedCampaignState(defaults: UserDefaults, persistenceDirectory: URL) {
        // Remove all slots' data
        for slot in 1 ... 3 {
            let suffix = slot == 1 ? "" : ".slot\(slot)"
            defaults.removeObject(forKey: selectedCountryKey + suffix)
            defaults.removeObject(forKey: selectedLanguageKey + suffix)
            defaults.removeObject(forKey: selectedScenarioKey + suffix)
            defaults.removeObject(forKey: campaignStateKey + suffix)
            defaults.removeObject(forKey: campaignStateEnvelopeKey + suffix)
            defaults.removeObject(forKey: campaignStateBackupKey + suffix)
        }
        for fileName in [campaignStateEnvelopeFileName, campaignStateBackupFileName, campaignStateLegacyFileName] {
            try? FileManager.default.removeItem(at: persistenceDirectory.appendingPathComponent(fileName))
            // Also remove slot-suffixed files
            for slot in 2 ... 3 {
                let slotFile = fileName.replacingOccurrences(of: ".json", with: "-slot\(slot).json")
                try? FileManager.default.removeItem(at: persistenceDirectory.appendingPathComponent(slotFile))
            }
        }
        defaults.removeObject(forKey: activeSlotKey)
    }

    func persistState() {
        guard let state else {
            defaults.removeObject(forKey: slotKey(Self.campaignStateKey))
            defaults.removeObject(forKey: slotKey(Self.campaignStateEnvelopeKey))
            defaults.removeObject(forKey: slotKey(Self.campaignStateBackupKey))
            removePersistedCampaignFiles()
            return
        }

        // Cancel any pending debounced write — only the latest state matters.
        persistDebounceTask?.cancel()
        persistenceRevision &+= 1
        let revision = persistenceRevision
        let activeSlot = saveSlot
        let defaults = self.defaults
        let persistenceDirectory = self.persistenceDirectory
        let snapshot = state
        let persistence = NativePersistenceSnapshot(
            state: snapshot,
            slot: activeSlot,
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        persistDebounceTask = Task { @MainActor [weak self] in
            // 500 ms debounce: coalesces rapid mutations (e.g. delete 3 actions)
            // into a single JSON encode + disk write.
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, self?.persistenceRevision == revision else { return }
            await NativePersistenceWriter.shared.write(persistence)
        }
    }

    /// Immediate persistence for critical mutations (turn advance, new game).
    /// The snapshot is queued without making the main actor wait for JSON
    /// encoding, backup decoding, or atomic file writes.
    func persistStateImmediately() {
        guard let state else {
            persistState()
            return
        }
        persistDebounceTask?.cancel()
        persistenceRevision &+= 1
        let activeSlot = saveSlot
        let defaults = self.defaults
        let persistenceDirectory = self.persistenceDirectory
        let snapshot = state
        let persistence = NativePersistenceSnapshot(
            state: snapshot,
            slot: activeSlot,
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        let previousImmediate = persistImmediateTask
        persistImmediateTask = Task { @MainActor in
            await previousImmediate?.value
            await NativePersistenceWriter.shared.write(persistence)
        }
    }

    /// Synchronous flush for app-lifecycle hooks (scene phase changes,
    /// NSApplication.willTerminateNotification). The willTerminate
    /// notification is synchronous and the process may exit before any
    /// awaited task resumes, so this cancels the debounce task and writes
    /// the latest state inline. Guarantees Cmd+Q / background / crash
    /// cannot lose the sub-second mutation window.
    func flushPendingPersistence() {
        persistDebounceTask?.cancel()
        persistDebounceTask = nil
        guard let state else { return }
        persistenceRevision &+= 1
        Self.writeStateToDisk(
            state,
            slot: saveSlot,
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
    }

    /// Waits for the latest queued write. The app normally does not need to
    /// await persistence, but this is useful for lifecycle handoff and
    /// deterministic integration tests.
    func waitForPersistence() async {
        let pendingDebounce = persistDebounceTask
        let pendingImmediate = persistImmediateTask
        await pendingDebounce?.value
        await pendingImmediate?.value
    }

    fileprivate nonisolated static func writeStateToDisk(
        _ state: NativeCampaignState,
        slot activeSlot: Int,
        defaults: UserDefaults,
        persistenceDirectory: URL
    ) {
        // Persistence is deliberately redundant: primary versioned envelope,
        // last-good envelope backup, and a direct legacy state blob. The read
        // path tries them in that order so corrupt primary data can be recovered
        // without losing old-save compatibility.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeCampaignStore")
        let envelope = CampaignStateEnvelope(
            schemaVersion: 2,
            savedAt: NativeGameEngine.todayStamp(),
            state: state
        )
        let envelopeData: Data
        let legacyData: Data
        do {
            envelopeData = try encoder.encode(envelope)
            legacyData = try encoder.encode(state)
        } catch {
            logger.error("Native campaign encode failed")
            return
        }

        let backupData: Data = if let previousPrimary = Self.primaryPersistenceData(
            from: defaults,
            persistenceDirectory: persistenceDirectory,
            slotKey: { key in Self.slotKey(key, slot: activeSlot) },
            slotFileName: { name in Self.slotFileName(name, slot: activeSlot) }
        ),
            let previousEnvelope = try? decoder.decode(CampaignStateEnvelope.self, from: previousPrimary),
            previousEnvelope.schemaVersion == 2
        {
            previousPrimary
        } else {
            envelopeData
        }

        do {
            try Self.writePersistenceData(
                backupData,
                fileName: Self.slotFileName(Self.campaignStateBackupFileName, slot: activeSlot),
                directory: persistenceDirectory
            )
            try Self.writePersistenceData(
                envelopeData,
                fileName: Self.slotFileName(Self.campaignStateEnvelopeFileName, slot: activeSlot),
                directory: persistenceDirectory
            )
            try Self.writePersistenceData(
                legacyData,
                fileName: Self.slotFileName(Self.campaignStateLegacyFileName, slot: activeSlot),
                directory: persistenceDirectory
            )
            Self.storeDefaultsFallback(backupData, forKey: Self.slotKey(Self.campaignStateBackupKey, slot: activeSlot), defaults: defaults)
            Self.storeDefaultsFallback(envelopeData, forKey: Self.slotKey(Self.campaignStateEnvelopeKey, slot: activeSlot), defaults: defaults)
            Self.storeDefaultsFallback(legacyData, forKey: Self.slotKey(Self.campaignStateKey, slot: activeSlot), defaults: defaults)
            Self.writeTursoPersistenceData(
                envelopeData: envelopeData,
                backupData: backupData,
                legacyData: legacyData,
                savedAt: envelope.savedAt,
                slot: activeSlot,
                defaults: defaults
            )
            logger.info("Native campaign persisted round=\(state.round, privacy: .public) timeline=\(state.timeline.count, privacy: .public)")
        } catch {
            logger.error("Native campaign file persistence failed")
        }
    }

    static func loadSelectedCountry(
        from defaults: UserDefaults,
        decoder: JSONDecoder,
        key: String = selectedCountryKey
    ) -> PlayerCountry? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(PlayerCountry.self, from: data)
    }

    func removePersistedCampaignFiles() {
        for fileName in [
            Self.campaignStateEnvelopeFileName,
            Self.campaignStateBackupFileName,
            Self.campaignStateLegacyFileName
        ] {
            do {
                try Self.removePersistenceData(fileName: slotFileName(fileName), directory: persistenceDirectory)
            } catch {
                logger.error("Native campaign persistence cleanup failed")
            }
        }
    }

    static func loadCampaignState(
        from defaults: UserDefaults,
        decoder: JSONDecoder,
        persistenceDirectory: URL,
        slotKey: (String) -> String = { $0 },
        slotFileName: (String) -> String = { $0 }
    ) -> CampaignLoadResult {
        let envelopeKey = slotKey(campaignStateEnvelopeKey)
        let backupKey = slotKey(campaignStateBackupKey)
        let legacyKey = slotKey(campaignStateKey)

        let primarySources = persistenceSources(
            defaults: defaults,
            key: envelopeKey,
            fileName: slotFileName(campaignStateEnvelopeFileName),
            directory: persistenceDirectory,
            tursoKind: .envelope,
            slot: Self.slotNumber(from: envelopeKey)
        )
        if let primary = newestEnvelope(from: primarySources, decoder: decoder) {
            let notice: String? = switch primary.sourceLabel {
            case "file":
                nil
            case "turso":
                "Loaded the campaign save from Turso because no local copy was available."
            default:
                "Loaded the newest campaign save from user-defaults because it is newer than the file copy."
            }
            return CampaignLoadResult(state: primary.envelope.state, notice: notice)
        }

        let backupSources = persistenceSources(
            defaults: defaults,
            key: backupKey,
            fileName: slotFileName(campaignStateBackupFileName),
            directory: persistenceDirectory,
            tursoKind: .backup,
            slot: Self.slotNumber(from: backupKey)
        )
        if let backup = newestEnvelope(from: backupSources, decoder: decoder) {
            let notice = primarySources.isEmpty
                ? "Loaded the last-good campaign backup because the primary save was missing."
                : "Recovered the campaign from the last-good backup because the primary save was corrupt."
            return CampaignLoadResult(state: backup.envelope.state, notice: "\(notice) Source: \(backup.sourceLabel).")
        }

        let legacySources = persistenceSources(
            defaults: defaults,
            key: legacyKey,
            fileName: slotFileName(campaignStateLegacyFileName),
            directory: persistenceDirectory,
            tursoKind: .legacy,
            slot: Self.slotNumber(from: legacyKey)
        )
        for source in legacySources {
            if let state = try? decoder.decode(NativeCampaignState.self, from: source.data) {
                let notice = primarySources.isEmpty
                    ? "Loaded a legacy campaign save and will upgrade it on the next save."
                    : "Loaded a legacy campaign save because the versioned save could not be read."
                return CampaignLoadResult(state: state, notice: "\(notice) Source: \(source.label).")
            }
        }

        if !primarySources.isEmpty || !backupSources.isEmpty || !legacySources.isEmpty {
            return CampaignLoadResult(
                state: nil,
                notice: "Saved campaign data could not be read. A new campaign was not created until you choose a country."
            )
        }

        return CampaignLoadResult(state: nil, notice: nil)
    }

    /// Remote recovery is deliberately asynchronous. Local files and
    /// UserDefaults remain the launch path; this helper is only used after a
    /// local miss so a slow provider cannot hold the main actor.
    nonisolated static func loadRemoteCampaignState(
        configuration: NativeTursoCampaignPersistence.Configuration,
        decoder: JSONDecoder,
        slot: Int
    ) async -> CampaignLoadResult {
        async let envelopeData = NativeTursoCampaignPersistence.readAsync(kind: .envelope, slot: slot, configuration: configuration)
        async let backupData = NativeTursoCampaignPersistence.readAsync(kind: .backup, slot: slot, configuration: configuration)
        async let legacyData = NativeTursoCampaignPersistence.readAsync(kind: .legacy, slot: slot, configuration: configuration)
        let (envelope, backup, legacy) = await (envelopeData, backupData, legacyData)

        if let envelope,
           let decoded = try? decoder.decode(CampaignStateEnvelope.self, from: envelope),
           decoded.schemaVersion == 2
        {
            return CampaignLoadResult(
                state: decoded.state,
                notice: "Loaded the campaign save from Turso because no local copy was available."
            )
        }

        if let backup,
           let decoded = try? decoder.decode(CampaignStateEnvelope.self, from: backup),
           decoded.schemaVersion == 2
        {
            return CampaignLoadResult(
                state: decoded.state,
                notice: "Loaded the campaign backup from Turso because no local primary save was available."
            )
        }

        if let legacy,
           let decoded = try? decoder.decode(NativeCampaignState.self, from: legacy)
        {
            return CampaignLoadResult(
                state: decoded,
                notice: "Loaded a legacy campaign save from Turso and will upgrade it on the next save."
            )
        }

        return CampaignLoadResult(state: nil, notice: nil)
    }

    static func defaultPersistenceDirectory(fileManager: FileManager = .default) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("SwiftHistoria", isDirectory: true)
            .appendingPathComponent("NativeCampaigns", isDirectory: true)
    }

    nonisolated static func primaryPersistenceData(
        from defaults: UserDefaults,
        persistenceDirectory: URL,
        slotKey: (String) -> String = { $0 },
        slotFileName: (String) -> String = { $0 }
    ) -> Data? {
        let sources = persistenceSources(
            defaults: defaults,
            key: slotKey(campaignStateEnvelopeKey),
            fileName: slotFileName(campaignStateEnvelopeFileName),
            directory: persistenceDirectory,
            tursoKind: .envelope,
            slot: Self.slotNumber(from: slotKey(campaignStateEnvelopeKey)),
            includeTurso: false
        )
        return newestEnvelope(from: sources, decoder: JSONDecoder())?.sourceData ?? sources.first?.data
    }

    nonisolated static func storeDefaultsFallback(_ data: Data, forKey key: String, defaults: UserDefaults) {
        if data.count <= maximumUserDefaultsCampaignBlobBytes {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    nonisolated static func newestEnvelope(
        from sources: [PersistenceDataSource],
        decoder: JSONDecoder
    ) -> (envelope: CampaignStateEnvelope, sourceLabel: String, sourceData: Data)? {
        let formatter = ISO8601DateFormatter()
        var newest: (envelope: CampaignStateEnvelope, sourceLabel: String, sourceData: Data, savedDate: Date)?
        for source in sources {
            guard let envelope = try? decoder.decode(CampaignStateEnvelope.self, from: source.data),
                  envelope.schemaVersion == 2
            else {
                continue
            }
            let savedDate = formatter.date(from: envelope.savedAt) ?? .distantPast
            if newest == nil || savedDate > newest!.savedDate {
                newest = (envelope, source.label, source.data, savedDate)
            }
        }
        guard let newest else { return nil }
        return (newest.envelope, newest.sourceLabel, newest.sourceData)
    }

    nonisolated static func persistenceSources(
        defaults: UserDefaults,
        key: String,
        fileName: String,
        directory: URL,
        tursoKind: NativeTursoCampaignPersistence.Kind? = nil,
        slot: Int = 1,
        includeTurso: Bool = true
    ) -> [PersistenceDataSource] {
        var sources: [PersistenceDataSource] = []
        if let data = readPersistenceData(fileName: fileName, directory: directory) {
            sources.append(PersistenceDataSource(data: data, label: "file"))
        }
        if let data = defaults.data(forKey: key) {
            sources.append(PersistenceDataSource(data: data, label: "user-defaults"))
        }
        if includeTurso,
           sources.isEmpty,
           let tursoKind,
           let data = NativeTursoCampaignPersistence.read(kind: tursoKind, slot: slot, defaults: defaults)
        {
            sources.append(PersistenceDataSource(data: data, label: "turso"))
        }
        return sources
    }

    nonisolated static func persistenceURL(fileName: String, directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    nonisolated static func readPersistenceData(fileName: String, directory: URL) -> Data? {
        try? Data(contentsOf: persistenceURL(fileName: fileName, directory: directory))
    }

    nonisolated static func writePersistenceData(_ data: Data, fileName: String, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: persistenceURL(fileName: fileName, directory: directory), options: [.atomic])
    }

    nonisolated static func removePersistenceData(fileName: String, directory: URL) throws {
        let url = persistenceURL(fileName: fileName, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    nonisolated static func slotNumber(from key: String) -> Int {
        guard let markerRange = key.range(of: ".slot", options: .backwards) else {
            return 1
        }
        return Int(key[markerRange.upperBound...]) ?? 1
    }

    nonisolated static func writeTursoPersistenceData(
        envelopeData: Data,
        backupData: Data,
        legacyData: Data,
        savedAt: String,
        slot: Int,
        defaults: UserDefaults
    ) {
        NativeTursoCampaignPersistence.write(
            records: [
                .init(kind: .backup, data: backupData, savedAt: savedAt),
                .init(kind: .envelope, data: envelopeData, savedAt: savedAt),
                .init(kind: .legacy, data: legacyData, savedAt: savedAt)
            ],
            slot: slot,
            defaults: defaults
        )
    }
}

enum NativeTursoCampaignPersistence {
    enum Kind: String {
        case envelope
        case backup
        case legacy
    }

    struct Record {
        let kind: Kind
        let data: Data
        let savedAt: String
    }

    struct Configuration: Equatable {
        let databaseURL: URL
        let authToken: String

        var pipelineURL: URL {
            databaseURL.appendingPathComponent("v2/pipeline")
        }
    }

    static let tableName = "native_campaign_saves"
    private static let timeoutSeconds: TimeInterval = 1.5

    static func configuration(defaults: UserDefaults, environment: [String: String] = ProcessInfo.processInfo.environment) -> Configuration? {
        let rawURL = (defaults.string(forKey: NativeCampaignStore.tursoDatabaseURLKey) ?? environment[NativeCampaignStore.tursoDatabaseURLKey])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawToken = (NativeSecretStore.string(forKey: NativeCampaignStore.tursoAuthTokenKey, defaults: defaults) ?? environment[NativeCampaignStore.tursoAuthTokenKey])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawURL, !rawURL.isEmpty, let rawToken, !rawToken.isEmpty else {
            return nil
        }
        let normalizedURL = rawURL.hasPrefix("libsql://")
            ? "https://" + rawURL.dropFirst("libsql://".count)
            : rawURL
        guard let url = URL(string: String(normalizedURL)) else {
            return nil
        }
        return Configuration(databaseURL: url, authToken: rawToken)
    }

    static func write(records: [Record], slot: Int, defaults: UserDefaults) {
        guard let configuration = configuration(defaults: defaults), !records.isEmpty else {
            return
        }
        let request = pipelineRequest(configuration: configuration, requests: writeRequests(records: records, slot: slot))
        Task.detached(priority: .utility) {
            _ = try? await execute(request: request)
        }
    }

    static func read(kind: Kind, slot: Int, defaults: UserDefaults) -> Data? {
        guard let configuration = configuration(defaults: defaults) else {
            return nil
        }
        // Never turn optional remote recovery into synchronous launch I/O.
        // `loadRemoteCampaignState` is the async path used after local misses.
        guard !Thread.isMainThread else { return nil }
        let request = pipelineRequest(configuration: configuration, requests: readRequests(kind: kind, slot: slot))
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = NativeTursoReadResultBox()
        Task.detached(priority: .utility) {
            defer { semaphore.signal() }
            guard let response = try? await execute(request: request) else { return }
            resultBox.data = dataBlob(fromPipelineResponse: response)
        }
        return semaphore.wait(timeout: .now() + timeoutSeconds) == .success ? resultBox.data : nil
    }

    static func readAsync(kind: Kind, slot: Int, defaults: UserDefaults) async -> Data? {
        guard let configuration = configuration(defaults: defaults) else {
            return nil
        }
        return await readAsync(kind: kind, slot: slot, configuration: configuration)
    }

    static func readAsync(kind: Kind, slot: Int, configuration: Configuration) async -> Data? {
        let request = pipelineRequest(configuration: configuration, requests: readRequests(kind: kind, slot: slot))
        guard let response = try? await execute(request: request) else { return nil }
        return dataBlob(fromPipelineResponse: response)
    }

    static func writeRequests(records: [Record], slot: Int) -> [[String: Any]] {
        var requests: [[String: Any]] = [
            [
                "type": "execute",
                "stmt": [
                    "sql": """
                    CREATE TABLE IF NOT EXISTS \(tableName) (
                        slot INTEGER NOT NULL,
                        kind TEXT NOT NULL,
                        saved_at TEXT NOT NULL,
                        data BLOB NOT NULL,
                        PRIMARY KEY (slot, kind)
                    )
                    """
                ]
            ]
        ]
        for record in records {
            requests.append([
                "type": "execute",
                "stmt": [
                    "sql": """
                    INSERT INTO \(tableName) (slot, kind, saved_at, data)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(slot, kind) DO UPDATE SET
                        saved_at = excluded.saved_at,
                        data = excluded.data
                    """,
                    "args": [
                        ["type": "integer", "value": "\(slot)"],
                        ["type": "text", "value": record.kind.rawValue],
                        ["type": "text", "value": record.savedAt],
                        ["type": "blob", "base64": record.data.base64EncodedString()]
                    ]
                ]
            ])
        }
        requests.append(["type": "close"])
        return requests
    }

    /// Deletes every mirrored record for a slot (envelope/backup/legacy).
    /// Called on campaign reset / slot clear so a deleted campaign cannot
    /// resurrect via `recoverRemoteCampaignIfNeeded()` on the next launch.
    static func deleteSlot(slot: Int, defaults: UserDefaults) {
        guard let configuration = configuration(defaults: defaults) else {
            return
        }
        let requests: [[String: Any]] = [
            [
                "type": "execute",
                "stmt": [
                    "sql": "DELETE FROM \(tableName) WHERE slot = ?",
                    "args": [["type": "integer", "value": "\(slot)"]]
                ]
            ],
            ["type": "close"]
        ]
        let request = pipelineRequest(configuration: configuration, requests: requests)
        Task.detached(priority: .utility) {
            _ = try? await execute(request: request)
        }
    }

    static func readRequests(kind: Kind, slot: Int) -> [[String: Any]] {
        [
            [
                "type": "execute",
                "stmt": [
                    "sql": "SELECT data FROM \(tableName) WHERE slot = ? AND kind = ? ORDER BY saved_at DESC LIMIT 1",
                    "args": [
                        ["type": "integer", "value": "\(slot)"],
                        ["type": "text", "value": kind.rawValue]
                    ]
                ]
            ],
            ["type": "close"]
        ]
    }

    static func pipelineRequest(configuration: Configuration, requests: [[String: Any]]) -> URLRequest {
        var request = URLRequest(url: configuration.pipelineURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("Bearer \(configuration.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["requests": requests])
        return request
    }

    static func dataBlob(fromPipelineResponse data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]]
        else {
            return nil
        }
        for result in results {
            guard let rows = result["rows"] as? [[Any]],
                  let firstRow = rows.first,
                  let firstValue = firstRow.first as? [String: Any]
            else {
                continue
            }
            if let base64 = firstValue["base64"] as? String {
                return Data(base64Encoded: base64)
            }
            if let value = firstValue["value"] as? String {
                return Data(base64Encoded: value) ?? Data(value.utf8)
            }
        }
        return nil
    }

    private static func execute(request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

final class NativeTursoReadResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?

    var data: Data? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedData
        }
        set {
            lock.lock()
            storedData = newValue
            lock.unlock()
        }
    }
}
