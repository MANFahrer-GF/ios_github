import SwiftUI
import UIKit
import TonneCore

// MARK: - Farben

extension Color {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

// MARK: - Uhrzeit

enum TimeOfDay {
    /// Über Kalender-Bestandteile statt Sekunden ab Mitternacht – sonst zeigt die Auswahl an den Tagen der Zeitumstellung eine Stunde daneben.
    static func date(fromMinutes minutes: Int) -> Date {
        Days.at(minutes: minutes, on: Days.today()) ?? Days.today().addingTimeInterval(TimeInterval(minutes * 60))
    }
    static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

struct TimeOfDayPicker: View {
    let title: String
    @Binding var minutes: Int
    var body: some View {
        DatePicker(title, selection: Binding(get: { TimeOfDay.date(fromMinutes: minutes) }, set: { minutes = TimeOfDay.minutes(from: $0) }), displayedComponents: .hourAndMinute)
    }
}

// MARK: - Karten

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct SymbolBadge: View {
    let symbolName: String
    let colorHex: String
    var size: CGFloat = 44
    /// Name der Abfallart. Gesetzt: eigenes Tonnen-Piktogramm statt SF Symbol (nicht für Orte).
    var wasteName: String? = nil
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: colorHex), Color(hex: colorHex).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            WasteIcon(symbolName: symbolName, name: wasteName ?? "", size: size * 0.45, weight: .semibold, waste: wasteName != nil)
                .foregroundStyle(HexLuma.glyphColor(on: colorHex))
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: colorHex).opacity(0.35), radius: 6, x: 0, y: 3)
    }
}

struct InitialsBadge: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: colorHex), Color(hex: colorHex).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Bild einer Person: eigenes Foto, sonst das Foto aus dem Kontakt, sonst Initialen.
struct PersonAvatar: View {
    let person: Person?
    let initials: String
    let colorHex: String
    var size: CGFloat = 44
    @State private var contactPhoto: Data?

    var body: some View {
        Group {
            if let data = person?.photoData ?? contactPhoto ?? person?.contactIdentifier.flatMap({ ContactPhotoCache.shared.cached($0) }),
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                InitialsBadge(initials: initials, colorHex: colorHex, size: size)
            }
        }
        .task(id: person?.contactIdentifier) {
            guard person?.photoData == nil, let identifier = person?.contactIdentifier else { return }
            contactPhoto = await ContactPhotoCache.shared.load(identifier)
        }
    }
}

/// Einfaches Umbruch-Layout für Chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: maxWidth == .infinity ? totalWidth : maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Auswahl

struct PaletteColorPicker: View {
    @Binding var colorHex: String
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Palette.colors, id: \.self) { hex in
                Circle().fill(Color(hex: hex)).frame(width: 36, height: 36)
                    .overlay { if hex.uppercased() == colorHex.uppercased() { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) } }
                    .onTapGesture { colorHex = hex }
            }
            ColorPicker("", selection: Binding(get: { Color(hex: colorHex) }, set: { colorHex = $0.hexString })).labelsHidden().frame(width: 36, height: 36)
        }
    }
}

struct SymbolPicker: View {
    @Binding var symbolName: String
    let colorHex: String
    var symbols: [String] = Palette.wasteSymbols
    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(symbols, id: \.self) { symbol in
                SymbolTile(isSelected: symbol == symbolName, colorHex: colorHex) {
                    Image(systemName: symbol).font(.title3)
                }
                .onTapGesture { symbolName = symbol }
            }
        }
    }
}

/// Abfallart oder Kategorie mit Piktogramm, z. B. in Auswahlmenüs (dort zählen nur Text und Image).
struct WasteLabel: View {
    let title: String
    let symbolName: String
    var name: String = ""

    var body: some View {
        Label { Text(title) } icon: { Image.waste(symbolName, name: name) }
    }
}

struct WasteCategoryLabel: View {
    let category: WasteCategory
    var title: String? = nil

    var body: some View {
        WasteLabel(title: title ?? category.name, symbolName: category.symbolName, name: category.name)
    }
}

/// Auswahl für Abfallarten: zuerst die eigenen Piktogramme (Gelber Sack und Gelbe Tonne getrennt), dann SF Symbols.
/// `symbolName` ist das angezeigte Symbol (`WasteType.displaySymbol`).
struct WasteSymbolPicker: View {
    @Binding var symbolName: String
    let colorHex: String
    let wasteName: String
    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(WasteGlyph.pickerSymbols, id: \.self) { symbol in
                SymbolTile(isSelected: WasteGlyph.matches(symbol, current: symbolName, name: wasteName), colorHex: colorHex) {
                    Image.waste(symbol).font(.title3)
                }
                .onTapGesture { symbolName = symbol }
            }
        }
    }
}

private struct SymbolTile<Content: View>: View {
    let isSelected: Bool
    let colorHex: String
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Color(hex: colorHex).opacity(0.2) : Color(.tertiarySystemFill)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? Color(hex: colorHex) : .clear, lineWidth: 2))
            .foregroundStyle(isSelected ? Color(hex: colorHex) : .primary)
            .contentShape(Rectangle())
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Standortfilter

enum LocationFilter {
    static func apply(_ id: String) -> UUID? { UUID(uuidString: id) }
}

struct LocationFilterMenu: View {
    let locations: [Location]
    @AppStorage(SettingsKeys.locationFilter) private var filterID: String = ""
    var body: some View {
        if locations.count > 1 {
            Menu {
                Picker("Standort", selection: $filterID) {
                    Label("Alle Standorte", systemImage: "square.grid.2x2").tag("")
                    ForEach(locations) { Label($0.name, systemImage: $0.symbolName).tag($0.id.uuidString) }
                }
            } label: {
                Image(systemName: filterID.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }
    }
}

/// Haptisches Feedback für „Erledigt“ & Co.
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - Anrufen (immer mit Nachfrage)

enum CallLink {
    /// tel:-Link aus einer Telefonnummer, nil ohne Ziffern.
    static func url(_ phone: String?) -> URL? {
        let digits = (phone ?? "").filter { "+0123456789".contains($0) }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}

private struct CallConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let name: String
    let url: URL
    @Environment(\.openURL) private var openURL
    func body(content: Content) -> some View {
        content.confirmationDialog(L10n.t("\(name) anrufen?", "Call \(name)?"), isPresented: $isPresented, titleVisibility: .visible) {
            Button(L10n.t("Anrufen", "Call")) { openURL(url) }
            Button(L10n.t("Abbrechen", "Cancel"), role: .cancel) {}
        }
    }
}

extension View {
    /// Vor dem Anruf nachfragen – nicht aus Versehen telefonieren.
    func callConfirmation(isPresented: Binding<Bool>, name: String, url: URL) -> some View {
        modifier(CallConfirmation(isPresented: isPresented, name: name, url: url))
    }
}

// MARK: - Einträge: gemeinsame Zeile und gemeinsames Bearbeiten-Fenster (Übersicht, Kalender)

/// Was ein Tipp auf einen Eintrag öffnet. Je Seite gibt es genau ein Sheet dafür – verschachtelte Sheets blockieren sich.
enum EventEditTarget: Identifiable {
    case person(Person), event(CustomEvent), waste(WasteType)

    var id: String {
        switch self {
        case .person(let p): return "person-\(p.id)"
        case .event(let e): return "event-\(e.id)"
        case .waste(let w): return "waste-\(w.id)"
        }
    }

    @MainActor
    static func target(for event: CalendarEvent, model: AppModel) -> EventEditTarget? {
        if let id = event.personID, let person = model.allPeople().first(where: { $0.id == id }) { return .person(person) }
        if let id = event.eventID, let custom = model.allCustomEvents().first(where: { $0.id == id }) { return .event(custom) }
        if let id = event.wasteTypeID, let type = model.allWasteTypes().first(where: { $0.id == id }) { return .waste(type) }
        return nil
    }
}

private struct EventEditorSheet: ViewModifier {
    @Binding var target: EventEditTarget?
    func body(content: Content) -> some View {
        content.sheet(item: $target) { item in
            switch item {
            case .person(let person): BirthdayEditView(person: person)
            case .event(let event): CustomEventEditView(event: event)
            case .waste(let type):
                // Müllart (Erinnerungen, Farbe, Symbol, Termine) – wie unter „Müll“, hier als Fenster
                NavigationStack {
                    WasteDetailView(type: type)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.t("Fertig", "Done")) { target = nil } } }
                }
            }
        }
    }
}

extension View {
    func eventEditorSheet(_ target: Binding<EventEditTarget?>) -> some View { modifier(EventEditorSheet(target: target)) }
}

/// Texte zu einem Eintrag – überall gleich.
enum EventText {
    /// Der Name bzw. Titel – „hat Geburtstag“ sagt schon das 🎂-Schildchen und der Tag darüber.
    static func title(_ event: CalendarEvent) -> String { event.title }

    static func birthYear(_ event: CalendarEvent) -> Int? {
        event.years.map { Calendar.current.component(.year, from: event.date) - $0 }
    }

    /// Angaben als einzelne Schildchen – stehen geordnet nebeneinander und brechen nur als Ganzes um.
    /// Geburtstag: „wird 66“, „Jg. 1960“, „♎️ Waage“ („Zeit zum Gratulieren“ nur am Tag selbst ohne bekanntes Alter).
    /// Eigener Termin: Uhrzeit, Wiederholung. Tonne: Standort, falls gewünscht.
    static func tags(_ event: CalendarEvent, person: Person?, showLocation: Bool = false) -> [String] {
        switch event.kind {
        case .birthday:
            var tags: [String] = []
            let cake = event.isMilestone ? "🎉" : "🎂"
            if let years = event.years, let year = birthYear(event) {
                tags += [cake + " " + L10n.t("wird \(years)", "turns \(years)"), L10n.t("Jg. \(year)", "b. \(year)")]
            } else {
                tags.append(cake + " " + (Days.until(event.date) == 0 ? L10n.t("Zeit zum Gratulieren", "Time to celebrate") : L10n.t("Geburtstag", "Birthday")))
            }
            if let zodiac = person?.zodiacLabel { tags.append(zodiac) }
            return tags
        case .custom:
            return event.subtitle.components(separatedBy: " · ")
        case .waste:
            return showLocation ? [event.locationName].compactMap { $0 } : []
        }
    }
}

/// Kleines graues Schildchen für eine Angabe.
struct InfoTag: View {
    let text: String
    var size: CGFloat = 12
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text).font(KlarStyle.font(size, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// Schildchen in einer Reihe, die bei Platzmangel als Ganzes umbrechen.
struct InfoTags: View {
    let tags: [String]
    var size: CGFloat = 12
    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 5) { ForEach(tags, id: \.self) { InfoTag(text: $0, size: size) } }
        }
    }
}


/// Eine Zeile wie in der großen Übersichtskarte: helle Fläche, Symbol bzw. Foto, Name, Angaben als Schildchen.
/// Am Geburtstag selbst darunter „Anrufen“ (mit Nummer, mit Nachfrage) und „Nachricht“ – vorher ergibt das keinen Sinn.
struct EventItemCard: View {
    let event: CalendarEvent
    var person: Person? = nil
    var size: CGFloat = 36
    var showLocation = false
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var confirmCall = false

    private var callURL: URL? { CallLink.url(person?.phone) }
    private var messageURL: URL? { NotificationManager.greetingURL(name: person?.name ?? event.title, phone: person?.phone) }
    private var showsActions: Bool { event.kind == .birthday && Days.until(event.date) == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    leading
                    VStack(alignment: .leading, spacing: 4) {
                        Text(EventText.title(event)).font(KlarStyle.font(17, .heavy)).foregroundStyle(KlarStyle.text(scheme))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        InfoTags(tags: EventText.tags(event, person: person, showLocation: showLocation))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Eigene Reihe über die volle Breite – nimmt Name und Angaben keinen Platz weg
            if showsActions {
                HStack(spacing: 8) {
                    if let url = callURL {
                        actionButton("phone.fill", label: L10n.t("Anrufen", "Call"), color: .green) { confirmCall = true }
                            .callConfirmation(isPresented: $confirmCall, name: person?.name ?? event.title, url: url)
                    }
                    if let url = messageURL {
                        actionButton("message.fill", label: L10n.t("Nachricht", "Message"), color: .blue) { openURL(url) }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground).opacity(scheme == .dark ? 0.6 : 0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(event.kind == .waste && event.done ? 0.55 : 1)
    }

    @ViewBuilder
    private var leading: some View {
        switch event.kind {
        case .waste: BinDot(symbolName: event.symbolName, colorHex: event.colorHex, name: event.title, size: size)
        case .birthday: PersonAvatar(person: person, initials: NameText.initials(event.title), colorHex: event.colorHex, size: size)
        case .custom: SymbolBadge(symbolName: event.symbolName, colorHex: event.colorHex, size: size)
        }
    }

    private func actionButton(_ symbol: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol).font(KlarStyle.font(15, .heavy)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
