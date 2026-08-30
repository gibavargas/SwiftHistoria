@testable import SwiftHistoria
import XCTest

final class TurnTickerProseTests: XCTestCase {
    func testQuotesExistForEveryLanguage() {
        for language in NativeGameLanguage.allCases {
            let quotes = TurnTickerProse.quotes(for: language)
            XCTAssertEqual(quotes.count, 30, "\(language) column drifted from 30 lines")
            for quote in quotes {
                XCTAssertFalse(quote.trimmingCharacters(in: .whitespaces).isEmpty, "\(language) has an empty line")
            }
        }
    }

    func testPortugueseColumnMatchesOriginalTickerCopy() {
        XCTAssertEqual(
            TurnTickerProse.quotes(for: .portuguese).first,
            "Reconstruindo redes de inteligência regional..."
        )
        XCTAssertEqual(
            TurnTickerProse.quotes(for: .portuguese).last,
            "Integrando pacotes de inteligência aliada..."
        )
    }

    func testEnglishFallbackIsNonEmptyAndDistinct() {
        let english = TurnTickerProse.quotes(for: .english)
        let spanish = TurnTickerProse.quotes(for: .spanish)
        XCTAssertEqual(english.count, spanish.count)
        XCTAssertEqual(Set(english).count, english.count, "English column contains duplicate lines")
    }
}
