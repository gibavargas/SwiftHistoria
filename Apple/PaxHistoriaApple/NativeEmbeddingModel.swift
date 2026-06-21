import Foundation

// Tiny deterministic embedding model used for semantic
// memory and cosine similarity over short strategy text.

enum NativeTinyEmbeddingModel {
    private static let dimensions = 64

    static func embed(_ text: String) -> [Float] {
        var vector = Array(repeating: Float(0), count: dimensions)
        for token in tokens(text) {
            let hash = token.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
            let index = Int(hash % UInt64(dimensions))
            vector[index] += (hash & 1) == 0 ? 1 : -1
        }
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        Double(zip(lhs, rhs).reduce(Float(0)) { $0 + $1.0 * $1.1 })
    }

    private static func tokens(_ text: String) -> [String] {
        let base = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        return base.flatMap { token in [token] + aliases[token, default: []] }
    }

    private static let aliases: [String: [String]] = [
        "airport": ["logistics", "corridor", "trade"],
        "border": ["security", "sovereignty", "conflict"],
        "budget": ["fiscal", "debt", "capacity"],
        "corridor": ["logistics", "trade", "infrastructure"],
        "debt": ["budget", "fiscal", "market"],
        "diplomacy": ["relations", "treaty", "leverage"],
        "education": ["services", "capacity", "stability"],
        "energy": ["infrastructure", "resilience", "industry"],
        "fiscal": ["budget", "debt", "capacity"],
        "inflation": ["prices", "market", "stability"],
        "insurgency": ["security", "stabilization", "rebel"],
        "market": ["confidence", "trade", "growth"],
        "port": ["logistics", "corridor", "trade"],
        "rail": ["logistics", "corridor", "infrastructure"],
        "rebel": ["insurgency", "security", "stabilization"],
        "security": ["stabilization", "insurgency", "resilience"],
        "services": ["education", "health", "stability"],
        "stability": ["services", "security", "legitimacy"],
        "stabilization": ["security", "insurgency", "resilience"],
        "trade": ["corridor", "market", "diplomacy"],
        "unemployment": ["jobs", "growth", "stability"]
    ]
}

extension NativeStrategyContextDatabase {
    /// Test-only accessor for the tiny embedding model.
    static func embedForTesting(_ text: String) -> [Float] {
        NativeTinyEmbeddingModel.embed(text)
    }

    /// Test-only accessor for cosine similarity.
    static func cosineForTesting(_ lhs: [Float], _ rhs: [Float]) -> Double {
        NativeTinyEmbeddingModel.cosine(lhs, rhs)
    }
}
