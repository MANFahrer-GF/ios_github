import SwiftUI
import MessageUI
import TonneCore

private let crashReportAddress = "thomas@kant.ovh"

struct CrashReportFile: Transferable {
    let report: CrashReport
    /// Hinweis aus der Update-Prüfung („trotz Update gesendet“), steht über dem Bericht.
    var note: String? = nil
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in Data(((file.note.map { $0 + "\n\n" } ?? "") + file.report.fileText).utf8) }
            .suggestedFileName("Tonne-und-Torte-Absturzbericht.txt")
    }
}

/// Hängt am Wurzel-Bildschirm: bietet einen neuen Absturzbericht einmal an. Ein einziges Sheet für Hinweis und Versand,
/// damit sich nicht zwei Präsentationen überlappen. Wie es auch geschlossen wird: Der Hinweis kommt nicht noch einmal.
struct CrashReportPrompt: View {
    @EnvironmentObject private var center: CrashReportCenter
    @State private var offer: CrashReport?
    @State private var offeredIDs: [String] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .onAppear(perform: offerNext)
            .onChange(of: center.reports) { _, _ in offerNext() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { offerNext() } }
            .sheet(item: $offer, onDismiss: {
                center.markOffered(offeredIDs)
                offerNext()
            }) { CrashReportOfferSheet(report: $0).appTypography() }
    }

    /// Was während des offenen Sheets dazukommt, wird nicht mit abgehakt und danach eigens angeboten.
    private func offerNext() {
        guard offer == nil, !otherSheetIsOpen, let report = center.reportToOffer else { return }
        offeredIDs = center.idsToOffer
        offer = report
    }

    /// Über ein offenes Sheet kann SwiftUI kein zweites legen – dann beim nächsten Aktivieren der App erneut versuchen.
    private var otherSheetIsOpen: Bool {
        UIApplication.shared.connectedScenes.contains { scene in
            (scene as? UIWindowScene)?.keyWindow?.rootViewController?.presentedViewController != nil
        }
    }
}

private struct CrashReportOfferSheet: View {
    let report: CrashReport
    @State private var reviewing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if reviewing {
            CrashReportSendSheet(report: report)
        } else {
            NavigationStack {
                Form {
                    Section {
                        Text(L10n.t("Magst du den Absturzbericht per Mail schicken? Er enthält technische Angaben zum Absturz. Deine Termine, Namen oder Orte fügt die App nicht hinzu. Du siehst die Mail vor dem Absenden.",
                                    "Would you like to send the crash report by email? It contains technical details about the crash. The app doesn't add your events, names or places. You'll see the email before it's sent."))
                    }
                    Section {
                        Button(L10n.t("Ansehen und senden", "Review and send")) { reviewing = true }
                        Button(L10n.t("Nicht jetzt", "Not now")) { dismiss() }
                    }
                }
                .navigationTitle(L10n.t("Tonne & Torte ist abgestürzt", "Tonne & Torte crashed"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// Erst die Update-Prüfung (`UpdateCheck`): Ist eine neuere Version da, als die des Berichts oder die installierte, sagt
/// die App das und bietet den App Store an; senden geht trotzdem, dann mit Vermerk. Danach die Mail mit dem Bericht im
/// Anhang; ohne eingerichtete Mail-App bleibt das Teilen der Datei.
/// Der Bericht bleibt nach dem Senden erhalten: „gesendet“ heißt nur, dass die Mail in der Warteschlange liegt.
struct CrashReportSendSheet: View {
    let report: CrashReport
    @State private var verdict: UpdateCheck.Verdict?
    @State private var storeURL: URL?
    @State private var note: String?
    @State private var confirmed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch verdict {
        case nil:
            ProgressView(L10n.t("Suche nach Updates …", "Checking for updates …"))
                .task { await check() }
        case .updateAvailable(let store)? where !confirmed:
            hint(L10n.t("Es gibt eine neuere Version von Tonne & Torte (\(store)). Der Fehler ist dort vielleicht schon behoben. Bitte aktualisiere zuerst und schick den Bericht nur, wenn die App danach wieder abstürzt.",
                        "There's a newer version of Tonne & Torte (\(store)). The problem may already be fixed there. Please update first and only send the report if the app crashes again."),
                 note: "Gesendet trotz verfügbarem Update: installiert \(StoreVersion.installed), im App Store \(store)",
                 offersStore: true, title: L10n.t("Update verfügbar", "Update available"))
        case .reportFromOlderVersion(let old, let installed)? where !confirmed:
            hint(L10n.t("Der Absturz passierte in Version \(old). Inzwischen ist Version \(installed) installiert, dort ist der Fehler vielleicht schon behoben. Schick den Bericht nur, wenn die App auch jetzt noch abstürzt.",
                        "The crash happened in version \(old). Version \(installed) is installed now and the problem may already be fixed there. Only send the report if the app still crashes."),
                 note: "Gesendet trotz neuerer Version: Bericht aus \(old), installiert \(StoreVersion.installed)",
                 offersStore: false, title: L10n.t("Neuere Version installiert", "Newer version installed"))
        default:
            send
        }
    }

    private func check() async {
        let latest = await StoreVersion.latest()
        storeURL = latest?.url
        verdict = UpdateCheck.verdict(report: report.appVersion, installed: StoreVersion.installed, store: latest?.version)
    }

    private func hint(_ text: String, note: String, offersStore: Bool, title: String) -> some View {
        NavigationStack {
            Form {
                Section { Text(text) }
                Section {
                    if offersStore, let storeURL {
                        Button(L10n.t("Zum App Store", "Open App Store")) { openURL(storeURL); dismiss() }
                    }
                    Button(L10n.t("Trotzdem senden", "Send anyway")) { self.note = note; confirmed = true }
                    Button(L10n.t("Nicht senden", "Don't send")) { dismiss() }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var send: some View {
        if MFMailComposeViewController.canSendMail() {
            CrashMailComposer(report: report, note: note) { dismiss() }
                .ignoresSafeArea()
        } else {
            NavigationStack {
                Form {
                    Section {
                        Text(L10n.t("Auf diesem Gerät ist keine Mail-App eingerichtet. Du kannst den Bericht teilen, zum Beispiel an \(crashReportAddress).",
                                    "No mail account is set up on this device. You can share the report, for example with \(crashReportAddress)."))
                        ShareLink(item: CrashReportFile(report: report, note: note),
                                  preview: SharePreview(L10n.t("Absturzbericht", "Crash report"))) {
                            Label(L10n.t("Bericht teilen", "Share report"), systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .navigationTitle(L10n.t("Absturzbericht", "Crash report"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.t("Schließen", "Close")) { dismiss() } }
                }
            }
        }
    }
}

private struct CrashMailComposer: UIViewControllerRepresentable {
    let report: CrashReport
    let note: String?
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([crashReportAddress])
        mail.setSubject("Tonne & Torte: \(L10n.t("Absturzbericht", "Crash report")) \(report.appVersion)")
        mail.setMessageBody(L10n.t("Der Bericht hängt als Datei an. Wenn du magst, schreib dazu, was du gerade gemacht hast:\n\n\n",
                                   "The report is attached. If you like, add what you were doing:\n\n\n") + (note.map { $0 + "\n" } ?? "") + report.summary, isHTML: false)
        mail.addAttachmentData(Data(((note.map { $0 + "\n\n" } ?? "") + report.fileText).utf8), mimeType: "text/plain", fileName: "Tonne-und-Torte-Absturzbericht.txt")
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish()
        }
    }
}
