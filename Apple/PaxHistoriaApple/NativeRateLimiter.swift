import Foundation
import OSLog

/// Sliding-window rate limiter for OpenRouter free API.
///
/// Stress-test results: OpenRouter enforces 20 requests/minute per key.
/// This limiter tracks timestamps in a sliding 60-second window and
/// blocks (suspends) new requests until capacity is available.
///
/// Conservative limit: 8 req/min (60% margin) to account for:
/// - Retry storms where multiple lanes fail simultaneously
/// - OpenRouter counting ALL requests (including 429s) against the limit
/// - Sub-second timing jitter between lanes
actor NativeRateLimiter {
    static let shared = NativeRateLimiter()

    /// OpenRouter hard limit: 20 req/min (confirmed via stress-test)
    static let providerLimit = 20
    /// 60% safety margin → 8 req/min effective (very conservative to avoid 429 storms)
    static let effectiveLimit = 8

    private var timestamps: [Date] = []
    private let windowDuration: TimeInterval = 60.0

    /// Wait until a request slot is available, then record it.
    func acquire() async {
        while true {
            let now = Date()
            timestamps = timestamps.filter { now.timeIntervalSince($0) < windowDuration }
            if timestamps.count < Self.effectiveLimit {
                timestamps.append(now)
                return
            }
            // Wait until the oldest timestamp exits the window
            if let oldest = timestamps.first {
                let waitTime = windowDuration - now.timeIntervalSince(oldest) + 0.5
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
    }

    /// Non-blocking check — returns available capacity right now.
    func availableSlots() -> Int {
        let now = Date()
        timestamps = timestamps.filter { now.timeIntervalSince($0) < windowDuration }
        return max(0, Self.effectiveLimit - timestamps.count)
    }
}
