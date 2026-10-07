import Foundation
import ActivityKit
import TonneCore

/// Live-Aktivität „Tonne rausstellen“ am Vorabend, beendet nach der Abholung.
///
/// Ab iOS 26 plant die App bei jedem Öffnen die nächsten Abende im Voraus; iOS startet die Aktivität
/// dann zur Abendzeit selbst – ohne dass die App offen ist und ohne Einrichtung. Vor iOS 26 kann eine
/// Live-Aktivität nur bei geöffneter App starten (oder über den Kurzbefehl StartPickupLiveActivityIntent).
@MainActor
enum LiveActivityManager {
    /// Was danach auf dem Sperrbildschirm steht – für die Antwort des Kurzbefehls.
    enum Outcome { case shown(names: [String]), nothingDue, alreadyDone, disabled, failed }

    struct Result {
        var outcome: Outcome
        /// Abholtage, für die iOS die Aktivität am Abend selbst startet. Sie melden sich mit eigenem Hinweis,
        /// die Abend-Mitteilung für diese Tage entfällt.
        var scheduledDays: Set<String> = []
    }

    static var canSchedule: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    @discardableResult
    static func refresh(with snapshot: WidgetSnapshot, eveningMinutes: Int, showTomorrowNow: Bool = false) async -> Result {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return Result(outcome: .disabled) }
        let entries = LiveActivityPlanner.plan(pickupDays: snapshot.pickupDays, eveningMinutes: eveningMinutes,
                                               canSchedule: canSchedule, showTomorrowNow: showTomorrowNow)
        let wanted = Dictionary(entries.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
        let doneKeys = Set(snapshot.pickupDays.filter(\.done).map { Days.iso($0.date) })
        var result = Result(outcome: .nothingDue)

        // Bestehende Aktivitäten: erledigte ausklingen lassen, nicht mehr gewünschte oder umgeplante beenden.
        var keep: [String: Activity<PickupActivityAttributes>] = [:]
        for activity in Activity<PickupActivityAttributes>.activities {
            let key = activity.attributes.dayKey
            if doneKeys.contains(key) {
                var state = activity.content.state
                state.done = true
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(1800)))
                if Days.until(activity.attributes.pickupDate) <= 1 { result.outcome = .alreadyDone }
            } else if let entry = wanted[key], keep[key] == nil, isCompatible(activity, with: entry) {
                keep[key] = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        for entry in entries {
            let state = PickupActivityAttributes.ContentState(
                names: entry.day.items.map(\.name),
                symbolNames: entry.day.items.map(\.displaySymbol),
                colorHexes: entry.day.items.map(\.colorHex),
                done: false
            )
            let end = Days.at(minutes: 12 * 60, on: entry.day.date) ?? entry.day.date.addingTimeInterval(12 * 3600)
            let content = ActivityContent(state: state, staleDate: end)
            if let existing = keep[entry.dayKey] {
                await existing.update(content)
            } else if let start = entry.start {
                guard request(entry: entry, content: content, start: start) else { continue }
            } else {
                let attributes = PickupActivityAttributes(dayKey: entry.dayKey, pickupDate: entry.day.date, locationName: entry.day.items.first?.locationName)
                do { _ = try Activity.request(attributes: attributes, content: content, pushType: nil) } catch {
                    result.outcome = .failed
                    continue
                }
            }
            if entry.start == nil {
                result.outcome = .shown(names: state.names)
            } else {
                result.scheduledDays.insert(entry.dayKey)
            }
        }
        return result
    }

    /// Passt eine laufende oder geplante Aktivität noch zum Plan? Eine geplante mit anderer Startzeit
    /// (z. B. Abendzeit geändert) oder eine geplante, die jetzt sofort erscheinen soll, wird neu angelegt.
    private static func isCompatible(_ activity: Activity<PickupActivityAttributes>, with entry: LiveActivityPlanner.Entry) -> Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), activity.activityState == .pending {
            return activity.attributes.scheduledStart == entry.start
        }
        #endif
        return true
    }

    /// Plant die Aktivität für den Abend (iOS 26+). iOS startet sie dann selbst und meldet sich mit dem Hinweis.
    private static func request(entry: LiveActivityPlanner.Entry, content: ActivityContent<PickupActivityAttributes.ContentState>, start: Date) -> Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let attributes = PickupActivityAttributes(dayKey: entry.dayKey, pickupDate: entry.day.date,
                                                      locationName: entry.day.items.first?.locationName, scheduledStart: start)
            let text = ReminderPlanner.eveningText(names: entry.day.items.map(\.name))
            let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: text.title),
                                           body: LocalizedStringResource(stringLiteral: text.body), sound: .default)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil, style: .standard, alertConfiguration: alert, start: start)
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }

    static func endAll() async {
        for activity in Activity<PickupActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
