import Foundation
import OSLog

/// Converts provider failures into short, player-safe messages.
///
/// Raw provider response bodies (JSON error payloads, stack-ish fragments,
/// endpoint internals) are logged to OSLog at the failure site and must never
/// reach `lastError` → `ErrorBanner`. Players get provider, model lane,
/// status, and a retry hint — that's it.
enum NativeProviderErrorSanitizer {
    private static let logger = Logger(
        subsystem: "com.gibavargas.SwiftHistoria",
        category: "ProviderErrors"
    )

    static func playerMessage(provider: String, lane: String, status: Int) -> String {
        switch status {
        case 401, 403:
            "\(provider) rejected the API key (HTTP \(status)). Check the key in Settings for the \(lane) lane and retry."
        case 402:
            "\(provider) reports the account is out of credits (HTTP 402) for the \(lane) lane."
        case 408:
            "\(provider) timed out (HTTP 408) on the \(lane) lane. Wait a moment and advance the turn again."
        case 429:
            "\(provider) rate limited the \(lane) lane (HTTP 429). Wait about a minute before advancing again."
        case 500 ... 599:
            "\(provider) had a server error (HTTP \(status)) on the \(lane) lane. Retry in a few seconds."
        default:
            "\(provider) request failed (HTTP \(status)) on the \(lane) lane. Retry, or check Settings."
        }
    }

    /// Logs a raw body fragment for diagnosis and returns nothing — the
    /// fragment must not be embedded in player-visible strings.
    static func logRawBody(provider: String, body: String) {
        let prefix = String(body.prefix(600))
        logger.error("\(provider, privacy: .public) raw body: \(prefix, privacy: .public)")
    }
}
