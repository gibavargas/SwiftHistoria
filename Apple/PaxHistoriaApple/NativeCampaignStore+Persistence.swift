import Foundation
import OSLog
import SwiftUI

/// File I/O, persistence, and campaign-state loading.
extension NativeCampaignStore {
    static func removePersistedCampaignState(defaults: UserDefaults, persistenceDirectory: URL) {
        defaults.removeObject(forKey: selectedCountryKey)
        defaults.removeObject(forKey: selectedLanguageKey)
        defaults.removeObject(forKey: selectedScenarioKey)
        defaults.removeObject(forKey: campaignStateKey)
        defaults.removeObject(forKey: campaignStateEnvelopeKey)
        defaults.removeObject(forKey: campaignStateBackupKey)
        for fileName in [campaignStateEnvelopeFileName, campaignStateBackupFileName, campaignStateLegacyFileName] {
            try? FileManager.default.removeItem(at: persistenceDirectory.appendingPathComponent(fileName))
        }
    }

    func persistState() {
        guard let state else {
            defaults.removeObject(forKey: Self.campaignStateKey)
            defaults.removeObject(forKey: Self.campaignStateEnvelopeKey)
            defaults.removeObject(forKey: Self.campaignStateBackupKey)
            removePersistedCampaignFiles()
            return
        }

        // Persistence is deliberately redundant: primary versioned envelope,
        // last-good envelope backup, and a direct legacy state blob. The read
        // path tries them in that order so corrupt primary data can be recovered
        // without losing old-save compatibility.
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
            persistenceDirectory: persistenceDirectory
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
                fileName: Self.campaignStateBackupFileName,
                directory: persistenceDirectory
            )
            try Self.writePersistenceData(
                envelopeData,
                fileName: Self.campaignStateEnvelopeFileName,
                directory: persistenceDirectory
            )
            try Self.writePersistenceData(
                legacyData,
                fileName: Self.campaignStateLegacyFileName,
                directory: persistenceDirectory
            )
            Self.storeDefaultsFallback(backupData, forKey: Self.campaignStateBackupKey, defaults: defaults)
            Self.storeDefaultsFallback(envelopeData, forKey: Self.campaignStateEnvelopeKey, defaults: defaults)
            Self.storeDefaultsFallback(legacyData, forKey: Self.campaignStateKey, defaults: defaults)
            logger.info("Native campaign persisted round=\(state.round, privacy: .public) timeline=\(state.timeline.count, privacy: .public)")
        } catch {
            logger.error("Native campaign file persistence failed")
        }
    }

    static func loadSelectedCountry(from defaults: UserDefaults, decoder: JSONDecoder) -> PlayerCountry? {
        guard let data = defaults.data(forKey: selectedCountryKey) else {
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
                try Self.removePersistenceData(fileName: fileName, directory: persistenceDirectory)
            } catch {
                logger.error("Native campaign persistence cleanup failed")
            }
        }
    }

    static func loadCampaignState(
        from defaults: UserDefaults,
        decoder: JSONDecoder,
        persistenceDirectory: URL
    ) -> CampaignLoadResult {
        let primarySources = persistenceSources(
            defaults: defaults,
            key: campaignStateEnvelopeKey,
            fileName: campaignStateEnvelopeFileName,
            directory: persistenceDirectory
        )
        if let primary = newestEnvelope(from: primarySources, decoder: decoder) {
            let notice = primary.sourceLabel == "file"
                ? nil
                : "Loaded the newest campaign save from user-defaults because it is newer than the file copy."
            return CampaignLoadResult(state: primary.envelope.state, notice: notice)
        }

        let backupSources = persistenceSources(
            defaults: defaults,
            key: campaignStateBackupKey,
            fileName: campaignStateBackupFileName,
            directory: persistenceDirectory
        )
        if let backup = newestEnvelope(from: backupSources, decoder: decoder) {
            let notice = primarySources.isEmpty
                ? "Loaded the last-good campaign backup because the primary save was missing."
                : "Recovered the campaign from the last-good backup because the primary save was corrupt."
            return CampaignLoadResult(state: backup.envelope.state, notice: "\(notice) Source: \(backup.sourceLabel).")
        }

        let legacySources = persistenceSources(
            defaults: defaults,
            key: campaignStateKey,
            fileName: campaignStateLegacyFileName,
            directory: persistenceDirectory
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

    static func defaultPersistenceDirectory(fileManager: FileManager = .default) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("SwiftHistoria", isDirectory: true)
            .appendingPathComponent("NativeCampaigns", isDirectory: true)
    }

    static func primaryPersistenceData(
        from defaults: UserDefaults,
        persistenceDirectory: URL
    ) -> Data? {
        let sources = persistenceSources(
            defaults: defaults,
            key: campaignStateEnvelopeKey,
            fileName: campaignStateEnvelopeFileName,
            directory: persistenceDirectory
        )
        return newestEnvelope(from: sources, decoder: JSONDecoder())?.sourceData ?? sources.first?.data
    }

    static func storeDefaultsFallback(_ data: Data, forKey key: String, defaults: UserDefaults) {
        if data.count <= maximumUserDefaultsCampaignBlobBytes {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func newestEnvelope(
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

    static func persistenceSources(
        defaults: UserDefaults,
        key: String,
        fileName: String,
        directory: URL
    ) -> [PersistenceDataSource] {
        var sources: [PersistenceDataSource] = []
        if let data = readPersistenceData(fileName: fileName, directory: directory) {
            sources.append(PersistenceDataSource(data: data, label: "file"))
        }
        if let data = defaults.data(forKey: key) {
            sources.append(PersistenceDataSource(data: data, label: "user-defaults"))
        }
        return sources
    }

    static func persistenceURL(fileName: String, directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func readPersistenceData(fileName: String, directory: URL) -> Data? {
        try? Data(contentsOf: persistenceURL(fileName: fileName, directory: directory))
    }

    static func writePersistenceData(_ data: Data, fileName: String, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: persistenceURL(fileName: fileName, directory: directory), options: [.atomic])
    }

    static func removePersistenceData(fileName: String, directory: URL) throws {
        let url = persistenceURL(fileName: fileName, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
