import UIKit
import TonneCore

/// Geburtstagsliste als PDF: Titel, Datum, Tabelle mit Name, Geburtstag, Alter, nächster Termin, Geschenkideen.
enum BirthdayPDF {
    static func render(_ rows: [BirthdayExport.Row], title: String = "Tonne & Torte – Geburtstage") -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 in Punkt
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: UIGraphicsPDFRendererFormat())
        let sorted = BirthdayExport.sorted(rows)
        let columns: [(title: String, width: CGFloat)] = [
            (L10n.t("Name", "Name"), 150), (L10n.t("Geburtstag", "Birthday"), 80), (L10n.t("Alter", "Age"), 45),
            (L10n.t("Nächster", "Next"), 110), (L10n.t("Geschenkideen / Notizen", "Gift ideas / notes"), 130),
        ]
        let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
        let headFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 10)
        let smallFont = UIFont.systemFont(ofSize: 8)
        let rowHeight: CGFloat = 22

        return renderer.pdfData { context in
            var y: CGFloat = 0
            var page = 0
            func startPage() {
                context.beginPage()
                page += 1
                y = margin
                title.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont, .foregroundColor: UIColor.label])
                let stamp = Date().formatted(date: .long, time: .omitted) + " · " + L10n.t("Seite", "Page") + " \(page)"
                let stampWidth = (stamp as NSString).size(withAttributes: [.font: smallFont]).width
                stamp.draw(at: CGPoint(x: pageRect.width - margin - stampWidth, y: y + 8), withAttributes: [.font: smallFont, .foregroundColor: UIColor.secondaryLabel])
                y += 36
                var x = margin
                UIColor.systemGray5.setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: rowHeight), cornerRadius: 4).fill()
                for column in columns {
                    column.title.draw(in: CGRect(x: x + 6, y: y + 5, width: column.width - 8, height: rowHeight), withAttributes: [.font: headFont, .foregroundColor: UIColor.label])
                    x += column.width
                }
                y += rowHeight + 2
            }
            startPage()
            for (index, row) in sorted.enumerated() {
                if y + rowHeight > pageRect.height - margin { startPage() }
                if index % 2 == 1 {
                    UIColor.systemGray6.withAlphaComponent(0.6).setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: rowHeight)).fill()
                }
                let next = row.annual.next()
                let turns = next.flatMap { row.annual.years(on: $0) }
                let nextText = next.map { "\(DateText.short($0)) · \(DateText.countdown($0))" + (turns.map { " (\($0))" } ?? "") } ?? "–"
                let extra = (row.giftIdeas.map { "🎁 \($0)" } + (row.notes.isEmpty ? [] : [row.notes])).joined(separator: " · ")
                let values = [row.name, BirthdayExport.dateString(row.annual), BirthdayExport.currentAge(row.annual).map(String.init) ?? "–", nextText, extra]
                var x = margin
                for (column, value) in zip(columns, values) {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineBreakMode = .byTruncatingTail
                    (value as NSString).draw(in: CGRect(x: x + 6, y: y + 5, width: column.width - 8, height: rowHeight - 4), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.label, .paragraphStyle: paragraph])
                    x += column.width
                }
                y += rowHeight
            }
            let footer = L10n.t("\(sorted.count) Geburtstage · erstellt mit Tonne & Torte", "\(sorted.count) birthdays · created with Tonne & Torte")
            footer.draw(at: CGPoint(x: margin, y: pageRect.height - margin + 10), withAttributes: [.font: smallFont, .foregroundColor: UIColor.secondaryLabel])
        }
    }
}

extension Person {
    var exportRow: BirthdayExport.Row {
        BirthdayExport.Row(name: name, annual: annual, notes: notes, giftIdeas: giftIdeas, phone: phone, remindersEnabled: remindersEnabled, remindDaysBefore: remindDaysBefore)
    }
}
