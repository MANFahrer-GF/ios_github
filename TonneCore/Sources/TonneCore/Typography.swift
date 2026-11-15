import Foundation

/// Schriftwahl der App (Einstellung „Schrift“ unter „Mehr“): nur die Schriftart. Die Größe folgt der iOS-Textgröße.
/// Reines Modell ohne SwiftUI – App, Widget und Watch übersetzen es in `Font`.
public struct TypographySettings: Equatable, Sendable {
    public enum Family: String, CaseIterable, Sendable {
        /// SF Rounded – so sah die App bisher aus, darum die Grundeinstellung.
        case rounded
        /// SF Pro, die normale iOS-Schrift.
        case standard
        /// New York, die Serifenschrift von iOS.
        case serif
    }

    public var family: Family

    public init(family: Family = .rounded) {
        self.family = family
    }

    public static let standard = TypographySettings()
    public static let familyKey = "typography.family"

    public init(defaults: UserDefaults) {
        self.init(family: Family(rawValue: defaults.string(forKey: Self.familyKey) ?? "") ?? .rounded)
    }

    public func write(to defaults: UserDefaults) {
        defaults.set(family.rawValue, forKey: Self.familyKey)
    }

    // MARK: - Größe (folgt iOS, nach oben begrenzt)

    /// Anzahl der iOS-Textgrößen (xSmall … accessibility5); `large` (Index 3) ist die iOS-Grundeinstellung.
    public static let sizeCount = 12
    public static let defaultSizeIndex = 3
    /// Größte Stufe, die die App mitgeht: „xxxLarge“ (Fließtext 23 statt 17 pt). Die Bedienungshilfen-Größen von iOS
    /// darüber sprengen Karten und Listen (Thomas 15.11.: „zu groß dürfen wir nicht anbieten“) – sie enden hier.
    public static let maxSizeIndex = 6

    /// iOS-Textgröße (Index), begrenzt auf `maxIndex` und nie über `maxSizeIndex`.
    public static func sizeIndex(system: Int, maxIndex: Int = maxSizeIndex) -> Int {
        min(max(system, 0), min(maxIndex, maxSizeIndex))
    }

    /// Faktor für Angaben mit fester Punktgröße: so wie iOS den Fließtext (17 pt) je Stufe vergrößert.
    /// Große Zahlen und Überschriften wachsen gedämpft, damit sie in ihren Karten bleiben.
    public static func scale(sizeIndex: Int, baseSize: Double) -> Double {
        let body: [Double] = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        let factor = body[min(max(sizeIndex, 0), body.count - 1)] / 17
        guard factor > 1 else { return factor }
        let damping = baseSize >= 30 ? 0.4 : baseSize >= 22 ? 0.6 : 1
        return 1 + (factor - 1) * damping
    }
}
