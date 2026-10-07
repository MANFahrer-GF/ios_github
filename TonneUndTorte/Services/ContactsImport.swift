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
        var errorDescription: String? { "Kontaktzugriff wurde nicht erlaubt. Bitte in den Einstellungen freigeben." }
    }

    static func candidates() async throws -> [Candidate] {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else { throw ImportError.denied }
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
