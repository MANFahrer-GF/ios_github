import Foundation
import Contacts
import TonneCore

/// Liest Geburtstage aus den Kontakten.
enum ContactsImport {
    struct Candidate: Identifiable, Hashable {
        let identifier: String
        let name: String
        let day: Int
        let month: Int
        let year: Int?
        let phone: String?
        var id: String { identifier }
    }

    enum ImportError: LocalizedError {
        case denied
        var errorDescription: String? { L10n.t("Kontaktzugriff wurde nicht erlaubt. Bitte in den Einstellungen freigeben.", "Contacts access was not allowed. Please enable it in Settings.") }
    }

    /// Jahr, das Kontakte-Konten für „ohne Jahr“ eintragen; alles bis dahin ist kein echtes Geburtsjahr.
    static let placeholderYear = 1604

    /// Geburtsjahr ohne Platzhalter.
    static func realYear(_ year: Int?) -> Int? { year.flatMap { $0 > placeholderYear ? $0 : nil } }

    enum Access { case full, limited, denied, notDetermined }

    /// Aktueller Freigabestatus. Seit iOS 18 kann man auch nur ausgewählte Kontakte freigeben.
    static var access: Access {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18.0, *), status == .limited { return .limited }
        switch status {
        case .authorized: return .full
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static func candidates() async throws -> [Candidate] {
        if access == .notDetermined {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        }
        guard access == .full || access == .limited else { throw ImportError.denied }
        // Viele Kontakte zu lesen dauert, darum nicht auf dem Hauptthread.
        return try await Task.detached(priority: .userInitiated) { try fetchAll() }.value
    }

    private static func fetchAll() throws -> [Candidate] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        var result: [Candidate] = []
        try store.enumerateContacts(with: request) { contact, _ in
            if let candidate = candidate(from: contact) { result.append(candidate) }
        }
        return result
    }

    private static let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor, CNContactBirthdayKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor]

    /// Kontakt mit Geburtstag als Kandidat. Funktioniert auch für Kontakte aus der Systemauswahl, die ohne Kontaktfreigabe kommen.
    static func candidate(from contact: CNContact) -> Candidate? {
        guard contact.isKeyAvailable(CNContactBirthdayKey), let birthday = contact.birthday,
              let day = birthday.day, let month = birthday.month,
              DateComponents(calendar: Calendar(identifier: .gregorian), year: 2000, month: month, day: day).isValidDate else { return nil }
        var name = ""
        if contact.isKeyAvailable(CNContactGivenNameKey), contact.isKeyAvailable(CNContactFamilyNameKey) {
            name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        }
        if name.isEmpty, contact.isKeyAvailable(CNContactNicknameKey) { name = contact.nickname }
        guard !name.isEmpty else { return nil }
        let phone = contact.isKeyAvailable(CNContactPhoneNumbersKey) ? contact.phoneNumbers.first?.value.stringValue : nil
        // Manche Konten speichern „ohne Jahr“ als 1604 – das ist kein echtes Geburtsjahr.
        let year = realYear(birthday.year)
        return Candidate(identifier: contact.identifier, name: name, day: day, month: month, year: year, phone: phone)
    }
}
