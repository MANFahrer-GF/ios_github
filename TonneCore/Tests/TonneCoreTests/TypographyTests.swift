import XCTest
@testable import TonneCore

final class TypographyTests: XCTestCase {
    func testStandardIsTheLookUntil2011() {
        XCTAssertEqual(TypographySettings.standard.family, .rounded)
        // Bei iOS-Grundgröße „large“ bleibt jede feste Größe unverändert
        for size in [11.0, 13, 17, 24, 36, 64] {
            XCTAssertEqual(TypographySettings.scale(sizeIndex: TypographySettings.defaultSizeIndex, baseSize: size), 1, accuracy: 0.0001)
        }
    }

    func testEmptyOrUnknownDefaultsGiveRounded() {
        let defaults = UserDefaults(suiteName: "typography.test.\(UUID())")!
        XCTAssertEqual(TypographySettings(defaults: defaults), .standard)
        defaults.set("comic", forKey: TypographySettings.familyKey)
        XCTAssertEqual(TypographySettings(defaults: defaults), .standard)
    }

    func testRoundTripThroughDefaults() {
        let defaults = UserDefaults(suiteName: "typography.test.\(UUID())")!
        for family in TypographySettings.Family.allCases {
            TypographySettings(family: family).write(to: defaults)
            XCTAssertEqual(TypographySettings(defaults: defaults).family, family)
        }
    }

    func testSizeFollowsIOSButNeverAboveXXXLarge() {
        XCTAssertEqual(TypographySettings.sizeIndex(system: 0), 0)
        XCTAssertEqual(TypographySettings.sizeIndex(system: 3), 3)
        XCTAssertEqual(TypographySettings.sizeIndex(system: 6), 6)
        // Bedienungshilfen-Größen von iOS (7…11) enden bei „xxxLarge“
        for system in 7...11 { XCTAssertEqual(TypographySettings.sizeIndex(system: system), TypographySettings.maxSizeIndex) }
        XCTAssertEqual(TypographySettings.sizeIndex(system: 11, maxIndex: 99), TypographySettings.maxSizeIndex)
        // Widgets begrenzen auf eine kleinere Höchststufe
        XCTAssertEqual(TypographySettings.sizeIndex(system: 11, maxIndex: 4), 4)
    }

    func testScaleGrowsMonotonicAndDampsLargeNumbers() {
        let reachable = 0...TypographySettings.maxSizeIndex
        for size in [13.0, 24, 36] {
            let factors = reachable.map { TypographySettings.scale(sizeIndex: $0, baseSize: size) }
            XCTAssertEqual(factors, factors.sorted(), "Faktor steigt mit der Stufe (\(size) pt)")
        }
        let top = TypographySettings.maxSizeIndex
        XCTAssertLessThan(TypographySettings.scale(sizeIndex: top, baseSize: 36), TypographySettings.scale(sizeIndex: top, baseSize: 13))
        XCTAssertLessThan(TypographySettings.scale(sizeIndex: 0, baseSize: 17), 1)
    }
}
