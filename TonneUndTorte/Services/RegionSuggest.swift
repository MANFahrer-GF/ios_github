import Foundation
import CoreLocation
import TonneCore

/// Ermittelt per Standort den Ort/Landkreis und schlägt passende Katalogeinträge vor.
@MainActor
final class RegionSuggest: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var placeName: String?
    @Published var suggestions: [CatalogEntry] = []
    @Published var isWorking = false
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func locate() {
        errorMessage = nil
        isWorking = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isWorking = false
            errorMessage = "Standortzugriff ist deaktiviert – bitte Ort von Hand eingeben."
        default:
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus), self.isWorking {
                manager.requestLocation()
            } else if [.denied, .restricted].contains(manager.authorizationStatus) {
                self.isWorking = false
                self.errorMessage = "Standortzugriff ist deaktiviert – bitte Ort von Hand eingeben."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                let place = placemarks.first
                // Bundesland nur als Rückfall: „Bayern“ träfe sonst z. B. „Königsberg in Bayern“ (Haßberge) bei jedem bayerischen Ort
                let local = [place?.locality, place?.subAdministrativeArea].compactMap { $0 }
                let terms = local.isEmpty ? [place?.administrativeArea].compactMap { $0 } : local
                self.placeName = terms.first
                var found: [CatalogEntry] = []
                for term in terms {
                    for entry in ProviderCatalog.search(term) where !found.contains(entry) { found.append(entry) }
                    // „Landkreis X“ → auch nach „X“ suchen
                    let short = term.replacingOccurrences(of: "Landkreis ", with: "").replacingOccurrences(of: "Kreis ", with: "")
                    for entry in ProviderCatalog.search(short) where !found.contains(entry) { found.append(entry) }
                }
                self.suggestions = found
                if found.isEmpty { self.errorMessage = "Für \(self.placeName ?? "deine Region") ist noch kein Entsorger im Katalog – bitte unten suchen oder ICS-Link nutzen." }
            } catch {
                self.errorMessage = "Ort konnte nicht bestimmt werden."
            }
            self.isWorking = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isWorking = false
            self.errorMessage = "Standort konnte nicht ermittelt werden."
        }
    }
}
