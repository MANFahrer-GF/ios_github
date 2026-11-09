import SwiftUI
import MessageUI
import TonneCore

private let crashReportAddress = "thomas@kant.ovh"

struct CrashReportFile: Transferable {
    let report: CrashReport
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in Data(file.report.fileText.utf8) }
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
            }) { CrashReportOfferSheet(report: $0) }
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

/// Mail mit dem Bericht im Anhang; ohne eingerichtete Mail-App bleibt das Teilen der Datei.
/// Der Bericht bleibt nach dem Senden erhalten: „gesendet“ heißt nur, dass die Mail in der Warteschlange liegt.
struct CrashReportSendSheet: View {
    let report: CrashReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if MFMailComposeViewController.canSendMail() {
            CrashMailComposer(report: report) { dismiss() }
                .ignoresSafeArea()
        } else {
            NavigationStack {
                Form {
                    Section {
                        Text(L10n.t("Auf diesem Gerät ist keine Mail-App eingerichtet. Du kannst den Bericht teilen, zum Beispiel an \(crashReportAddress).",
                                    "No mail account is set up on this device. You can share the report, for example with \(crashReportAddress)."))
                        ShareLink(item: CrashReportFile(report: report),
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
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([crashReportAddress])
        mail.setSubject("Tonne & Torte: \(L10n.t("Absturzbericht", "Crash report")) \(report.appVersion)")
        mail.setMessageBody(L10n.t("Der Bericht hängt als Datei an. Wenn du magst, schreib dazu, was du gerade gemacht hast:\n\n\n",
                                   "The report is attached. If you like, add what you were doing:\n\n\n") + report.summary, isHTML: false)
        mail.addAttachmentData(Data(report.fileText.utf8), mimeType: "text/plain", fileName: "Tonne-und-Torte-Absturzbericht.txt")
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
