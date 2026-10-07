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
        let store = CNContactStore()
        if access == .notDetermined {
            _ = try await store.requestAccess(for: .contacts)
        }
        guard access == .full || access == .limited else { throw ImportError.denied }
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor, CNContactBirthdayKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        var result: [Candidate] = []
        try store.enumerateContacts(with: request) { contact, _ in
            guard let birthday = contact.birthday, let day = birthday.day, let month = birthday.month else { return }
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty else { return }
            result.append(Candidate(identifier: contact.identifier, name: name, day: day, month: month, year: birthday.year, phone: contact.phoneNumbers.first?.value.stringValue))
        }
        return result
    }
}
