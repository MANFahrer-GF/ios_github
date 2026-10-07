import UIKit
import Contacts
import ContactsUI

/// Systemauswahl für Kontakte (CNContactPickerViewController). Braucht keine Kontaktfreigabe:
/// Die ausgewählten Personen kommen direkt zurück, auch wenn nur einzelne oder gar keine Kontakte freigegeben sind.
/// Wird über UIKit gezeigt, weil die Auswahl in einem SwiftUI-Sheet leer bzw. schwarz bleibt.
@MainActor
enum ContactsPicker {
    private static var delegate: Delegate?
    /// Die gerade gezeigte Auswahl. Schwach gehalten: Ist sie zu, wird das automatisch `nil`.
    private static weak var activePicker: CNContactPickerViewController?

    /// Liefert die übernehmbaren Personen und wie viele Ausgewählte ausgelassen wurden (kein Name oder kein vollständiges Datum).
    static func present(completion: @escaping (_ chosen: [ContactsImport.Candidate], _ skipped: Int) -> Void) {
        // Schon offen (z. B. Doppeltipp): nicht ein zweites Mal zeigen, sonst ginge die erste Auswahl verloren.
        guard activePicker == nil, let presenter = topViewController() else { return }
        let picker = CNContactPickerViewController()
        // Nur Kontakte mit Geburtstag sind auswählbar.
        picker.predicateForEnablingContact = NSPredicate(format: "birthday != nil")
        let delegate = Delegate { contacts in
            ContactsPicker.delegate = nil
            let chosen = contacts.compactMap(ContactsImport.candidate(from:))
            completion(chosen, contacts.count - chosen.count)
        }
        self.delegate = delegate
        activePicker = picker
        picker.delegate = delegate
        presenter.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }

    private final class Delegate: NSObject, CNContactPickerDelegate {
        let done: ([CNContact]) -> Void
        init(done: @escaping ([CNContact]) -> Void) { self.done = done }

        // Mehrfachauswahl: Weil diese Methode existiert, zeigt iOS Häkchen und „Fertig“.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) { done(contacts) }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { done([]) }
    }
}
