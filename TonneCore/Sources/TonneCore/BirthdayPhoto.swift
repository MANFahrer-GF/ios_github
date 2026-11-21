import Foundation
import CryptoKit

/// Fotos im Geburtstags-Widget (Wunsch Ralf, 21.11.2026). Die App legt je Foto ein kleines Vorschaubild in die App-Gruppe;
/// der Name enthält einen Hash des Fotos, so zeigt das Widget nach einem Fotowechsel nie ein altes Bild und die App
/// schreibt nur Neues.
public enum BirthdayPhoto {
    public static let folder = "birthday-photos"
    /// Kantenlänge des Vorschaubilds in Pixeln (größter Kreis im Widget: 42 pt bei 3×).
    public static let pixelSize: CGFloat = 132

    public static func id(personID: UUID, photo: Data) -> String {
        let digest = SHA256.hash(data: photo).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(personID.uuidString)-\(digest)"
    }

    /// Dateiname des Vorschaubilds; nil für ungültige IDs (Schutz vor Pfadangaben aus fremden Schnappschüssen).
    public static func fileName(_ id: String) -> String? {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return id + ".jpg"
    }
}
