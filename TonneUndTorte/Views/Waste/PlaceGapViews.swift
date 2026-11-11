import SwiftUI
import TonneCore

/// Karte für eine Gemeinde ohne belegten Entsorger – gleich in „Geht mein Ort?“ und im Einrichtungsassistenten:
/// Grund im Klartext (Entsorger, Prüftag), Webseite des Entsorgers und direkte Wege zu den Terminen.
struct PlaceGapSection: View {
    let check: PlaceCheck
    /// Springt zum Feld für den Kalender-Link (nur im Assistenten).
    var onPasteLink: (() -> Void)? = nil
    /// Öffnet die Dateiauswahl für ICS-/CSV-Termine (nur im Assistenten).
    var onImportFile: (() -> Void)? = nil

    private var gap: PlaceGap { check.gap ?? PlaceGap(reason: "", isUnavailable: false) }

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(gap.headline).font(.subheadline.weight(.semibold))
                    Text(gap.explanation(for: check.name)).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: gap.isUnavailable ? "xmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("placeGapReason")
            if let website = gap.website {
                Link(destination: website) {
                    Label(L10n.t("Webseite von \(gap.provider ?? website.host() ?? "")", "Website of \(gap.provider ?? website.host() ?? "")"),
                          systemImage: "safari")
                }
                .accessibilityIdentifier("placeGapWebsite")
            }
            MissingPlaceActions(onPasteLink: onPasteLink, onImportFile: onImportFile, reportMail: check.reportMailURL)
        } header: {
            Text("\(check.name) · \(DistrictCoverage.displayName(check.district))")
        } footer: {
            Text(L10n.t("Hast du einen Kalender-Link oder eine Datei vom Entsorger, kannst du die Termine trotzdem nutzen. Meldest du den Ort, prüfen wir den Hinweis.",
                        "If you have a calendar link or a file from the provider, you can still use your dates. If you report the town, we will look into it."))
        }
    }
}

/// Wege zu den Terminen, wenn die Suche keine Gemeinde findet oder kein Ort eingegeben ist.
struct MissingPlaceHelpSection: View {
    var onPasteLink: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        Section {
            // Ohne Suchtext: der könnte eine Adresse sein.
            MissingPlaceActions(onPasteLink: onPasteLink, onImportFile: onImportFile, reportMail: PlaceCheck.blankReportMailURL)
        } header: {
            Text(L10n.t("Ort fehlt? So geht es trotzdem", "Town missing? How to still get your dates"))
        } footer: {
            Text(L10n.t("Meldest du den Ort, prüfen wir den Hinweis.", "If you report the town, we will look into it."))
        }
    }
}

/// Knöpfe statt Hilfetext: Link einfügen, Datei laden, Ort melden; Rhythmus und CSV-Vorlage unter „Weitere Möglichkeiten“.
private struct MissingPlaceActions: View {
    var onPasteLink: (() -> Void)?
    var onImportFile: (() -> Void)?
    var reportMail: URL?

    var body: some View {
        if let onPasteLink {
            Button(action: onPasteLink) {
                Label(L10n.t("Kalender-Link einfügen", "Paste calendar link"), systemImage: "link")
            }
            .accessibilityIdentifier("placeGapPasteLink")
        }
        if let onImportFile {
            Button(action: onImportFile) {
                Label(L10n.t("Termine aus Datei laden", "Load dates from a file"), systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("placeGapImportFile")
        }
        if let reportMail {
            Link(destination: reportMail) {
                Label(L10n.t("Ort melden", "Report town"), systemImage: "envelope")
            }
            .accessibilityIdentifier("placeGapReport")
        }
        DisclosureGroup {
            if onPasteLink == nil {
                Label(L10n.t("Kalender-Link oder Datei: beim Anlegen eines Standorts unter „Entsorger nicht dabei?“.",
                             "Calendar link or file: when adding a location, under “Provider not listed?”."),
                      systemImage: "link")
            }
            Label(L10n.t("Feste Abfuhr (z. B. alle 2 Wochen dienstags) als Rhythmus bei der Müllart einstellen.",
                         "Set a fixed schedule (e.g. every 2 weeks on Tuesday) as a rhythm in the waste type."),
                  systemImage: "repeat")
            ShareLink(item: PickupCSVFile(text: PickupCSV.template(), fileName: L10n.t("Abfuhrtermine-Vorlage.csv", "Pickup-template.csv")),
                      preview: SharePreview(L10n.t("CSV-Vorlage", "CSV template"))) {
                Label(L10n.t("CSV-Vorlage für Termine vom Papierkalender", "CSV template for dates from a paper calendar"),
                      systemImage: "tablecells")
            }
        } label: {
            Text(L10n.t("Weitere Möglichkeiten", "More options"))
        }
        .font(.subheadline)
        .accessibilityIdentifier("placeGapMore")
    }
}
