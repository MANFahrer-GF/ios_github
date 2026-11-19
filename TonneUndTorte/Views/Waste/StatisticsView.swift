import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TonneCore

/// Leerungs-Statistik: je Müllart, wie oft rausgestellt – mit Freileerungen, wenn ein Kontingent eingetragen ist.
/// Ruhig in der Hausform: keine Punkte, keine Ranglisten.
struct StatisticsView: View {
    /// Nur ein Standort (aus Müll › Standort), sonst alle.
    var locationID: UUID?
    @EnvironmentObject private var model: AppModel
    @Query(sort: \Location.sortOrder) private var locations: [Location]
    @Query(sort: \WasteType.sortOrder) private var wasteTypes: [WasteType]
    @Environment(\.colorScheme) private var scheme
    @State private var showPrevious = false
    @State private var settingsFor: WasteType?
    @State private var extraFor: WasteType?
    @State private var extraDate = Days.today()
    @State private var showCatchUp = false
    /// „Einzeln nachtragen“ im Kontingent-Blatt: danach die Nachtragen-Liste dieser Müllart öffnen
    @State private var catchUpType: WasteType?
    @State private var catchUpAfterSettings: WasteType?
    @State private var token = 0

    private var allTypes: [WasteType] {
        _ = token
        return wasteTypes.filter { $0.isActive && (locationID == nil || $0.location?.id == locationID) }
            .sorted { ($0.location?.sortOrder ?? 0, $0.sortOrder) < ($1.location?.sortOrder ?? 0, $1.sortOrder) }
    }
    /// Ohne die mit „Kein Kontingent“ ausgeblendeten.
    private var types: [WasteType] { allTypes.filter { !$0.hidesInStatistics } }
    private var hiddenTypes: [WasteType] { allTypes.filter(\.hidesInStatistics) }
    private var showLocation: Bool { locationID == nil && locations.count > 1 }
    private var today: Date { Days.today() }

    private func period(_ type: WasteType) -> QuotaPeriod {
        let current = type.quotaPeriod(containing: today)
        return showPrevious ? PickupQuota.previous(current, anchor: type.quotaStart) : current
    }

    private var summaries: [(type: WasteType, summary: QuotaSummary)] {
        types.map { ($0, $0.quotaSummary(period: period($0), today: today)) }
    }

    var body: some View {
        let items = summaries
        ScrollView {
            VStack(spacing: 20) {
                header
                if allTypes.isEmpty {
                    Text(L10n.t("Noch keine Müllarten. Lege unter „Müll“ einen Standort an.", "No waste types yet. Add a location under “Waste”."))
                        .tonneFont(.subheadline).foregroundStyle(.secondary).card()
                } else {
                    if !types.isEmpty && !types.contains(where: \.isCounted) { explanationCard }
                    ForEach(items, id: \.type.id) { item in
                        QuotaCard(type: item.type, summary: item.summary, showLocation: showLocation, editable: true,
                                  onSet: { mark, day in set(mark, item.type, day) },
                                  onRemoveExtra: { day in item.type.removeExtraPickup(day); persist() },
                                  onSettings: { settingsFor = item.type },
                                  onAddExtra: { extraDate = today; extraFor = item.type },
                                  onHide: { setHidden(true, item.type) })
                    }
                    footer(items)
                }
            }
            .limitedWidth()
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.t("Leerungen", "Collections"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $settingsFor, onDismiss: {
            token += 1
            if let type = catchUpAfterSettings { catchUpAfterSettings = nil; catchUpType = type }
        }) { type in QuotaSettingsView(type: type, onCatchUp: { catchUpAfterSettings = type }).appTypography() }
        .sheet(item: $catchUpType, onDismiss: { token += 1 }) { type in CatchUpSheet(typeID: type.id) }
        .sheet(item: $extraFor, onDismiss: { token += 1 }) { type in extraSheet(type).appTypography() }
        .sheet(isPresented: $showCatchUp, onDismiss: { token += 1 }) { CatchUpSheet(locationID: locationID) }
    }

    // MARK: - Kopf

    private var header: some View {
        let year = Calendar.current.component(.year, from: today)
        return VStack(alignment: .leading, spacing: 10) {
            if let id = locationID, let location = locations.first(where: { $0.id == id }) {
                Label(location.name, systemImage: location.symbolName).tonneFont(.subheadline, .semibold).foregroundStyle(.secondary)
            }
            Picker(L10n.t("Zeitraum", "Period"), selection: $showPrevious) {
                Text(String(year)).tag(false)
                Text(String(year - 1)).tag(true)
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("So wird gezählt", "How counting works")).tonneFont(.headline)
            Text(L10n.t("Jedes „Erledigt“ zählt als Leerung der Müllart, „Diesmal nicht“ als nicht rausgestellt. Trag ein, wie viele Leerungen dein Tarif im Jahr enthält – dann siehst du, wie viele noch frei sind.",
                        "Every “Done” counts as a collection of that waste type, “Not this time” as not put out. Enter how many collections your plan includes per year to see how many are left."))
                .tonneFont(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let first = types.first(where: { $0.category == .residual }) ?? types.first(where: { $0.handling != .bringTo }) ?? types.first {
                Button(L10n.t("Kontingent einrichten", "Set up included collections")) { settingsFor = first }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Unten

    private func footer(_ items: [(type: WasteType, summary: QuotaSummary)]) -> some View {
        let open = items.reduce(0) { $0 + $1.summary.open + $1.summary.bulk }
        let comparison = previousYearLine(items)
        return VStack(alignment: .leading, spacing: 14) {
            if open > 0 && !showPrevious {
                Button { showCatchUp = true } label: {
                    Label(L10n.t("\(L10n.count(open, "Termin", "Termine", "date", "dates")) offen – nachtragen", "\(L10n.count(open, "Termin", "Termine", "date", "dates")) open – catch up"),
                          systemImage: "questionmark.circle")
                        .tonneFont(.subheadline, .semibold)
                }
                .accessibilityIdentifier("statsCatchUp")
            }
            if let comparison { Text(comparison).tonneFont(.footnote).foregroundStyle(.secondary) }
            if !hiddenTypes.isEmpty {
                Menu {
                    Section(L10n.t("Wieder zeigen", "Show again")) {
                        ForEach(hiddenTypes, id: \.id) { type in
                            Button(showLocation ? "\(type.name) · \(type.location?.name ?? "")" : type.name) { setHidden(false, type) }
                        }
                    }
                } label: {
                    Label(L10n.t("\(hiddenTypes.count) ohne Kontingent ausgeblendet", "\(hiddenTypes.count) hidden without included collections"),
                          systemImage: "eye.slash").tonneFont(.subheadline, .semibold)
                }
                .accessibilityIdentifier("statsHidden")
            }
            ShareLink(item: PickupCSVFile(text: model.statisticsCSV(locationID: locationID), fileName: L10n.t("Leerungen.csv", "Collections.csv")),
                      preview: SharePreview(L10n.t("Leerungen.csv", "Collections.csv"))) {
                Label(L10n.t("Als CSV exportieren", "Export as CSV"), systemImage: "square.and.arrow.up").tonneFont(.subheadline, .semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// „Bis zum gleichen Tag im Vorjahr: 6 Leerungen (jetzt 7)“ – eine Zeile, über alle gezeigten Müllarten.
    private func previousYearLine(_ items: [(type: WasteType, summary: QuotaSummary)]) -> String? {
        guard !showPrevious else { return nil }
        let lastYearToday = Calendar.current.date(byAdding: .year, value: -1, to: today) ?? today
        var now = 0, before = 0
        for item in items {
            now += item.summary.used
            let previous = PickupQuota.previous(item.summary.period, anchor: item.type.quotaStart).through(lastYearToday)
            before += item.type.quotaSummary(period: previous, today: lastYearToday).used
        }
        guard before > 0 || now > 0 else { return nil }
        return L10n.t("Bis zum gleichen Tag im Vorjahr: \(before) \(before == 1 ? "Leerung" : "Leerungen") (jetzt \(now))",
                      "Same day last year: \(before) \(before == 1 ? "collection" : "collections") (now \(now))")
    }

    // MARK: - Zusatzleerung

    private func extraSheet(_ type: WasteType) -> some View {
        NavigationStack {
            VStack {
                DatePicker(L10n.t("Leerung am", "Collection on"), selection: $extraDate, in: ...Days.add(365, to: today), displayedComponents: .date)
                    .datePickerStyle(.graphical).padding()
                Text(L10n.t("Für Leerungen, die nicht im Kalender stehen (bestellte Sonderleerung, verschobener Termin). Zählt wie ein normaler Termin.",
                            "For collections that aren't in the calendar (ordered extra collection, moved date). Counts like a regular one."))
                    .tonneFont(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                Spacer()
            }
            .navigationTitle(L10n.t("Leerung hinzufügen", "Add collection")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("Abbrechen", "Cancel")) { extraFor = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Hinzufügen", "Add")) { type.addExtraPickup(extraDate); persist(); extraFor = nil }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func set(_ mark: PickupMark, _ type: WasteType, _ day: Date) {
        Haptics.tap()
        Task { await model.setPickupMark(mark, wasteTypeID: type.id, day: day); token += 1 }
    }

    private func persist() {
        model.save()
        token += 1
        Task { await model.refreshAll() }
    }

    private func setHidden(_ hidden: Bool, _ type: WasteType) {
        withAnimation { type.hiddenInStatistics = hidden; model.save(); token += 1 }
    }
}

// MARK: - Karte je Müllart

struct QuotaCard: View {
    let type: WasteType
    let summary: QuotaSummary
    var showLocation = false
    var editable = true
    var onSet: (PickupMark, Date) -> Void
    var onRemoveExtra: (Date) -> Void
    var onSettings: () -> Void
    var onAddExtra: () -> Void
    /// „Kein Kontingent“: Müllart aus der Übersicht ausblenden (nil = Knopf fehlt).
    var onHide: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder private var quotaChoice: some View {
        // Als Knöpfe mit Fläche: Als blanker Text sah man nicht, dass man tippen kann (Thomas 19.11.2026)
        Button(L10n.t("Kontingent einrichten", "Set up included collections"), action: onSettings)
            .tonneFont(.subheadline, .semibold)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("quotaSetup-\(type.name)")
        if let onHide, type.neverCounted {
            Button(L10n.t("Kein Kontingent", "None included"), action: onHide)
                .tonneFont(.subheadline, .semibold)
                .buttonStyle(.bordered)
                .accessibilityHint(L10n.t("Blendet \(type.name) in den Leerungen aus", "Hides \(type.name) from collections"))
                .accessibilityIdentifier("quotaNone-\(type.name)")
        }
    }

    private var alert: Color { scheme == .dark ? Color(hex: "#FF6B5E") : Color(hex: "#D93025") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                BinDot(symbolName: type.displaySymbol, colorHex: type.colorHex, name: type.name, size: 30).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(type.name).tonneFont(size: 17, .heavy).foregroundStyle(KlarStyle.text(scheme))
                    if showLocation, let location = type.location?.name {
                        Text(location).tonneFont(size: 12, .bold).foregroundStyle(KlarStyle.muted(scheme))
                    }
                }
                Spacer(minLength: 0)
                if summary.period.label() != String(Calendar.current.component(.year, from: summary.period.start)) || type.quotaStart != nil {
                    Text(summary.period.label()).tonneFont(size: 12, .bold).foregroundStyle(KlarStyle.muted(scheme))
                }
                Button(action: onSettings) {
                    Image(systemName: "slider.horizontal.3").tonneFont(size: 16, .semibold).foregroundStyle(KlarStyle.muted(scheme))
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Kontingent für \(type.name) einstellen", "Included collections for \(type.name)"))
                .accessibilityIdentifier("quotaSettings-\(type.name)")
            }
            if let included = summary.included {
                HStack(alignment: .center, spacing: 16) {
                    QuotaRing(used: summary.used, included: included, exhausted: summary.isExhausted, tint: summary.isExhausted ? alert : KlarStyle.ink(type.colorHex, scheme))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PickupQuota.headline(summary)).tonneFont(size: 22, .black).foregroundStyle(KlarStyle.text(scheme))
                            .accessibilityIdentifier("quotaHeadline-\(type.name)")
                        Text(detailLine).tonneFont(size: 13, .bold).foregroundStyle(KlarStyle.muted(scheme)).fixedSize(horizontal: false, vertical: true)
                        if let prognosis = prognosisLine {
                            Text(prognosis).tonneFont(size: 13, .semibold).foregroundStyle(KlarStyle.muted(scheme)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                if summary.isExhausted {
                    Label(exhaustedLine, systemImage: "exclamationmark.circle.fill")
                        .tonneFont(size: 13, .bold).foregroundStyle(alert).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(PickupQuota.headline(summary)).tonneFont(size: 15, .heavy).foregroundStyle(KlarStyle.text(scheme))
                        .accessibilityIdentifier("quotaHeadline-\(type.name)")
                    // Nur ohne Kontingent: Im Vorjahr einer gezählten Müllart fehlt es nur für diesen Zeitraum
                    if editable && !type.isCounted {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { quotaChoice }
                            VStack(alignment: .leading, spacing: 8) { quotaChoice }
                        }
                    }
                }
            }
            if !summary.entries.isEmpty {
                YearStrip(type: type, entries: summary.entries, editable: editable, onSet: onSet, onRemoveExtra: onRemoveExtra)
            }
            HStack(alignment: .firstTextBaseline) {
                if editable {
                    Button(action: onAddExtra) { Label(L10n.t("Leerung hinzufügen", "Add collection"), systemImage: "plus.circle").tonneFont(size: 13, .bold) }
                        .accessibilityIdentifier("addExtra-\(type.name)")
                }
                Spacer(minLength: 8)
                if let baseline = type.quotaBaseline, let date = type.quotaBaselineDate, summary.period.contains(Days.start(of: date)) {
                    Text(L10n.t("bis \(DateText.short(date)) laut Angabe: \(baseline)", "until \(DateText.short(date)) as entered: \(baseline)"))
                        .tonneFont(size: 12, .bold).foregroundStyle(KlarStyle.muted(scheme))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            KlarSurface(tintHex: type.colorHex)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 16, x: 0, y: 6)
        )
        // Kontingent erreicht: rot umrandet (zusätzlich zum Text, nicht nur über die Farbe)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(alert, lineWidth: summary.isExhausted ? 2 : 0))
    }

    private var detailLine: String {
        PickupQuota.freeAndRemainingLine(summary, today: Days.today())
    }

    private var prognosisLine: String? {
        switch summary.prognosis {
        case .none, .exhausted: return nil
        case .lastsUntilEnd: return L10n.t("Bei gleichem Tempo reicht es bis zum Jahresende.", "At this pace it lasts until the end of the year.")
        case .runsOut(let date):
            let month = date.formatted(.dateTime.month(.wide))
            return L10n.t("Bei gleichem Tempo reicht es bis etwa \(month).", "At this pace it lasts until about \(month).")
        }
    }

    private var exhaustedLine: String {
        var text = L10n.t("Jede weitere Leerung kostet extra.", "Every further collection costs extra.")
        if summary.overBy > 0, let cost = summary.extraCost {
            let price = cost.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR"))
            text += " " + L10n.t("\(L10n.count(summary.overBy, "Zusatzleerung", "Zusatzleerungen", "extra collection", "extra collections")) ≈ \(price)",
                                 "\(L10n.count(summary.overBy, "Zusatzleerung", "Zusatzleerungen", "extra collection", "extra collections")) ≈ \(price)")
        }
        return text
    }
}

/// Fortschrittsring „7 von 12“.
struct QuotaRing: View {
    let used: Int
    let included: Int
    let exhausted: Bool
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().stroke(KlarStyle.hairline(scheme), lineWidth: 7)
            Circle().trim(from: 0, to: included > 0 ? min(1, CGFloat(used) / CGFloat(included)) : 1)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: exhausted ? "exclamationmark" : "arrow.up.bin.fill")
                .tonneFont(size: 16, .bold).foregroundStyle(tint)
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }
}

// MARK: - Jahresleiste

/// Ein Punkt je Termin: voll = raus, Ring = nicht raus, grau mit ? = offen, blass = kommt noch.
/// Antippen ändert den Termin. Zustände auch per Form und Text, nicht nur per Farbe.
struct YearStrip: View {
    let type: WasteType
    let entries: [QuotaEntry]
    var editable = true
    var onSet: (PickupMark, Date) -> Void
    var onRemoveExtra: (Date) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 44), spacing: 4)], alignment: .leading, spacing: 8) {
            ForEach(entries, id: \.date) { entry in
                if editable && !entry.upcoming && !entry.coveredByBaseline {
                    Menu {
                        Button { onSet(.out, entry.date) } label: { Label(L10n.t("Raus", "Out"), systemImage: "checkmark.circle.fill") }
                        Button { onSet(.notOut, entry.date) } label: { Label(L10n.t("Nicht raus", "Not out"), systemImage: "circle") }
                        Button { onSet(.open, entry.date) } label: { Label(L10n.t("Offen", "Open"), systemImage: "questionmark.circle") }
                        if entry.isExtra {
                            Button(role: .destructive) { onRemoveExtra(entry.date) } label: { Label(L10n.t("Zusatzleerung entfernen", "Remove extra collection"), systemImage: "trash") }
                        }
                    } label: { cell(entry) }
                    .accessibilityIdentifier("dot-\(type.name)-\(Days.iso(entry.date))")
                } else {
                    cell(entry)
                }
            }
        }
    }

    private func cell(_ entry: QuotaEntry) -> some View {
        let color = KlarStyle.ink(type.colorHex, scheme)
        return VStack(spacing: 3) {
            ZStack {
                switch (entry.upcoming, entry.mark) {
                case (true, _):
                    Circle().strokeBorder(KlarStyle.muted(scheme).opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                case (false, .out):
                    Circle().fill(color)
                    Image(systemName: entry.isExtra ? "plus" : "checkmark").tonneFont(fixed: 11, .heavy).foregroundStyle(HexLuma.glyphColor(on: type.colorHex))
                case (false, .notOut):
                    Circle().strokeBorder(color, lineWidth: 2)
                case (false, .open):
                    Circle().fill(KlarStyle.muted(scheme).opacity(0.25))
                    Image(systemName: "questionmark").tonneFont(fixed: 11, .heavy).foregroundStyle(KlarStyle.muted(scheme))
                }
                if entry.bulkConfirmed {
                    Circle().fill(.orange).frame(width: 9, height: 9).offset(x: 9, y: -9)
                }
            }
            .frame(width: 26, height: 26)
            .opacity(entry.coveredByBaseline ? 0.35 : 1)
            Text(entry.date.formatted(.dateTime.day().month(.defaultDigits)))
                .tonneFont(fixed: 9, .semibold).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
        }
        .frame(minWidth: 34, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QuotaText.spoken(entry))
    }
}

enum QuotaText {
    /// VoiceOver: „11. November, rausgestellt“.
    static func spoken(_ entry: QuotaEntry) -> String {
        let date = entry.date.formatted(.dateTime.day().month(.wide))
        var state: String
        if entry.coveredByBaseline { state = L10n.t("im Startwert enthalten", "included in the starting value") }
        else if entry.upcoming { state = L10n.t("kommt noch", "upcoming") }
        else {
            switch entry.mark {
            case .out: state = L10n.t("rausgestellt", "put out")
            case .notOut: state = L10n.t("nicht rausgestellt", "not put out")
            case .open: state = L10n.t("offen, nichts eingetragen", "open, nothing entered")
            }
        }
        if entry.isExtra { state += L10n.t(", Zusatzleerung", ", extra collection") }
        if entry.bulkConfirmed { state += L10n.t(", pauschal bestätigt", ", confirmed for the whole day") }
        if entry.offDuty { state += L10n.t(", jemand anderes ist dran", ", someone else's turn") }
        return "\(date), \(state)"
    }
}

// MARK: - Nachtragen

/// Offene oder pauschal bestätigte Termine mit „Raus“ / „Nicht raus“ – auf der Übersicht und in der Statistik.
/// Vergangene, noch offene Termine zum Nachtragen („Raus“ / „Nicht raus“) – aus der Statistik oder direkt nach dem
/// Einrichten eines Kontingents („Einzeln nachtragen“, dann nur diese Müllart).
struct CatchUpSheet: View {
    var locationID: UUID?
    var typeID: UUID?
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = 0

    var body: some View {
        let _ = token
        let items = model.openItems(locationID: locationID).filter { typeID == nil || $0.type.id == typeID }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !items.isEmpty {
                        Text(L10n.t("Stand die Tonne an diesen Tagen draußen? Jedes „Raus“ zählt als Leerung.",
                                    "Was the bin out on these days? Every “Out” counts as a collection."))
                            .tonneFont(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    CatchUpList(items: items) { token += 1 }
                }
                .padding()
            }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(L10n.t("Nachtragen", "Catch up")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.t("Fertig", "Done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .appTypography()
    }
}

struct CatchUpList: View {
    let items: [AppModel.QuotaItem]
    var limit: Int = .max
    var onChange: () -> Void = {}
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                Text(L10n.t("Alles eingetragen.", "All caught up.")).tonneFont(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(items.prefix(limit)) { item in
                HStack(spacing: 10) {
                    BinDot(symbolName: item.type.displaySymbol, colorHex: item.type.colorHex, name: item.type.name, size: 26).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.type.name).tonneFont(size: 15, .heavy).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1)
                        Text(item.bulk ? L10n.t("\(DateText.short(item.date)) · pauschal bestätigt", "\(DateText.short(item.date)) · confirmed for the day")
                                       : DateText.short(item.date))
                            .tonneFont(size: 12, .bold).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 4)
                    Button(L10n.t("Raus", "Out")) { set(.out, item) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .accessibilityLabel(L10n.t("\(item.type.name) am \(DateText.short(item.date)): raus", "\(item.type.name) on \(DateText.short(item.date)): out"))
                        .accessibilityIdentifier("catchUpOut-\(item.type.name)-\(Days.iso(item.date))")
                    Button(L10n.t("Nicht raus", "Not out")) { set(.notOut, item) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel(L10n.t("\(item.type.name) am \(DateText.short(item.date)): nicht raus", "\(item.type.name) on \(DateText.short(item.date)): not out"))
                        .accessibilityIdentifier("catchUpNotOut-\(item.type.name)-\(Days.iso(item.date))")
                }
            }
        }
    }

    private func set(_ mark: PickupMark, _ item: AppModel.QuotaItem) {
        Haptics.tap()
        Task { await model.setPickupMark(mark, wasteTypeID: item.type.id, day: item.date); onChange() }
    }
}

// MARK: - Einstellungen

/// Kontingent, Gebührenjahr, Preis, Tonnendienst und Startwert einer Müllart.
struct QuotaSettingsView: View {
    @Bindable var type: WasteType
    /// „Einzeln nachtragen“ gewählt: Der Aufrufer öffnet nach dem Schließen die Nachtragen-Liste.
    var onCatchUp: () -> Void = {}
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var included = 12
    @State private var ownYear = false
    @State private var cutoff = Days.today()
    @State private var price = ""
    @State private var askBaseline = false
    @State private var baselineText = ""
    // Erst bei „Fertig“ ins Modell – „Abbrechen“ nimmt alles zurück
    @State private var countOffDuty = false
    @State private var baseline: Int?
    @State private var baselineDate: Date?
    @State private var askedOnFinish = false
    private let wasCounted: Bool

    init(type: WasteType, onCatchUp: @escaping () -> Void = {}) {
        self.type = type
        self.onCatchUp = onCatchUp
        wasCounted = type.isCounted
        _enabled = State(initialValue: type.isCounted)
        _included = State(initialValue: type.includedPerYear ?? 12)
        _ownYear = State(initialValue: type.quotaStart != nil)
        _cutoff = State(initialValue: type.quotaStart ?? Days.today())
        _price = State(initialValue: type.pricePerExtra.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "")
        _countOffDuty = State(initialValue: type.countOffDuty)
        _baseline = State(initialValue: type.quotaBaseline)
        _baselineDate = State(initialValue: type.quotaBaselineDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L10n.t("Leerungen inklusive", "Included collections"), isOn: $enabled)
                    if enabled {
                        Stepper(value: $included, in: 0...104) {
                            Text(L10n.t("\(included) pro Jahr", "\(included) per year")).tonneFont(.body)
                        }
                        .accessibilityIdentifier("quotaStepper")
                    }
                } footer: {
                    Text(L10n.t("Wie viele Leerungen dein Tarif im Jahr enthält. Jede weitere kostet meist extra.",
                                "How many collections your plan includes per year. Further ones usually cost extra."))
                }
                if enabled {
                    Section {
                        Toggle(L10n.t("Zählung startet nicht am 1. Januar", "Count doesn't start on 1 January"), isOn: $ownYear)
                        if ownYear {
                            DatePicker(L10n.t("Zählung startet am", "Count starts on"), selection: $cutoff, displayedComponents: .date)
                        }
                    } footer: {
                        Text(L10n.t("Normalerweise zählen die Leerungen vom 1. Januar bis 31. Dezember. Zählt dein Entsorger ab einem anderen Tag, zum Beispiel ab deinem Einzug, stell ihn hier ein.",
                                    "Collections normally count from 1 January to 31 December. If your collector counts from another day, for example from when you moved in, set it here."))
                    }
                    Section {
                        TextField(L10n.t("Preis je Zusatzleerung", "Price per extra collection"), text: $price).keyboardType(.decimalPad)
                    } footer: { Text(L10n.t("Optional, z. B. 4,20.", "Optional, e.g. 4.20.")) }
                    if !type.dutyPeriods.isEmpty {
                        Section {
                            Toggle(L10n.t("Leerungen zählen auch, wenn ich nicht dran bin", "Count collections when it's not my turn"), isOn: $countOffDuty)
                        } footer: {
                            Text(L10n.t("Für eine geteilte Tonne: Die Tage der anderen stehen dann zum Nachtragen bereit.",
                                        "For a shared bin: the other days are then listed to catch up."))
                        }
                    }
                    if let baseline, let date = baselineDate {
                        Section(L10n.t("Startwert", "Starting value")) {
                            LabeledContent(L10n.t("bis \(DateText.short(date)) laut Angabe", "until \(DateText.short(date)) as entered"), value: "\(baseline)")
                            Button(L10n.t("Startwert ändern", "Change starting value")) { baselineText = "\(baseline)"; askBaseline = true }
                            Button(L10n.t("Startwert entfernen", "Remove starting value"), role: .destructive) { self.baseline = nil; baselineDate = nil }
                        }
                    } else {
                        Section {
                            Button(L10n.t("Bisher genutzte Leerungen angeben", "Enter collections used so far")) { baselineText = ""; askBaseline = true }
                        }
                    }
                }
            }
            .navigationTitle(type.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.t("Fertig", "Done")) { finish() } }
            }
            .alert(L10n.t("Wie viele Leerungen hast du dieses Jahr schon genutzt?", "How many collections have you used this year?"), isPresented: $askBaseline) {
                TextField(L10n.t("Anzahl", "Number"), text: $baselineText).keyboardType(.numberPad)
                // Nur mit gültiger Zahl: Leer oder ungültig hätte das Kontingent ohne Startwert gespeichert (Codex-Befund 1)
                Button(L10n.t("Zahl übernehmen", "Use number")) {
                    guard let value = enteredBaseline else { return }
                    baseline = value
                    baselineDate = Days.today()
                    if askedOnFinish { apply(); save() }
                }
                .disabled(enteredBaseline == nil)
                // Beim Einrichten: öffnet danach die Liste der vergangenen Termine dieser Müllart; eine eingetippte Zahl gilt dann
                // nicht (Thomas 19.11.2026, vorher schloss es nur das Blatt und verwarf die Zahl ohne Hinweis).
                // Über „Bisher genutzte Leerungen angeben“ gibt es nichts nachzutragen: dort ist es „Abbrechen“.
                if askedOnFinish {
                    Button(L10n.t("Stattdessen einzeln nachtragen", "Enter dates one by one instead"), role: .cancel) {
                        onCatchUp(); apply(); save()
                    }
                } else {
                    Button(L10n.t("Abbrechen", "Cancel"), role: .cancel) {}
                }
            } message: {
                if askedOnFinish {
                    Text(L10n.t("Die Zahl gilt als Startwert bis heute. Oder du gehst die vergangenen Termine einzeln durch („Raus“ oder „Nicht raus“) – dann wird keine Zahl verwendet.",
                                "The number counts as the starting value until today. Or go through past dates one by one (“Out” or “Not out”) – then no number is used."))
                } else {
                    Text(L10n.t("Die Zahl gilt als Startwert bis heute.", "The number counts as the starting value until today."))
                }
            }
        }
    }

    private var enteredBaseline: Int? {
        Int(baselineText.trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 0 ? $0 : nil }
    }

    private func finish() {
        // Mitten im Zeitraum eingeschaltet: einmal nach dem bisherigen Stand fragen – nur wenn es etwas nachzutragen gibt,
        // gezählt wie die Nachtragen-Liste (`AppModel.openItems`: Tonnendienst, schon markiert, Gebührenjahr), sonst öffnete
        // „Stattdessen einzeln nachtragen“ eine leere Liste (Codex-Befund 2). Die Einstellungen stehen dafür schon im Modell;
        // beide Antworten der Frage speichern.
        apply()
        if enabled && !wasCounted && baseline == nil {
            let today = Days.today()
            let open = type.quotaSummary(period: type.quotaPeriod(containing: today), today: today).entries
                .contains { !$0.upcoming && !$0.coveredByBaseline && ($0.mark == .open || $0.bulkConfirmed) }
            if open {
                baselineText = ""
                askedOnFinish = true
                askBaseline = true
                return
            }
        }
        save()
    }

    /// Alle Eingaben des Blatts auf einmal ins Modell.
    private func apply() {
        type.setIncluded(enabled ? included : nil)
        if enabled { type.hiddenInStatistics = false }
        type.quotaStart = enabled && ownYear ? Days.start(of: cutoff) : nil
        type.pricePerExtra = enabled ? Double(price.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) : nil
        type.countOffDuty = countOffDuty
        type.quotaBaseline = baseline
        type.quotaBaselineDate = baselineDate
    }

    private func save() {
        model.save()
        Task { await model.refreshAll() }
        dismiss()
    }
}

// MARK: - Erledigt je Müllart

/// „Erledigt“ an einem Tag mit gezählter und weiteren Müllarten: Häkchen je Müllart, alle vorausgewählt, ein Tipp „Fertig“.
struct DoneChoiceSheet: View {
    let day: Date
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var leftIn: Set<UUID> = []

    var body: some View {
        let types = model.doneChoiceTypes(day: day)
        NavigationStack {
            List {
                Section {
                    ForEach(types, id: \.id) { type in
                        let out = !leftIn.contains(type.id)
                        Button {
                            if out { leftIn.insert(type.id) } else { leftIn.remove(type.id) }
                        } label: {
                            HStack(spacing: 12) {
                                BinDot(symbolName: type.displaySymbol, colorHex: type.colorHex, name: type.name, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(type.name).tonneFont(.body, .semibold).foregroundStyle(.primary)
                                    if let line = model.quotaLine(for: type) { Text(line).tonneFont(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: out ? "checkmark.circle.fill" : "circle")
                                    .tonneFont(.title2).foregroundStyle(out ? Color.accentColor : .secondary)
                            }
                        }
                        .accessibilityLabel(type.name)
                        .accessibilityValue(out ? L10n.t("stand draußen", "was out") : L10n.t("blieb drin", "stayed in"))
                        .accessibilityAddTraits(out ? .isSelected : [])
                        .accessibilityIdentifier("choice-\(type.name)")
                    }
                } footer: {
                    Text(L10n.t("Was nicht abgehakt ist, zählt als „nicht rausgestellt“.", "Anything unticked counts as “not put out”."))
                }
            }
            .navigationTitle(L10n.t("Was stand draußen?", "What was out?")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Fertig", "Done")) {
                        Haptics.success()
                        let left = leftIn
                        Task { await model.markDone(dayKey: Days.iso(day), leftIn: left); dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
