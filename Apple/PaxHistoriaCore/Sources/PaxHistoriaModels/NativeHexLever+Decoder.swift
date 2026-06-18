import Foundation

public extension NativeHexLever {
    static func decodeHexLever(_ hex: String) -> NativeHexLever? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("0x") {
            clean = String(clean.dropFirst(2))
        }
        guard clean.count == 6 || clean.count == 8 else { return nil }
        let chars = Array(clean)

        func decodeNibble(_ char: Character) -> Int? {
            guard let val = char.hexDigitValue else { return nil }
            return val >= 8 ? val - 16 : val
        }

        guard let g = decodeNibble(chars[0]),
              let b = decodeNibble(chars[1]),
              let d = decodeNibble(chars[2]),
              let i = decodeNibble(chars[3]),
              let t = decodeNibble(chars[4]),
              let f = decodeNibble(chars[5])
        else {
            return nil
        }

        var securityDelta = 0.0
        var rebelDelta = 0.0
        var invasionNudge = 0

        if chars.count == 8 {
            if let s = decodeNibble(chars[6]) {
                securityDelta = Double(s) * 2.5
                rebelDelta = Double(-s) * 1.5
            }
            if let v = decodeNibble(chars[7]) {
                invasionNudge = v
            }
        }

        return NativeHexLever(
            growthDelta: Double(g) * 0.1,
            budgetDelta: Double(b) * 0.05,
            debtDelta: Double(d) * 0.2,
            inflationDelta: Double(i) * 0.05,
            tradeDelta: Double(t) * 0.05,
            fiscalSpaceDelta: f,
            securityDelta: securityDelta,
            rebelDelta: rebelDelta,
            invasionNudge: invasionNudge
        )
    }
}
