import XCTest
@testable import D6000Manager

final class LocalizationTests: XCTestCase {
    private func strings(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    private func specifiers(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:@|lld|04X)")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
    }

    func testBothLanguagesHaveTheSameKeysAndSpecifiers() throws {
        let english = try strings("en")
        let spanish = try strings("es")
        XCTAssertEqual(Set(english.keys), Set(spanish.keys))
        for (key, value) in spanish {
            XCTAssertEqual(specifiers(key), specifiers(value), key)
        }
    }

    func testSpanishTranslationIsUsed() throws {
        XCTAssertEqual(try strings("es")["Dock not detected"], "Dock no detectado")
        XCTAssertEqual(try strings("en")["Dock not detected"], "Dock not detected")
    }
}
