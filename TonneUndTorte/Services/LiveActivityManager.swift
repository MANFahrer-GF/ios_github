import Foundation
import ActivityKit
import TonneCore

/// Startet am Vorabend eine Live-Aktivität „Tonne rausstellen“ und beendet sie nach der Abholung.
/// Live-Aktivitäten können nur gestartet werden, während die App geöffnet ist – deshalb wird bei
/// jedem Aktivwerden der App geprüft, ob eine fällig ist. Ohne die App zu öffnen geht es über
/// StartPickupLiveActivityIntent (Kurzbefehle-Automation am Abend, Siri, Aktionstaste).
@MainActor
enum LiveActivityManager {
    /// Ergebnis für den Kurzbefehl: was danach auf dem Sperrbildschirm steht.
    enum Outcome { case shown(names: [String]), nothingDue, alreadyDone, disabled, failed }

    @discardableResult
    static func refresh(with snapshot: WidgetSnapshot) async -> Outcome {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }
        let today = Days.today()
        let tomorrow = Days.add(1, to: today)
        // Relevante Abholung: heute (bis mittags) oder morgen
        let candidate = snapshot.pickupDays.first { day in
            let d = Days.start(of: day.date)
            return d == tomorrow || (d == today && Calendar.current.component(.hour, from: Date()) < 12)
        }
        let running = Activity<PickupActivityAttributes>.activities

        guard let candidate else {
            for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
            return .nothingDue
        }
        let dayKey = Days.iso(candidate.date)
        let state = PickupActivityAttributes.ContentState(
            names: candidate.items.map(\.name),
            symbolNames: candidate.items.map(\.displaySymbol),
            colorHexes: candidate.items.map(\.colorHex),
            done: candidate.done
        )
        // Alte Aktivitäten anderer Tage beenden
        for activity in running where activity.attributes.dayKey != dayKey {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let existing = running.first(where: { $0.attributes.dayKey == dayKey }) {
            await existing.update(ActivityContent(state: state, staleDate: nil))
            if candidate.done {
                await existing.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(1800)))
                return .alreadyDone
            }
            return .shown(names: state.names)
        }
        guard !candidate.done else { return .alreadyDone }
        let attributes = PickupActivityAttributes(dayKey: dayKey, pickupDate: candidate.date, locationName: candidate.items.first?.locationName)
        let end = Days.at(minutes: 12 * 60, on: candidate.date) ?? candidate.date.addingTimeInterval(12 * 3600)
        do {
            _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: end), pushType: nil)
            return .shown(names: state.names)
        } catch {
            return .failed
        }
    }

    static func endAll() async {
        for activity in Activity<PickupActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
